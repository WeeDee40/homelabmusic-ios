//
//  HLAPI.swift
//  HomeLabMusic
//
//  Schnittstelle zum Musikwunsch-Dienst (/entdecken/…): Suche, Künstler, Alben, Sender,
//  Wünsche. Die App meldet sich mit den Navidrome-Zugangsdaten des Amperfy-Kontos an
//  (Subsonic-Verfahren, Passwort wird nie übertragen) und bekommt das Token der Person.
//
//  This program is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//

import AmperfyKit
import CryptoKit
import Foundation
import Security
import UIKit

// MARK: - Modelle

struct HLSong: Codable, Hashable, Sendable {
  var typ: String
  var status: String
  var deezerId: Int?
  var titel: String?
  var kuenstler: String?
  var kuenstlerId: Int?
  var album: String?
  var albumId: Int?
  var bild: String?
  var bildGross: String?
  var dauer: Double?
  var vorschau: String?
  var navidromeId: String?
  var navidromeCover: String?

  var schluessel: String { "\(deezerId ?? 0)|\(navidromeId ?? "")" }
  var istVorschau: Bool { typ != "bibliothek" }
}

struct HLKuenstler: Codable, Hashable, Sendable {
  var id: Int
  var name: String
  var bild: String?
  var bildGross: String?
  var fans: Int?
  var inBibliothek: Int?
  var albenAnzahl: Int?
  var folgt: Bool?                                      // auf der SoulSync-Watchlist der Person
}

struct HLAlbum: Codable, Hashable, Sendable {
  var id: Int
  var titel: String?
  var bild: String?
  var bildGross: String?
  var jahr: String?
  var typ: String?
  var kuenstler: String?
  var kuenstlerId: Int?
  var anzahl: Int?
  var inBibliothek: Int?
  var jahrDatum: String?
  var vorhanden: Bool?                                  // Startseite: Album schon in der Bibliothek

  var typText: String {
    switch typ {
    case "single": return "Single"
    case "ep": return "EP"
    case "compile": return "Sammlung"
    default: return "Album"
    }
  }
}

struct HLJetzt: Codable, Sendable {
  var quelle: String
  var song: HLSong
}

struct HLAbschnitt: Codable, Hashable, Sendable {
  var titel: String
  var untertitel: String?
  var songs: [HLSong]
}

struct HLSuche: Codable, Sendable {
  var abschnitte: [HLAbschnitt]?                        // Genre oder Stimmung erkannt
  var schwerpunkt: String?                              // "genre", "stimmung" oder nil
  var kuenstler: [HLKuenstler]
  var songs: [HLSong]
  var alben: [HLAlbum]
}

struct HLKuenstlerSeite: Codable, Sendable {
  var kuenstler: HLKuenstler
  var top: [HLSong]
  var alben: [HLAlbum]
  var aehnlich: [HLKuenstler]
}

struct HLAlbumSeite: Codable, Sendable {
  var album: HLAlbum
  var songs: [HLSong]
}

struct HLSender: Codable, Sendable {
  struct Kopf: Codable, Sendable {
    var name: String
  }

  var sender: Kopf
  var songs: [HLSong]
}

struct HLReihe: Codable, Hashable, Sendable {
  var typ: String                                       // "alben" oder "songs"
  var titel: String
  var untertitel: String?
  var kuenstlerId: Int?
  var alben: [HLAlbum]?
  var songs: [HLSong]?
}

struct HLReihen: Codable, Sendable {
  var reihen: [HLReihe]
}

struct HLWunschAntwort: Codable, Sendable {
  var status: String
  var meldung: String?
  var anzahl: Int?
  var titel: String?
  var kuenstler: String?
  var album: String?
  var songId: String?                                   // bei «gefunden»: Navidrome-ID
  var ueberschrift: String?
}

struct HLFortschritt: Codable, Hashable, Sendable {
  var phase: String                                     // wartet, laedt, import, fehler
  var text: String
  var prozent: Double?
  var andere: Bool
}

struct HLWunsch: Codable, Hashable, Sendable {
  var id: Int?
  var fortschritt: HLFortschritt?
  var titel: String
  var kuenstler: String
  var status: String
  var erstellt: Double
  var songId: String?                                   // Navidrome-ID, sobald der Song da ist

