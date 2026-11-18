//
//  HLMediathekUI.swift
//  HomeLabMusic
//
//  Bedienung der Mediathek (HLMediathek):
//  - Menüeintrag «Zur Mediathek hinzufügen» / «Aus Mediathek entfernen» für Song und Album
//    (über HLMenue in jedem Amperfy-Menü: Listen, Albumseite, Player, Mini-Player)
//  - «+» am Ende jeder Song-Zeile, die nicht in der Mediathek ist (Album- und Künstlerseite, Suche,
//    Favoriten, Playlists); eigene Songs haben keinen Knopf (wie bei Apple Music).
//  - «Zu «Kinder» verschieben» / «In die Musik verschieben» für Alben (Ordner auf dem NAS, Medienwunsch)
//  Im Kinder-Modus gibt es Hinzufügen und Entfernen nicht. Entfernen löscht nur den Eintrag, nie die Datei.
//
//  This program is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//

import AmperfyKit
import CoreData
import UIKit

@MainActor
enum HLMediathekUI {
  /// Mediathek bedienbar: angemeldet und nicht im Kinder-Modus.
  static var aktiv: Bool { HLAPI.shared.account != nil && !HLBibliothek.shared.istKinderModus }

  /// Drei Stufen (Mediathek, Server, neu) gelten nur, wenn die Mediathek bedienbar ist und es sie schon gibt;
  /// sonst heisst «auf dem Server» wie früher «bei dir».
  static var stufenAktiv: Bool { aktiv && HLListenFilter.mediathekAktiv }

  private static var kontext: NSManagedObjectContext {
    (UIApplication.shared.delegate as! AppDelegate).storage.main.context
  }

  /// Ist der Song (Navidrome-ID) in der Mediathek? Laut Gerät (letzter Abgleich und eigene Änderungen).
  static func inMediathek(navidromeId id: String) -> Bool {
    guard let account = HLAPI.shared.account else { return false }
    let r = NSFetchRequest<SongMO>(entityName: "Song")
    r.predicate = NSPredicate(format: "id == %@ AND account == %@ AND hlInMediathek == YES", id,
                              account.managedObject.objectID)
    r.fetchLimit = 1
    return ((try? kontext.count(for: r)) ?? 0) > 0
  }

  /// Anzahl Songs eines Künstlers (nach Name) in der Mediathek.
  static func mediathekAnzahl(kuenstler name: String) -> Int {
    guard let account = HLAPI.shared.account else { return 0 }
    let r = NSFetchRequest<SongMO>(entityName: "Song")
    r.predicate = NSPredicate(format: "artist.name ==[cd] %@ AND account == %@ AND hlInMediathek == YES", name,
                              account.managedObject.objectID)
    return (try? kontext.count(for: r)) ?? 0
  }

  /// Text für Künstler: «3 in deiner Mediathek», sonst «12 auf dem Server» (ohne Mediathek: «12 bei dir»).
  static func kuenstlerText(name: String, aufServer: Int) -> String? {
    guard stufenAktiv else { return aufServer > 0 ? "\(aufServer) bei dir" : nil }
    let eigene = mediathekAnzahl(kuenstler: name)
    if eigene > 0 { return "\(eigene) in deiner Mediathek" }
    return aufServer > 0 ? "\(aufServer) auf dem Server" : nil
  }

  /// Herz gesetzt: Song in die Mediathek (Entscheid 18.11.2026). Das Herz entfernen nimmt ihn nicht heraus.
  static func lieblingGesetzt(_ id: String) {
    guard aktiv, !inMediathek(navidromeId: id) else { return }
    Task {
      do {
        try await HLMediathek.shared.hinzufuegen(songIds: [id])
        HLPlayer.shared.mediathekNeu.insert(id)
      } catch {
        HLPlayer.shared.zeigeHinweis(error.localizedDescription)
      }
    }
  }

  /// Beschriftung für Wünschen (Vorschau, Shazam, Entdecken): wohin der Song nach der Lieferung kommt.
  static var wunschText: String {
    HLBibliothek.shared.istKinderModus ? "Zu «Kinder» hinzufügen" : "Zur Mediathek hinzufügen"
  }

  private static var appDelegate: AppDelegate { UIApplication.shared.delegate as! AppDelegate }

  // MARK: Menü

