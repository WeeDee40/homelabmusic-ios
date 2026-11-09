//
//  HLPocketID.swift
//  HomeLabMusic
//
//  «Mit Pocket ID anmelden» über den Einrichtungsdienst (einrichtung.bi-gerbers.ch), Phase 5 des Onboarding-Plans
//  (homelab-migration/PLAN-onboarding.md, «Schnittstelle für die Apps»):
//
//  1. Anmeldefenster (ASWebAuthenticationSession) auf
//     `GET /app/start?app=music&challenge=<base64url(SHA-256(verifier))>&geraet=<Name, max. 80>`.
//  2. Pocket ID fragt nach dem Passkey, danach zurück an `homelab-einrichtung://fertig?code=…` (oder `?fehler=…`).
//  3. Innert 2 Minuten, nur einmal: `POST /api/einloesen` `{"code", "verifier"}` →
//     `navidrome: {url, benutzer, header, token}`.
//
//  Die App speichert ein normales Subsonic-Konto (Benutzer, zufälliges Platzhalter-Passwort) und das Gerätetoken als
//  eigene Kopfzeile (`LoginCredentials.httpHeaders`). Amperfy schickt sie bei API, Stream, Cover und Download mit.
//  Caddy prüft sie per forward_auth beim Einrichtungsdienst und setzt `Remote-User`; Navidrome ignoriert dann `u`/`t`/`s`.
//  Widerrufen auf der Einrichtungsseite → Caddy antwortet 401 → die App bietet «Neu anmelden» an.
//  Admin-Konten (patrick) bekommen über den Dienst nie ein Token; für sie bleibt die Passwort-Anmeldung.
//

import AmperfyKit
import AuthenticationServices
import CryptoKit
import UIKit

enum HLPocketID {
  static let dienst = URL(string: "https://einrichtung.bi-gerbers.ch")!
  static let rueckkehrSchema = "homelab-einrichtung"
  /// Standard-Kopfzeile laut Schnittstelle; massgebend ist, was `/api/einloesen` liefert.
  static let standardKopfzeile = "x-homelab-geraet"

  struct Fehler: LocalizedError {
    let text: String
    var errorDescription: String? { text }
  }

  // MARK: Konto erkennen

  /// Gerätetoken eines Kontos (Kopfzeile ohne Rücksicht auf Gross-/Kleinschreibung), nil = Passwort-Konto.
  static func geraeteToken(_ cred: LoginCredentials?) -> (name: String, wert: String)? {
    guard let cred else { return nil }
    return cred.httpHeaders.first { $0.key.lowercased() == standardKopfzeile }.map { ($0.key, $0.value) }
  }

  @MainActor
  static func istPocketID(_ info: AccountInfo?) -> Bool {
    geraeteToken(AmperKit.shared.storage.settings.accounts.getSetting(info).read.loginCredentials) != nil
  }

  // MARK: Anmelden

  /// Ganzer Ablauf bis zu fertigen Zugangsdaten (noch nicht gespeichert).
  @MainActor
  static func anmelden(fenster: UIWindow?) async throws -> LoginCredentials {
    let verifier = zufall(48) // 64 Zeichen base64url
    let challenge = base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
    var start = URLComponents(
      url: dienst.appendingPathComponent("app/start"),
      resolvingAgainstBaseURL: false
    )!
    start.queryItems = [
      URLQueryItem(name: "app", value: "music"),
      URLQueryItem(name: "challenge", value: challenge),
      URLQueryItem(name: "geraet", value: String(geraetName.prefix(80))),
    ]
    let zurueck = try await browser(start.url!, fenster: fenster)
    let teile = URLComponents(url: zurueck, resolvingAgainstBaseURL: false)?.queryItems ?? []
    if let fehler = teile.first(where: { $0.name == "fehler" })?.value { throw Fehler(text: fehler) }
    guard let code = teile.first(where: { $0.name == "code" })?.value else {
      throw Fehler(text: "Die Anmeldung wurde nicht abgeschlossen.")
    }

    var r = URLRequest(url: dienst.appendingPathComponent("api/einloesen"))
    r.httpMethod = "POST"
    r.timeoutInterval = 30
    r.setValue("application/json", forHTTPHeaderField: "Content-Type")
    r.httpBody = try JSONEncoder().encode(["code": code, "verifier": verifier])
    let (daten, antwort) = try await URLSession.shared.data(for: r)

    struct Antwort: Decodable {
      struct Navidrome: Decodable { let url: String; let benutzer: String; let header: String; let token: String }
      let navidrome: Navidrome?
      let fehler: String?
    }
    let a = try? JSONDecoder().decode(Antwort.self, from: daten)
    guard (antwort as? HTTPURLResponse)?.statusCode == 200, let nd = a?.navidrome,
          !nd.benutzer.isEmpty, !nd.token.isEmpty, nd.url.isHyperTextProtocolProvided else {
      throw Fehler(text: a?.fehler ?? "Der Einrichtungsdienst hat keinen Zugang für Musik geliefert.")
    }

    // Platzhalter-Passwort: Navidrome prüft es nie (Caddy setzt Remote-User), es darf nur nicht leer sein.
    var cred = LoginCredentials(
      serverUrl: nd.url.trimmingCharacters(in: CharacterSet(charactersIn: "/")),
      username: nd.benutzer,
      password: "pocketid-" + zufall(24),
      backendApi: .subsonic
    )
    cred.httpHeaders = [nd.header.lowercased(): nd.token]
    return cred
  }

