//
//  HLPlayer.swift
//  HomeLabMusic
//
//  Wiedergabe im Entdecken-Tab über den Amperfy-Player (Sperrbildschirm, CarPlay, eine Warteschlange):
//  Songs aus der Bibliothek kommen als normale Bibliotheks-Songs in die Warteschlange, 30-Sekunden-
//  Vorschauen als versteckte Radio-Einträge (eine Adresse, die abgespielt wird; Radio-Liste und
//  Server-Abgleich ignorieren sie, weil sie als «gelöscht» markiert sind). Beim nächsten Start
//  aus dem Entdecken-Tab und beim App-Start werden die alten Vorschau-Einträge weggeräumt.
//
//  This program is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//

import AmperfyKit
import Combine
import UIKit

/// Song, den ein Internetradio gerade meldet (Titelinfos des Senders).
struct HLRadioEintrag: Hashable, Sendable {
  var sender: String
  var titel: String
  var kuenstler: String
  var schluessel: String { "\(kuenstler.lowercased())|\(titel.lowercased())" }
}

@MainActor
final class HLPlayer: ObservableObject {
  static let shared = HLPlayer()
  static let kontext = "Entdecken"
  private static let radioPraefix = "hl-vorschau-"
  private static let merkKey = "homelabmusic.vorschauRadios"

  /// Song aus dem Entdecken-Tab, der gerade im Amperfy-Player läuft (nil bei anderer Musik).
  @Published private(set) var aktuell: HLSong?
  @Published private(set) var spielt = false
  @Published private(set) var fortschritt = 0.0
  /// Status, der sich seit dem Laden geändert hat (z. B. nach «Wünschen»), je Song-Schlüssel.
  @Published private(set) var statusNeu: [String: String] = [:]
  @Published var hinweis: String?
  /// Mit «Nicht mein Ding» abgelehnte Songs (ausgeblendet bis zum Neuladen).
  @Published private(set) var ausgeblendet = Set<String>()
  /// Letzte Songs aus dem Radio (neuester zuerst) und ob gerade ein Radiosender läuft.
  @Published private(set) var radioVerlauf: [HLRadioEintrag] = []
  @Published private(set) var radioLaeuft = false
  @Published private(set) var radioTreffer: [String: HLSong] = [:]
  private var radioSuche = Set<String>()

  private(set) var zuordnung: [String: HLSong] = [:]       // Playable-ID -> Song
  private var takt: Timer?
  private var hinweisAufgabe: Task<(), Never>?

  private var amperfy: PlayerFacade { (UIApplication.shared.delegate as! AppDelegate).player }
  private var bibliothek: LibraryStorage { AmperKit.shared.storage.main.library }