  /// Einträge für das Menü eines Songs oder Albums.
  static func menue(fuer container: PlayableContainable) -> [UIMenuElement] {
    if let album = container as? Album {
      let mediathek = aktiv && !istKinder(album.id) ? albumAktionen(album) : []
      return mediathek + [verschiebenAktion(album)].compactMap { $0 }
    }
    guard aktiv else { return [] }
    if let song = (container as? AbstractPlayable)?.asSong, !song.isRadio, !istKinder(song.album?.id) {
      return [songAktion(song)]
    }
    return []
  }

  /// Liegt das Album in «Kinder»? (Auch in der Suche und unter «Zuletzt gehört» sichtbar, aber nie in der Mediathek.)
  private static func istKinder(_ albumId: String?) -> Bool {
    albumId.map { HLBibliothek.shared.kinderAlben.contains($0) } ?? false
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

  // MARK: Verschieben zwischen Musik und «Kinder»

  /// «Zu «Kinder» verschieben» bzw. «In die Musik verschieben», je nachdem, wo das Album liegt.
  /// Verschiebt den Albumordner auf dem NAS (Medienwunsch) und gilt für die ganze Familie, darum mit Rückfrage.
  private static func verschiebenAktion(_ album: Album) -> UIAction? {
    guard HLAPI.shared.account != nil,
          let bib = HLBibliothek.shared.bibliotheken.first(where: { $0.alben.contains(album.id) }),
          HLBibliothek.shared.bibliotheken.contains(where: { $0.istKinder != bib.istKinder }) else { return nil }
    let nachKinder = !bib.istKinder
    let titel = nachKinder ? "Zu «Kinder» verschieben" : "In die Musik verschieben"
    let bild = nachKinder ? "figure.and.child.holdinghands" : "music.note.house"
    return UIAction(title: titel, image: UIImage(systemName: bild)) { _ in
      let text = nachKinder
        ? "Das Album verschwindet für alle aus der Musik und aus allen Mediatheken und erscheint unter «Kinder»."
        : "Das Album erscheint für alle in der Musik und kommt in deine Mediathek."
      let alert = UIAlertController(title: "«\(album.name)» verschieben?", message: text, preferredStyle: .alert)
      alert.addAction(UIAlertAction(title: "Abbrechen", style: .cancel))
      alert.addAction(UIAlertAction(title: "Verschieben", style: .default) { _ in
        Task { await verschieben(album, nachKinder: nachKinder) }
      })
      zeigen(alert)
    }
  }

  private static func verschieben(_ album: Album, nachKinder: Bool) async {
    let logger = appDelegate.eventLogger
    do {
      let antwort = try await HLAPI.shared.verschieben(album: album.id, nachKinder: nachKinder)
      UIImpactFeedbackGenerator(style: .light).impactOccurred()
      logger.info(topic: "Verschoben", message: antwort.meldung ?? "«\(album.name)» ist verschoben.")
    } catch {
      logger.info(topic: "Nicht verschoben", message: error.localizedDescription)
      return
    }
    // Navidrome liest den Ordner in Sekunden neu ein (neue Album-ID); danach Bibliotheken und Mediathek neu.
    try? await Task.sleep(for: .seconds(10))
    await HLBibliothek.shared.aktualisieren()
    try? await Task.sleep(for: .seconds(50))           // Medienwunsch trägt das Album nach 45 s in die Mediathek ein
    try? await HLMediathek.shared.abgleichenUndWarten()
  }

  private static func zeigen(_ vc: UIViewController) {
    var oben = AppDelegate.mainSceneDelegate?.window?.rootViewController
    while let weiter = oben?.presentedViewController, !weiter.isBeingDismissed { oben = weiter }
    oben?.present(vc, animated: true)
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
          let song = appDelegate.storage.main.library.getSong(for: account, id: id),
          !istKinder(song.album?.id) else { return [] }
    return [songAktion(song)]
  }

  // MARK: «+» in der Song-Zeile

  /// Knopf am Zeilenende für Songs, die nicht in der Mediathek sind; nil sonst.
  static func zubehoer(fuer playable: AbstractPlayable, nachher: @escaping () -> ()) -> UIView? {
    guard aktiv, let song = playable.asSong, !playable.isRadio, !song.managedObject.hlInMediathek,
          !istKinder(song.album?.id) else { return nil }
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