  private static var geraetName: String {
    #if targetEnvironment(macCatalyst)
      return "HomeLabMusic auf dem Mac"
    #else
      return "HomeLabMusic auf \(UIDevice.current.name)" // iOS 16+: «iPhone» bzw. «iPad»
    #endif
  }

  @MainActor
  private static func browser(_ url: URL, fenster: UIWindow?) async throws -> URL {
    let anker = Anker(fenster: fenster ?? AppDelegate.mainSceneDelegate?.window)
    return try await withCheckedThrowingContinuation { fortsetzung in
      let sitzung = ASWebAuthenticationSession(url: url, callbackURLScheme: rueckkehrSchema) { zurueck, fehler in
        if let zurueck {
          fortsetzung.resume(returning: zurueck)
        } else if let fehler = fehler as? ASWebAuthenticationSessionError, fehler.code == .canceledLogin {
          fortsetzung.resume(throwing: CancellationError())
        } else {
          fortsetzung.resume(throwing: Fehler(
            text: fehler?.localizedDescription ?? "Das Anmeldefenster ging nicht auf."
          ))
        }
      }
      sitzung.presentationContextProvider = anker
      sitzung.prefersEphemeralWebBrowserSession = false
      if !sitzung.start() {
        fortsetzung.resume(throwing: Fehler(text: "Das Anmeldefenster ging nicht auf."))
      }
      anker.sitzung = sitzung // bis zum Ende festhalten
    }
  }