  private init() {
    takt = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
      MainActor.assumeIsolated { HLPlayer.shared.abgleichen() }
    }
  }

  func status(_ song: HLSong) -> String { statusNeu[song.schluessel] ?? song.status }

  // MARK: Wiedergabe

  func spielen(_ songs: [HLSong], ab start: Int, kontext: String = HLPlayer.kontext) {
    Task {
      let alteRadios = gemerkteRadios()
      guard let (playables, startIndex) = vorbereiten(songs, ab: start, neu: true) else {
        zeigeHinweis("Nichts abspielbar.")
        return
      }
      amperfy.play(context: PlayContext(name: kontext, index: min(startIndex, playables.count - 1), playables: playables))
      radiosLoeschen(alteRadios.filter { !gemerkteRadios().contains($0) })
      abgleichen()
    }
  }

  /// Songs hinten an die laufende Warteschlange hängen (Mix lädt nach).
  func anhaengen(_ songs: [HLSong]) {
    Task {
      guard let (playables, _) = vorbereiten(songs, ab: 0, neu: false) else { return }
      amperfy.appendContextQueue(playables: playables)
    }
  }

  /// Playables für Amperfy: Bibliotheks-Songs direkt, Vorschauen als versteckte Radio-Einträge (30 s, ohne
  /// Spulen; bewusst ohne Eingriff in Amperfys Wiedergabe-Kern).
  private func vorbereiten(_ songs: [HLSong], ab start: Int, neu: Bool) -> ([AbstractPlayable], Int)? {
    guard let account = HLAPI.shared.account else { return nil }
    var playables = [AbstractPlayable](), startIndex = 0, radios = [String]()
    var neueZuordnung = neu ? [String: HLSong]() : zuordnung
    for (i, s) in songs.enumerated() {
      if i == start { startIndex = playables.count }
      if !s.istVorschau, let id = s.navidromeId, let song = bibliothek.getSong(for: account, id: id) {
        playables.append(song)
        neueZuordnung[song.id] = s
      } else if s.istVorschau, let url = HLAPI.shared.url(s.vorschau) {
        let radio = bibliothek.createRadio(account: account)
        radio.id = Self.radioPraefix + UUID().uuidString
        radio.title = "\(s.titel ?? "") · \(s.kuenstler ?? "")"
        radio.url = url.absoluteString
        radio.remoteStatus = .deleted                 // nicht in der Radio-Liste, vom Abgleich unberührt
        playables.append(radio)
        neueZuordnung[radio.id] = s
        radios.append(radio.id)
      }
    }
    guard !playables.isEmpty else { return nil }
    bibliothek.saveContext()
    zuordnung = neueZuordnung
    merken((neu ? [] : gemerkteRadios()) + radios)
    return (playables, startIndex)
  }

  /// Amperfy-Songs direkt abspielen (Ersatz-Mix über Navidromes Instant Mix).
  func spielenAmperfy(_ playables: [AbstractPlayable], kontext: String) {
    zuordnung = [:]
    amperfy.play(context: PlayContext(name: kontext, index: 0, playables: playables))
  }

  // MARK: Vorschauen im Amperfy-Player (Titel, Cover, Hinzufügen-Knopf)

  /// Unser Song hinter einem Vorschau-Radio-Eintrag (sonst nil).
  func vorschau(_ p: AbstractPlayable?) -> HLSong? {
    guard let p, p.isRadio, p.id.hasPrefix(Self.radioPraefix) else { return nil }
    return zuordnung[p.id]
  }

  func vorschauKnopf(_ p: AbstractPlayable?) -> (bild: String, farbe: UIColor)? {
    guard let s = vorschau(p) else { return nil }
    switch status(s) {
    case "bibliothek": return ("checkmark.circle.fill", .systemGreen)
    case "angefragt": return ("hourglass.circle.fill", .systemOrange)
    default: return ("plus.circle.fill", .tintColor)
    }
  }

  /// Herz-Knopf bei einer Vorschau: zur Bibliothek hinzufügen. true, wenn es eine Vorschau war.
  func vorschauWuenschen(_ p: AbstractPlayable?) -> Bool {
    guard let s = vorschau(p) else { return false }
    wuenschen(s)
    return true
  }

  static func hakenEinrichten() {
    LibraryEntityImage.vorschauInfo = { p in
      guard let s = HLPlayer.shared.vorschau(p) else { return nil }
      return (s.titel ?? "", "Vorschau · \(s.kuenstler ?? "")", s.album)
    }
    LibraryEntityImage.vorschauBild = { id in
      if id.hasPrefix(radioPraefix) {
        guard let s = HLPlayer.shared.zuordnung[id], let url = HLAPI.shared.url(s.bildGross ?? s.bild) else { return nil }
        return await HLBildSpeicher.shared.bild(url)
      }
      return await HLPlayer.shared.radioBild(id)
    }
    LibraryEntityImage.vorschauBildSofort = { p in
      if let s = HLPlayer.shared.vorschau(p) {
        guard let url = HLAPI.shared.url(s.bildGross ?? s.bild) else { return nil }
        return HLBildSpeicher.shared.zwischengespeichert(url)
      }
      return HLPlayer.shared.radioBildSofort(p.id)
    }
  }

  // MARK: Bilder für echte Radiosender

  private var senderBilder: [String: String]?             // Radio-ID -> Navidrome-coverArt (falls hochgeladen)

  /// Cover des Songs, der gerade im Radio läuft (Deezer); sonst das Senderbild aus Navidrome.
  func radioBild(_ radioId: String) async -> UIImage? {
    if let eintrag = radioVerlauf.first, amperfy.currentlyPlaying?.id == radioId {
      for _ in 0 ..< 12 where radioTreffer[eintrag.schluessel] == nil { try? await Task.sleep(for: .milliseconds(500)) }
      if let s = radioTreffer[eintrag.schluessel], let url = HLAPI.shared.url(s.bildGross ?? s.bild),
         let bild = await HLBildSpeicher.shared.bild(url) { return bild }
    }
    if senderBilder == nil { senderBilder = await HLAPI.shared.senderBilder() }
    guard let cover = senderBilder?[radioId], !cover.isEmpty,
          let url = HLAPI.shared.subsonicURL("getCoverArt", ["id": cover, "size": "600"]) else { return nil }
    return await HLBildSpeicher.shared.bild(url)
  }

  func radioBildSofort(_ radioId: String) -> UIImage? {
    guard let eintrag = radioVerlauf.first, amperfy.currentlyPlaying?.id == radioId,
          let s = radioTreffer[eintrag.schluessel], let url = HLAPI.shared.url(s.bildGross ?? s.bild) else { return nil }
    return HLBildSpeicher.shared.zwischengespeichert(url)
  }

  var amperfyKontext: String { amperfy.contextName }
  var naechsteAnzahl: Int { amperfy.nextQueueCount }

  func umschalten() { amperfy.togglePlayPause() }
  func weiter() { amperfy.playNext() }

  /// Beim App-Start: Vorschau-Einträge entfernen, wenn der Player nicht mehr aus «Entdecken» spielt.
  func aufraeumenBeimStart() {
    HLVorschauDateien.aufraeumen()                   // Dateien aus Build 16/17 wegräumen
    guard amperfy.contextName != Self.kontext, !amperfy.contextName.hasPrefix(HLMix.praefix) else { return }
    radiosLoeschen(gemerkteRadios())
    merken([])
  }

  private var letzteId: String?
  private var letzteZeit = 0.0
  private var letzteDauer = 0.0

  /// Songwechsel auswerten: ganz gehört, früh übersprungen oder mit Stern -> Signal an den Mix.
  private func wechselAuswerten(neueId: String?) {
    defer { letzteId = neueId; letzteZeit = 0; letzteDauer = 0 }
    guard let alt = letzteId, alt != neueId, let song = zuordnung[alt] else { return }
    if song.istVorschau {
      if letzteZeit < 8 { HLMix.shared.signal(song, art: "skip") }
      return
    }
    let favorit = HLAPI.shared.account.flatMap { bibliothek.getSong(for: $0, id: alt) }?.isFavorite ?? false
    if favorit {
      HLMix.shared.signal(song, art: "stark")
    } else if letzteDauer > 0, letzteZeit >= letzteDauer * 0.8 {
      HLMix.shared.signal(song, art: "gehoert")
    } else if letzteZeit < 30 {
      HLMix.shared.signal(song, art: "skip")
    }
  }

  private func abgleichen() {
    let laufend = amperfy.currentlyPlaying
    if laufend?.id != letzteId { wechselAuswerten(neueId: laufend?.id) }
    if laufend != nil {
      letzteZeit = max(letzteZeit, amperfy.elapsedTime)
      if amperfy.duration > 0 { letzteDauer = amperfy.duration }
    }
    HLMix.shared.pruefen()
    let song = laufend.flatMap { zuordnung[$0.id] }
    if aktuell?.schluessel != song?.schluessel || (aktuell == nil) != (song == nil) { aktuell = song }
    if spielt != amperfy.isPlaying { spielt = amperfy.isPlaying }
    let dauer = song?.istVorschau == true ? 30 : amperfy.duration
    let neu = dauer > 0 ? min(amperfy.elapsedTime / dauer, 1) : 0
    if abs(neu - fortschritt) > 0.005 { fortschritt = neu }
    radioAbgleichen(laufend)
  }

  /// Echter Radiosender (nicht unsere Vorschau-Einträge): gemeldeten Song in den Verlauf übernehmen.
  private func radioAbgleichen(_ laufend: AbstractPlayable?) {
    guard let laufend, laufend.isRadio, !laufend.id.hasPrefix(Self.radioPraefix),
          let info = amperfy.currentRadioNowPlaying, !info.isEmpty else {
      if radioLaeuft { radioLaeuft = false }
      return
    }
    if !radioLaeuft { radioLaeuft = true }
    var titel = info.title.trimmingCharacters(in: .whitespaces)
    var kuenstler = info.artist.trimmingCharacters(in: .whitespaces)
    // Viele Sender melden «Künstler - Titel», teils mit anderen Strichen (Energy Bern: «˗»)
    if kuenstler.isEmpty, let r = titel.range(of: #"\s+[-–—˗‐‑−]\s+"#, options: .regularExpression) {
      kuenstler = String(titel[..<r.lowerBound]); titel = String(titel[r.upperBound...])
    }
    guard !titel.isEmpty, !kuenstler.isEmpty else { return }
    let e = HLRadioEintrag(sender: laufend.title, titel: titel, kuenstler: kuenstler)
    guard radioVerlauf.first?.schluessel != e.schluessel else { return }
    radioVerlauf.removeAll { $0.schluessel == e.schluessel }
    radioVerlauf.insert(e, at: 0)
    if radioVerlauf.count > 5 { radioVerlauf.removeLast() }
    nachschlagen(e)
  }

  /// Radio-Song in Bibliothek bzw. bei Deezer nachschlagen (einmal je Song).
  func nachschlagen(_ e: HLRadioEintrag) {
    guard radioTreffer[e.schluessel] == nil, !radioSuche.contains(e.schluessel) else { return }
    radioSuche.insert(e.schluessel)
    Task {
      if let song = try? await HLAPI.shared.erkennen(titel: e.titel, kuenstler: e.kuenstler) {
        radioTreffer[e.schluessel] = song
      }
      radioSuche.remove(e.schluessel)
    }
  }

  private func gemerkteRadios() -> [String] {
    UserDefaults.standard.stringArray(forKey: Self.merkKey) ?? []
  }

  private func merken(_ ids: [String]) {
    UserDefaults.standard.set(ids, forKey: Self.merkKey)
  }

  private func radiosLoeschen(_ ids: [String]) {
    guard let account = HLAPI.shared.account, !ids.isEmpty else { return }
    for id in ids where id.hasPrefix(Self.radioPraefix) {
      if let radio = bibliothek.getRadio(for: account, id: id) { bibliothek.deleteRadio(radio) }
    }
    bibliothek.saveContext()
  }

  // MARK: Wünschen

  func wuenschen(_ song: HLSong) {
    guard let id = song.deezerId, status(song) == "neu" else {
      zeigeHinweis(status(song) == "bibliothek" ? "In deiner Bibliothek." : "Schon gewünscht, kommt bald.")
      return
    }
    statusNeu[song.schluessel] = "angefragt"
    HLMix.shared.signal(song, art: "stark")
    Task {
      do {
        let r = try await HLAPI.shared.wunsch(song: id)
        switch r.status {
        case "gefunden":
          statusNeu[song.schluessel] = "bibliothek"
          zeigeHinweis("Hast du schon.")
        case "angefragt":
          zeigeHinweis("Gewünscht: kommt in ein paar Minuten in die Bibliothek.")
        default:
          statusNeu[song.schluessel] = nil
          zeigeHinweis(r.meldung ?? "Nicht gefunden.")
        }
      } catch {
        statusNeu[song.schluessel] = nil
        zeigeHinweis(error.localizedDescription)
      }
    }
  }

  /// Wunsch nach Titel/Künstler (Shazam-Treffer ohne Deezer-Eintrag).
  func wuenschenOhneDeezer(_ song: HLSong) {
    guard status(song) == "neu", let titel = song.titel, let kuenstler = song.kuenstler else { return }
    statusNeu[song.schluessel] = "angefragt"
    Task {
      do {
        let r = try await HLAPI.shared.wunsch(titel: titel, kuenstler: kuenstler)
        if r.status == "gefunden" { statusNeu[song.schluessel] = "bibliothek" }
        if r.status != "angefragt" && r.status != "gefunden" { statusNeu[song.schluessel] = nil }
        zeigeHinweis(r.meldung ?? "")
      } catch {
        statusNeu[song.schluessel] = nil
        zeigeHinweis(error.localizedDescription)
      }
    }
  }

  /// «Nicht mein Ding»: kommt nicht mehr in Vorschlägen und Mixen; läuft er gerade, geht es weiter.
  func ablehnen(_ song: HLSong) {
    guard let titel = song.titel, let kuenstler = song.kuenstler else { return }
    ausgeblendet.insert(song.schluessel)
    HLMix.shared.signal(song, art: "weg")
    if aktuell?.schluessel == song.schluessel { weiter() }
    Task {
      do {
        let r = try await HLAPI.shared.ablehnen(titel: titel, kuenstler: kuenstler, navidromeId: song.navidromeId)
        zeigeHinweis(r.meldung ?? "Abgelehnt.")
      } catch {
        ausgeblendet.remove(song.schluessel)
        zeigeHinweis(error.localizedDescription)
      }
    }
  }

  func alsAngefragtMarkieren(_ songs: [HLSong]) {
    for s in songs where status(s) == "neu" { statusNeu[s.schluessel] = "angefragt" }
  }

  func zeigeHinweis(_ text: String) {
    hinweis = text
    hinweisAufgabe?.cancel()
    hinweisAufgabe = Task {
      try? await Task.sleep(for: .seconds(3))
      if !Task.isCancelled { hinweis = nil }
    }
  }
}

// MARK: - Vorschau-Dateien

/// Früher lokal gespeicherte Vorschauen (Build 16/17) wegräumen; heute werden sie gestreamt.
@MainActor
enum HLVorschauDateien {
  private static var ordner: URL {
    FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("hl-vorschau")
  }

  static func aufraeumen() {
    try? FileManager.default.removeItem(at: ordner)
  }
}
