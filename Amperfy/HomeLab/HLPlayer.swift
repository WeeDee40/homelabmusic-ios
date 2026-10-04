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
  /// Letzte Songs aus dem Radio (neuester zuerst) und ob gerade ein Radiosender läuft.
  @Published private(set) var radioVerlauf: [HLRadioEintrag] = []
  @Published private(set) var radioLaeuft = false
  @Published private(set) var radioTreffer: [String: HLSong] = [:]
  private var radioSuche = Set<String>()

  private var zuordnung: [String: HLSong] = [:]       // Playable-ID -> Song
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

  func spielen(_ songs: [HLSong], ab start: Int) {
    guard let account = HLAPI.shared.account else { return }
    let alteRadios = gemerkteRadios()
    var playables = [AbstractPlayable]()
    var neueZuordnung = [String: HLSong]()
    var startIndex = 0
    var neueRadios = [String]()
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
        neueRadios.append(radio.id)
      }
    }
    guard !playables.isEmpty else {
      zeigeHinweis("Nichts abspielbar.")
      return
    }
    bibliothek.saveContext()
    zuordnung = neueZuordnung
    amperfy.play(context: PlayContext(name: Self.kontext, index: min(startIndex, playables.count - 1),
                                      playables: playables))
    radiosLoeschen(alteRadios)
    merken(neueRadios)
    abgleichen()
  }

  func umschalten() { amperfy.togglePlayPause() }
  func weiter() { amperfy.playNext() }

  /// Beim App-Start: Vorschau-Einträge entfernen, wenn der Player nicht mehr aus «Entdecken» spielt.
  func aufraeumenBeimStart() {
    guard amperfy.contextName != Self.kontext else { return }
    radiosLoeschen(gemerkteRadios())
    merken([])
  }

  private func abgleichen() {
    let laufend = amperfy.currentlyPlaying
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
