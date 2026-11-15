//
//  HLMediathekUI.swift
//  HomeLabMusic
//
//  Bedienung der Mediathek (HLMediathek):
//  - Menüeintrag «Zur Mediathek hinzufügen» / «Aus Mediathek entfernen» für Song und Album
//    (über HLMenue in jedem Amperfy-Menü: Listen, Albumseite, Player, Mini-Player)
//  - «+» am Ende jeder Song-Zeile, die nicht in der Mediathek ist (Album- und Künstlerseite, Suche,
//    Favoriten, Playlists); eigene Songs haben keinen Knopf (wie bei Apple Music).
//  Im Kinder-Modus gibt es beides nicht. Entfernen löscht nur den Eintrag, nie die Datei.
//
//  This program is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//

import AmperfyKit
import UIKit

@MainActor
enum HLMediathekUI {
  /// Mediathek bedienbar: angemeldet und nicht im Kinder-Modus.
  static var aktiv: Bool { HLAPI.shared.account != nil && !HLBibliothek.shared.istKinderModus }

  private static var appDelegate: AppDelegate { UIApplication.shared.delegate as! AppDelegate }

  // MARK: Menü

  /// Einträge für das Menü eines Songs oder Albums.
  static func menue(fuer container: PlayableContainable) -> [UIMenuElement] {
    guard aktiv else { return [] }
    if let song = (container as? AbstractPlayable)?.asSong, !song.isRadio {
      return [songAktion(song)]
    }
    if let album = container as? Album {
      return albumAktionen(album)
    }
    return []
  }

  private static func songAktion(_ song: Song) -> UIAction {
    if song.managedObject.hlInMediathek {
      return UIAction(title: "Aus Mediathek entfernen", image: UIImage(systemName: "minus.circle")) { _ in
        ausfuehren(meldung: nil) {
          try await HLMediathek.shared.entfernen(songIds: [song.id])
          song.managedObject.hlInMediathek = false
        }
      }
    }
    return UIAction(title: "Zur Mediathek hinzufügen", image: UIImage(systemName: "plus.circle")) { _ in
      ausfuehren(meldung: nil) {
        try await HLMediathek.shared.hinzufuegen(songIds: [song.id])
        song.managedObject.hlInMediathek = true
      }
    }
  }

  private static func albumAktionen(_ album: Album) -> [UIMenuElement] {
    let lokal = album.songs.compactMap(\.asSong)
    let eigene = lokal.filter { $0.managedObject.hlInMediathek }.count
    let gesamt = max(album.songCount, lokal.count)
    var aktionen = [UIMenuElement]()
    if eigene < gesamt {
      let titel = eigene == 0 ? "Zur Mediathek hinzufügen" : "Ganzes Album zur Mediathek"
      aktionen.append(UIAction(title: titel, image: UIImage(systemName: "plus.circle")) { _ in
        ausfuehren(meldung: "«\(album.name)» ist in deiner Mediathek.") {
          try await HLMediathek.shared.hinzufuegen(songIds: try await albumSongIds(album))
        }
      })
    }
    if eigene > 0 {
      aktionen.append(UIAction(title: "Aus Mediathek entfernen", image: UIImage(systemName: "minus.circle")) { _ in
        ausfuehren(meldung: "«\(album.name)» ist nicht mehr in deiner Mediathek.") {
          let ids = Set(try await albumSongIds(album)).union(lokal.map(\.id))
          try await HLMediathek.shared.entfernen(songIds: Array(ids))
        }
      })
    }
    return aktionen
  }

  /// Alle Song-IDs eines Albums vom Server (auf dem Gerät sind oft nicht alle Songs geladen).
  private static func albumSongIds(_ album: Album) async throws -> [String] {
    guard let antwort = await HLAPI.shared.subsonic("getAlbum", ["id": album.id]) else {
      throw HLMediathek.Fehler.server("Album nicht lesbar.")
    }
    let songs = (antwort["album"] as? [String: Any])?["song"] as? [[String: Any]] ?? []
    let ids = songs.compactMap { $0["id"] as? String }
    guard !ids.isEmpty else { throw HLMediathek.Fehler.server("Album ohne Songs.") }
    return ids
  }

  /// Für Songs aus Entdecken (Mini-Player-Menü): Eintrag nach Navidrome-ID.
  static func menue(navidromeId id: String) -> [UIMenuElement] {
    guard aktiv, let account = HLAPI.shared.account,
          let song = appDelegate.storage.main.library.getSong(for: account, id: id) else { return [] }
    return [songAktion(song)]
  }

  // MARK: «+» in der Song-Zeile

  /// Knopf am Zeilenende für Songs, die nicht in der Mediathek sind; nil sonst.
  static func zubehoer(fuer playable: AbstractPlayable, nachher: @escaping () -> ()) -> UIView? {
    guard aktiv, let song = playable.asSong, !playable.isRadio, !song.managedObject.hlInMediathek else { return nil }
    let knopf = UIButton(type: .system)
    knopf.setImage(UIImage(systemName: "plus.circle"), for: .normal)
    knopf.tintColor = appDelegate.storage.settings.accounts.getSetting(playable.account?.info).read
      .themePreference.asColor
    knopf.frame = CGRect(x: 0, y: 0, width: 30, height: 30)
    knopf.accessibilityLabel = "Zur Mediathek hinzufügen"
    knopf.addAction(UIAction { [weak knopf] _ in
      knopf?.isEnabled = false
      ausfuehren(meldung: nil) {
        try await HLMediathek.shared.hinzufuegen(songIds: [song.id])
        song.managedObject.hlInMediathek = true
      } danach: {
        knopf?.isEnabled = true
        nachher()
      }
    }, for: .touchUpInside)
    return knopf
  }

  // MARK: Ausführen

  private static func ausfuehren(
    meldung: String?,
    _ arbeit: @escaping @MainActor () async throws -> (),
    danach: @escaping @MainActor () -> () = {}
  ) {
    Task {
      do {
        try await arbeit()
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        if let meldung { appDelegate.eventLogger.info(topic: "Mediathek", message: meldung) }
      } catch {
        appDelegate.eventLogger.info(topic: "Mediathek", message: error.localizedDescription)
      }
      danach()
    }
  }
}
