//
//  HLPlayer.swift
//  HomeLabMusic
//
//  Eigener kleiner Player für den Entdecken-Tab: 30-Sekunden-Vorschauen (Deezer) und Songs aus
//  der Bibliothek (über den Musikwunsch-Dienst von Navidrome). Pausiert den Amperfy-Player,
//  solange er spielt, und hört auf, sobald Amperfy wieder spielt.
//
//  This program is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//

import AmperfyKit
import AVFoundation
import Combine
import MediaPlayer
import UIKit

@MainActor
final class HLPlayer: ObservableObject {
  static let shared = HLPlayer()

  @Published private(set) var liste: [HLSong] = []
  @Published private(set) var index = -1
  @Published private(set) var spielt = false
  @Published private(set) var fortschritt = 0.0
  /// Status, der sich seit dem Laden geändert hat (z. B. nach «Wünschen»), je Song-Schlüssel.
  @Published private(set) var statusNeu: [String: String] = [:]
  @Published var hinweis: String?

  private let player = AVPlayer()
  private var zeitBeobachter: Any?
  private var endeBeobachter: NSObjectProtocol?
  private var wachhund: Timer?
  private var hinweisAufgabe: Task<(), Never>?

  var aktuell: HLSong? { liste.indices.contains(index) ? liste[index] : nil }

  private var amperfy: PlayerFacade { (UIApplication.shared.delegate as! AppDelegate).player }

  private init() {
    zeitBeobachter = player.addPeriodicTimeObserver(
      forInterval: CMTime(seconds: 0.5, preferredTimescale: 600),
      queue: .main
    ) { [weak self] zeit in
      MainActor.assumeIsolated {
        guard let self, let dauer = self.player.currentItem?.duration.seconds, dauer.isFinite, dauer > 0 else { return }
        self.fortschritt = zeit.seconds / dauer
      }
    }
  }

  func status(_ song: HLSong) -> String { statusNeu[song.schluessel] ?? song.status }

  // MARK: Wiedergabe

  func spielen(_ songs: [HLSong], ab start: Int) {
    liste = songs
    index = start - 1
    weiter()
  }

  func weiter() {
    var i = index + 1
    while liste.indices.contains(i) {
      if let quelle = quelle(liste[i]) {
        index = i
        laden(quelle, song: liste[i])
        return
      }
      i += 1
    }
    stopp()
    zeigeHinweis("Ende der Liste.")
  }

  func zurueck() {
    if player.currentTime().seconds > 3 || index <= 0 {
      player.seek(to: .zero)
      return
    }
    var i = index - 1
    while i >= 0, quelle(liste[i]) == nil { i -= 1 }
    if i >= 0 { index = i - 1; weiter() }
  }

  func umschalten() {
    if spielt {
      player.pause()
      spielt = false
    } else if aktuell != nil {
      amperfy.pause()
      player.play()
      spielt = true
    }
  }

  func stopp() {
    player.pause()
    player.replaceCurrentItem(with: nil)
    spielt = false
    liste = []
    index = -1
    wachhund?.invalidate()
  }

  private func quelle(_ song: HLSong) -> URL? {
    if !song.istVorschau, let id = song.navidromeId {
      return HLAPI.shared.url("/entdecken/stream/\(id)")
    }
    return HLAPI.shared.url(song.vorschau)
  }

  private func laden(_ url: URL, song: HLSong) {
    amperfy.pause()
    fortschritt = 0
    Task {
      let kopf = await HLAPI.shared.kopf(fuer: url)
      let asset = AVURLAsset(url: url, options: kopf.isEmpty ? nil : ["AVURLAssetHTTPHeaderFieldsKey": kopf])
      let item = AVPlayerItem(asset: asset)
      if let alt = endeBeobachter { NotificationCenter.default.removeObserver(alt) }
      endeBeobachter = NotificationCenter.default.addObserver(
        forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main
      ) { _ in
        MainActor.assumeIsolated { HLPlayer.shared.weiter() }
      }
      player.replaceCurrentItem(with: item)
      player.play()
      spielt = true
      jetztLaeuft(song)
      wachen()
    }
  }

  /// Startet jemand den Amperfy-Player, hört die Vorschau auf.
  private func wachen() {
    wachhund?.invalidate()
    wachhund = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
      MainActor.assumeIsolated {
        guard let self else { return }
        if self.spielt, self.amperfy.isPlaying {
          self.player.pause()
          self.spielt = false
        }
      }
    }
  }

  private func jetztLaeuft(_ song: HLSong) {
    MPNowPlayingInfoCenter.default().nowPlayingInfo = [
      MPMediaItemPropertyTitle: song.titel ?? "",
      MPMediaItemPropertyArtist: (song.istVorschau ? "Vorschau · " : "") + (song.kuenstler ?? ""),
      MPMediaItemPropertyAlbumTitle: song.album ?? "",
    ]
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