  var abspielbar: Bool { songId != nil && (status == "geliefert" || status == "gefunden") }

  /// Als Bibliotheks-Song für den Player.
  var alsSong: HLSong {
    HLSong(typ: "bibliothek", status: "bibliothek", deezerId: nil, titel: titel, kuenstler: kuenstler,
           kuenstlerId: nil, album: nil, albumId: nil, bild: songId.map { "/entdecken/cover/mf-\($0)" },
           bildGross: nil, dauer: nil, vorschau: nil, navidromeId: songId, navidromeCover: nil)
  }
}

struct HLAntwort: Codable, Sendable {
  var status: String?
  var meldung: String?
  var kuenstlerGesperrt: Bool?
  var folgt: Bool?
}

struct HLAbgelehnt: Codable, Hashable, Sendable {
  var art: String                                       // "song" oder "kuenstler"
  var schluessel: String
  var anzeige: String
}

struct HLAbgelehntListe: Codable, Sendable {
  var eintraege: [HLAbgelehnt]
}

struct HLAehnlich: Codable, Sendable {
  var seed: HLSong
  var songs: [HLSong]
}

struct HLWunschListe: Codable, Sendable {
  var wuensche: [HLWunsch]
}

private struct HLAnmeldung: Codable, Sendable {
  var token: String
  var name: String
}

private struct HLFehler: Codable, Sendable {
  var meldung: String?
}

enum HLAPIFehler: LocalizedError {
  case keinKonto
  case server(String)

  var errorDescription: String? {
    switch self {
    case .keinKonto: return "Kein Navidrome-Konto angemeldet."
    case let .server(text): return text
    }
  }
}

// MARK: - Schnittstelle

@MainActor
final class HLAPI {
  static let shared = HLAPI()
  static let port = 30370

  var account: Account?
  private var token: String?
  private var anmeldung: Task<String, Error>?
  private let session: URLSession = {
    let c = URLSessionConfiguration.default
    c.timeoutIntervalForRequest = 25
    return URLSession(configuration: c)
  }()

  private var credentials: LoginCredentials? {
    guard let account else { return nil }
    return AmperKit.shared.storage.settings.accounts.getSetting(account.info).read.loginCredentials
  }

  /// Musikwunsch läuft auf demselben Rechner wie Navidrome, Port 30370.
  var basisURL: URL? {
    guard let cred = credentials else { return nil }
    let server = cred.activeBackendServerUrl.isEmpty ? cred.serverUrl : cred.activeBackendServerUrl
    guard let url = URL(string: server), let host = url.host else { return nil }
    var teile = URLComponents()
    teile.scheme = "http"
    teile.host = host
    teile.port = Self.port
    return teile.url
  }