  private final class Anker: NSObject, ASWebAuthenticationPresentationContextProviding {
    let fenster: UIWindow?
    var sitzung: ASWebAuthenticationSession?
    init(fenster: UIWindow?) { self.fenster = fenster }
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
      MainActor.assumeIsolated { fenster ?? ASPresentationAnchor() }
    }
  }

  // MARK: Bestehendes Konto erneuern (nach Widerruf) oder umstellen

  /// Neue Zugangsdaten für ein schon vorhandenes Konto übernehmen (gleicher Server und Benutzer).
  @MainActor
  static func uebernehmen(_ cred: LoginCredentials, fuer info: AccountInfo) {
    let app = AmperKit.shared
    let alt = app.storage.settings.accounts.getSetting(info).read.loginCredentials
    app.storage.settings.accounts.updateSetting(info) { s in
      var neu = s.loginCredentials ?? cred
      neu.changePasswordAndHash(password: cred.password)
      // eigene Kopfzeilen behalten, altes Gerätetoken ersetzen
      neu.httpHeaders = neu.httpHeaders.filter { $0.key.lowercased() != standardKopfzeile }
        .merging(cred.httpHeaders) { $1 }
      s.loginCredentials = neu
    }
    if let neu = app.storage.settings.accounts.getSetting(info).read.loginCredentials {
      (UIApplication.shared.delegate as? AppDelegate)?.getMeta(info).backendApi.provideCredentials(credentials: neu)
    }
    if let alt, let altToken = geraeteToken(alt), altToken.wert != geraeteToken(cred)?.wert {
      abmelden(alt) // altes Gerät beim Dienst entfernen (ist es schon widerrufen, schadet das nicht)
    }
    HLAPI.shared.medienwunschTokenVergessen()
    gesperrtGemeldet = false
  }

  /// Einstellungen → Konto: «Mit Pocket ID neu anmelden».
  @MainActor
  static func neuAnmelden(info: AccountInfo) async {
    do {
      let cred = try await anmelden(fenster: AppDelegate.mainSceneDelegate?.window)
      guard Account.createInfo(credentials: cred) == info else {
        meldung(
          "Anderes Konto",
          "Pocket ID hat dich als «\(cred.username)» angemeldet. Dieses Konto gehört jemand anderem. Füge dein Konto unter «Konto hinzufügen» hinzu."
        )
        abmelden(cred)
        return
      }
      uebernehmen(cred, fuer: info)
      meldung("Angemeldet", "Dieses Gerät ist wieder mit Pocket ID angemeldet.")
    } catch is CancellationError {
    } catch {
      meldung("Anmeldung fehlgeschlagen", error.localizedDescription)
    }
  }

  // MARK: Abmelden

  /// Gerät beim Einrichtungsdienst entfernen (Konto entfernen in den Einstellungen). Ohne Warten, Fehler egal.
  static func abmelden(_ cred: LoginCredentials?) {
    guard let token = geraeteToken(cred) else { return }
    var r = URLRequest(url: dienst.appendingPathComponent("api/abmelden"))
    r.httpMethod = "POST"
    r.timeoutInterval = 15
    r.setValue(token.wert, forHTTPHeaderField: token.name)
    URLSession.shared.dataTask(with: r).resume()
  }

  // MARK: Widerruf erkennen

  @MainActor private static var gesperrtGemeldet = false
  @MainActor private static var beobachter: NSObjectProtocol?

  /// Einmal beim Start: prüft beim Start und bei jeder Rückkehr in die App, ob das Gerät noch gilt.
  @MainActor
  static func einrichten() {
    guard beobachter == nil else { return }
    beobachter = NotificationCenter.default.addObserver(
      forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main
    ) { _ in
      Task { @MainActor in await pruefen() }
    }
    Task { @MainActor in await pruefen() }
  }

  @MainActor
  static func pruefen() async {
    let app = AmperKit.shared
    guard !gesperrtGemeldet, let info = app.storage.settings.accounts.active,
          let cred = app.storage.settings.accounts.getSetting(info).read.loginCredentials,
          let token = geraeteToken(cred),
          !app.storage.settings.user.isOfflineMode else { return }
    let server = cred.activeBackendServerUrl.isEmpty ? cred.serverUrl : cred.activeBackendServerUrl
    guard var teile = URLComponents(string: server.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/rest/ping")
    else { return }
    teile.queryItems = [URLQueryItem(name: "v", value: "1.16.1"), URLQueryItem(name: "c", value: "homelabmusic")]
    var r = URLRequest(url: teile.url!)
    r.timeoutInterval = 15
    r.setValue(token.wert, forHTTPHeaderField: token.name)
    // Nur ein klares 401 (Caddy: Gerät unbekannt oder abgemeldet) zählt; ohne Netz nichts melden.
    guard let (_, antwort) = try? await URLSession.shared.data(for: r),
          (antwort as? HTTPURLResponse)?.statusCode == 401 else { return }
    gesperrtGemeldet = true
    let alert = UIAlertController(
      title: "Gerät abgemeldet",
      message: "Dieses Gerät ist für «\(cred.username)» nicht mehr angemeldet (z. B. auf einrichtung.bi-gerbers.ch entfernt). Melde dich neu mit Pocket ID an, um wieder Musik zu hören.",
      preferredStyle: .alert
    )
    alert.addAction(UIAlertAction(title: "Mit Pocket ID anmelden", style: .default) { _ in
      Task { @MainActor in await neuAnmelden(info: info) }
    })
    alert.addAction(UIAlertAction(title: "Später", style: .cancel))
    zeigen(alert)
  }

  // MARK: Hilfen

  @MainActor
  private static func meldung(_ titel: String, _ text: String) {
    let alert = UIAlertController(title: titel, message: text, preferredStyle: .alert)
    alert.addAction(UIAlertAction(title: "OK", style: .default))
    zeigen(alert)
  }

  @MainActor
  private static func zeigen(_ vc: UIViewController) {
    var oben = AppDelegate.mainSceneDelegate?.window?.rootViewController
    while let weiter = oben?.presentedViewController, !weiter.isBeingDismissed { oben = weiter }
    oben?.present(vc, animated: true)
  }

  static func zufall(_ bytes: Int) -> String {
    var b = [UInt8](repeating: 0, count: bytes)
    _ = SecRandomCopyBytes(kSecRandomDefault, bytes, &b)
    return base64URL(Data(b))
  }

  private static func base64URL(_ d: Data) -> String {
    d.base64EncodedString().replacingOccurrences(of: "+", with: "-")
      .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
  }
}