  /// Adresse einer Subsonic-Anfrage an Navidrome mit den Zugangsdaten des Kontos (z. B. getCoverArt).
  func subsonicURL(_ endpunkt: String, _ parameter: [String: String]) -> URL? {
    guard let cred = credentials else { return nil }
    let server = cred.activeBackendServerUrl.isEmpty ? cred.serverUrl : cred.activeBackendServerUrl
    guard var teile = URLComponents(string: server.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/rest/" + endpunkt)
    else { return nil }
    let salz = (0 ..< 8).map { _ in String(format: "%02x", UInt8.random(in: 0 ... 255)) }.joined()
    let hash = Insecure.MD5.hash(data: Data((cred.password + salz).utf8)).map { String(format: "%02x", $0) }.joined()
    let basis = ["u": cred.username, "t": hash, "s": salz, "v": "1.16.1", "c": "homelabmusic"]
    teile.queryItems = basis.merging(parameter) { $1 }.sorted { $0.key < $1.key }
      .map { URLQueryItem(name: $0.key, value: $0.value) }
    return teile.url
  }

  private var schluessel: String {
    "homelabmusic.token.\(credentials?.username ?? "")@\(basisURL?.host ?? "")"
  }

  func url(_ pfad: String?) -> URL? {
    guard let pfad, !pfad.isEmpty else { return nil }
    if pfad.hasPrefix("http") { return URL(string: pfad) }
    return URL(string: pfad, relativeTo: basisURL)?.absoluteURL
  }

  /// Header für eigene Adressen (Cover, Songs aus der Bibliothek).
  func kopf(fuer url: URL) async -> [String: String] {
    guard url.host == basisURL?.host, url.port == Self.port else { return [:] }
    guard let tok = try? await gueltigesToken() else { return [:] }
    return ["Authorization": "Bearer \(tok)"]
  }

  // MARK: Anmeldung

  private func gueltigesToken() async throws -> String {
    if let token { return token }
    if let gespeichert = HLSchluesselbund.lesen(schluessel) {
      token = gespeichert
      return gespeichert
    }
    if let anmeldung { return try await anmeldung.value }   // gleichzeitige Anfragen: nur einmal anmelden
    let aufgabe = Task { try await anmelden() }
    anmeldung = aufgabe
    defer { anmeldung = nil }
    return try await aufgabe.value
  }

  private func anmelden() async throws -> String {
    guard let cred = credentials, let basis = basisURL else { throw HLAPIFehler.keinKonto }
    let salz = (0 ..< 8).map { _ in String(format: "%02x", UInt8.random(in: 0 ... 255)) }.joined()
    let hash = Insecure.MD5.hash(data: Data((cred.password + salz).utf8))
      .map { String(format: "%02x", $0) }.joined()
    var req = URLRequest(url: basis.appendingPathComponent("entdecken/anmelden"))
    req.httpMethod = "POST"
    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
    req.httpBody = try JSONEncoder().encode(["u": cred.username, "t": hash, "s": salz])
    let (daten, antwort) = try await session.data(for: req)
    guard (antwort as? HTTPURLResponse)?.statusCode == 200 else {
      throw HLAPIFehler.server(Self.meldung(daten) ?? "Anmeldung beim Musikwunsch-Dienst fehlgeschlagen.")
    }
    let a = try Self.decoder.decode(HLAnmeldung.self, from: daten)
    token = a.token
    HLSchluesselbund.schreiben(schluessel, a.token)
    return a.token
  }

  // MARK: Anfragen

  private static let decoder: JSONDecoder = {
    let d = JSONDecoder()
    d.keyDecodingStrategy = .convertFromSnakeCase
    return d
  }()

  private static func meldung(_ daten: Data) -> String? {
    (try? decoder.decode(HLFehler.self, from: daten))?.meldung
  }

  /// Konto nachträglich setzen (z. B. Hintergrundaufgabe ohne geöffnete Oberfläche).
  func kontoSicherstellen() {
    guard account == nil, let info = AmperKit.shared.storage.settings.accounts.active else { return }
    account = AmperKit.shared.storage.main.library.getAccount(info: info)
  }

  private func anfrage<T: Decodable>(
    _ pfad: String,
    abfrage: [String: String] = [:],
    methode: String = "GET",
    inhalt: [String: any Encodable & Sendable]? = nil,
    erneut: Bool = true
  ) async throws -> T {
    guard let basis = basisURL else { throw HLAPIFehler.keinKonto }
    var teile = URLComponents(url: basis.appendingPathComponent(pfad), resolvingAgainstBaseURL: false)!
    if !abfrage.isEmpty {
      teile.queryItems = abfrage.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
    }
    var req = URLRequest(url: teile.url!)
    req.httpMethod = methode
    req.setValue("Bearer \(try await gueltigesToken())", forHTTPHeaderField: "Authorization")
    if let inhalt {
      req.setValue("application/json", forHTTPHeaderField: "Content-Type")
      req.httpBody = try JSONSerialization.data(withJSONObject: inhalt)
    }
    let (daten, antwort) = try await session.data(for: req)
    let code = (antwort as? HTTPURLResponse)?.statusCode ?? 0
    if code == 401, erneut {                       // Token veraltet: neu anmelden, einmal wiederholen
      token = nil
      HLSchluesselbund.loeschen(schluessel)
      return try await anfrage(pfad, abfrage: abfrage, methode: methode, inhalt: inhalt, erneut: false)
    }
    guard code == 200 || code == 202 else {
      throw HLAPIFehler.server(Self.meldung(daten) ?? "Fehler \(code)")
    }
    return try Self.decoder.decode(T.self, from: daten)
  }

  func jetzt() async throws -> HLJetzt { try await anfrage("entdecken/jetzt") }
  func reihen() async throws -> HLReihen { try await anfrage("entdecken/reihen") }

  private struct HLErkannt: Codable, Sendable { var song: HLSong }

  /// Shazam-Treffer nachschlagen (Bibliothek oder Deezer-Vorschau), ohne Wunsch.
  func erkennen(titel: String, kuenstler: String) async throws -> HLSong {
    let r: HLErkannt = try await anfrage("entdecken/erkennen", abfrage: ["titel": titel, "kuenstler": kuenstler])
    return r.song
  }
  func suche(_ q: String) async throws -> HLSuche { try await anfrage("entdecken/suche", abfrage: ["q": q]) }
  func kuenstler(_ id: Int) async throws -> HLKuenstlerSeite { try await anfrage("entdecken/kuenstler/\(id)") }
  func album(_ id: Int) async throws -> HLAlbumSeite { try await anfrage("entdecken/album/\(id)") }
  func wuensche() async throws -> HLWunschListe { try await anfrage("entdecken/wuensche") }

  func sender(art: String, id: String) async throws -> HLSender {
    try await anfrage("entdecken/sender", abfrage: [art: id, "anzahl": "30"])
  }

  func wunsch(song deezerId: Int) async throws -> HLWunschAntwort {
    try await anfrage("entdecken/wunsch", methode: "POST", inhalt: ["deezer_id": deezerId])
  }

  /// Wunsch nach Titel und Künstler (Shazam), wie der Kurzbefehl: Bibliothek prüfen, sonst SoulSync.
  func wunsch(titel: String, kuenstler: String) async throws -> HLWunschAntwort {
    try await anfrage("wunsch", methode: "POST", inhalt: ["titel": titel, "kuenstler": kuenstler])
  }

  func ablehnen(titel: String, kuenstler: String, navidromeId: String?, rueckgaengig: Bool = false) async throws -> HLAntwort {
    var inhalt: [String: any Encodable & Sendable] = ["titel": titel, "kuenstler": kuenstler]
    if let navidromeId { inhalt["navidrome_id"] = navidromeId }
    if rueckgaengig { inhalt["rueckgaengig"] = true }
    return try await anfrage("entdecken/ablehnen", methode: "POST", inhalt: inhalt)
  }

  func abgelehnt() async throws -> HLAbgelehntListe { try await anfrage("entdecken/abgelehnt") }

  func aufheben(_ e: HLAbgelehnt) async throws -> HLAntwort {
    try await anfrage("entdecken/abgelehnt", methode: "POST", inhalt: ["art": e.art, "schluessel": e.schluessel])
  }

  func folgen(kuenstlerId: Int, name: String, folgen: Bool) async throws -> HLAntwort {
    try await anfrage("entdecken/folgen", methode: "POST", inhalt: ["kuenstler_id": kuenstlerId, "name": name, "folgen": folgen])
  }

  func andereVersion(wunschId: Int) async throws -> HLAntwort {
    try await anfrage("entdecken/wunsch/andere", methode: "POST", inhalt: ["id": wunschId])
  }

  func aehnlich(navidromeId: String) async throws -> HLAehnlich {
    try await anfrage("entdecken/aehnlich", abfrage: ["navidrome": navidromeId])
  }

  func wunsch(album albumId: Int) async throws -> HLWunschAntwort {
    try await anfrage("entdecken/wunsch", methode: "POST", inhalt: ["album_id": albumId])
  }
}

// MARK: - Schlüsselbund

enum HLSchluesselbund {
  private static func basis(_ konto: String) -> [String: Any] {
    [kSecClass as String: kSecClassGenericPassword,
     kSecAttrService as String: "ch.gerber.homelabmusic",
     kSecAttrAccount as String: konto]
  }

  static func lesen(_ konto: String) -> String? {
    var q = basis(konto)
    q[kSecReturnData as String] = true
    q[kSecMatchLimit as String] = kSecMatchLimitOne
    var ergebnis: AnyObject?
    guard SecItemCopyMatching(q as CFDictionary, &ergebnis) == errSecSuccess,
          let daten = ergebnis as? Data else { return nil }
    return String(data: daten, encoding: .utf8)
  }

  static func schreiben(_ konto: String, _ wert: String) {
    loeschen(konto)
    var q = basis(konto)
    q[kSecValueData as String] = Data(wert.utf8)
    q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
    SecItemAdd(q as CFDictionary, nil)
  }

  static func loeschen(_ konto: String) {
    SecItemDelete(basis(konto) as CFDictionary)
  }
}
