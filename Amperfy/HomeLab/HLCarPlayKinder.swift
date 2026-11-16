//
//  HLCarPlayKinder.swift
//  HomeLabMusic
//
//  Tab «Kinder» in CarPlay: Kinderalben und Hörspiele aus der Navidrome-Bibliothek «Kinder», unabhängig vom
//  Umschalter Mediathek | Kinder der App. Oben «Zuletzt gehört», darunter die Künstler bzw. Reihen; ein
//  Künstler zeigt seine Alben, ein Album seine Songs (Amperfys Albumliste).
//
//  Eigene Listen statt Amperfys Künstler- und Albenlisten, weil diese den Bibliotheksfilter der App anwenden
//  (im Modus Mediathek blendet er alles aus «Kinder» aus).
//
//  Erlaubt das Auto nur vier Tabs, fällt «Geladen» aus der Tab-Leiste und steht als Eintrag unter «Bibliothek».
//
//  This program is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//

import AmperfyKit
import CarPlay
import CoreData
import UIKit

extension CarPlaySceneDelegate {
  static var hlGeladenImTabBar: Bool { CPTabBarTemplate.maximumTabCount >= 5 }

  func hlKinderTabErstellen() -> CPListTemplate {
    let tab = CPListTemplate(title: "Kinder", sections: [])
    tab.tabImage = UIImage(systemName: "figure.and.child.holdinghands")
    tab.emptyViewTitleVariants = ["Noch keine Kinderalben"]
    return tab
  }

  /// Abschnitte des Kinder-Tabs (bei jedem Erscheinen neu, die Bibliotheken laden im Hintergrund nach).
  func hlKinderAbschnitte() -> [CPListSection] {
    guard let kinder = HLBibliothek.shared.bibliotheken.first(where: \.istKinder),
          let konto = activeAccount else { return [] }
    let kontext = appDelegate.storage.main.context
    let maximum = CPListTemplate.maximumItemCount
    var abschnitte = [CPListSection]()

    let zuletzt = NSFetchRequest<AlbumMO>(entityName: "Album")
    zuletzt.predicate = NSPredicate(
      format: "account == %@ AND id IN %@ AND recentIndex > 0", konto.managedObject.objectID, kinder.alben
    )
    zuletzt.sortDescriptors = [NSSortDescriptor(key: "recentIndex", ascending: true)]
    zuletzt.fetchLimit = 12
    var zuletztGesehen = Set<String>()
    let zuletztAlben = ((try? kontext.fetch(zuletzt)) ?? []).map { Album(managedObject: $0) }
      .filter { zuletztGesehen.insert($0.id).inserted }.prefix(6)
    if !zuletztAlben.isEmpty {
      abschnitte.append(CPListSection(
        items: Array(zuletztAlben).map { hlKinderAlbumEintrag($0) },
        header: "Zuletzt gehört",
        sectionIndexTitle: nil
      ))
    }

    let reihen = NSFetchRequest<ArtistMO>(entityName: "Artist")
    reihen.predicate = NSPredicate(format: "account == %@ AND id IN %@", konto.managedObject.objectID, kinder.kuenstler)
    reihen.sortDescriptors = [NSSortDescriptor(
      key: "name", ascending: true, selector: #selector(NSString.localizedCaseInsensitiveCompare(_:))
    )]
    // Amperfy legt Künstler teils doppelt an (gleiche Server-ID, Fehler #809): nur einen zeigen
    var gesehen = Set<String>()
    let kuenstler = ((try? kontext.fetch(reihen)) ?? []).map { Artist(managedObject: $0) }
      .filter { gesehen.insert($0.id).inserted }
      .prefix(max(0, maximum - zuletztAlben.count))
    if !kuenstler.isEmpty {
      abschnitte.append(CPListSection(
        items: Array(kuenstler).map { hlKinderKuenstlerEintrag($0, kinderAlben: kinder.alben) },
        header: "Alle",
        sectionIndexTitle: nil
      ))
    }
    return abschnitte
  }

  private func hlBild(_ eintrag: AbstractLibraryEntity) -> UIImage {
    if let artwork = eintrag.artwork, let info = artwork.account?.info {
      appDelegate.getMeta(info).artworkDownloadManager.download(object: artwork)
    }
    return LibraryEntityImage.getImageToDisplayImmediately(
      libraryEntity: eintrag,
      themePreference: getPreference(activeAccountInfo).theme,
      artworkDisplayPreference: getPreference(activeAccountInfo).artworkDisplayPreference,
      useCache: false
    ).carPlayImage(carTraitCollection: traits)
  }

  private func hlKinderKuenstlerEintrag(_ artist: Artist, kinderAlben: [String]) -> CPListItem {
    let eintrag = CPListItem(
      text: artist.name, detailText: nil, image: hlBild(artist),
      accessoryImage: nil, accessoryType: .disclosureIndicator
    )
    eintrag.handler = { [weak self] _, completion in
      guard let self else { completion(); return }
      let anfrage = NSFetchRequest<AlbumMO>(entityName: "Album")
      anfrage.predicate = NSPredicate(format: "artist.id == %@ AND id IN %@", artist.id, kinderAlben)
      anfrage.sortDescriptors = [
        NSSortDescriptor(key: "year", ascending: true),
        NSSortDescriptor(key: "name", ascending: true, selector: #selector(NSString.localizedCaseInsensitiveCompare(_:))),
      ]
      anfrage.fetchLimit = CPListTemplate.maximumItemCount
      var gesehen = Set<String>()
      let alben = ((try? appDelegate.storage.main.context.fetch(anfrage)) ?? []).map { Album(managedObject: $0) }
        .filter { gesehen.insert($0.id).inserted }
      let vorlage = CPListTemplate(
        title: artist.name,
        sections: [CPListSection(items: alben.map { hlKinderAlbumEintrag($0) })]
      )
      interfaceController?.pushTemplate(vorlage, animated: true, completion: nil)
      completion()
    }
    return eintrag
  }

  /// Album-Eintrag: lädt die Songs vom Server (Amperfy hat oft nur einen Teil) und zeigt Amperfys Songliste.
  private func hlKinderAlbumEintrag(_ album: Album) -> CPListItem {
    let eintrag = CPListItem(
      text: album.name, detailText: album.subtitle, image: hlBild(album),
      accessoryImage: nil, accessoryType: .disclosureIndicator
    )
    eintrag.handler = { [weak self] _, completion in
      guard let self else { completion(); return }
      Task { @MainActor in
        if !self.isOfflineMode, let info = self.activeAccountInfo {
          let meta = self.appDelegate.getMeta(info)
          try? await album.fetch(
            storage: self.appDelegate.storage,
            librarySyncer: meta.librarySyncer,
            playableDownloadManager: meta.playableDownloadManager
          )
        }
        let vorlage = self.createAlbumSongListTemplate(for: album, onlyCached: false)
        let _ = try? await self.interfaceController?.pushTemplate(vorlage, animated: true)
        completion()
      }
    }
    return eintrag
  }

  /// Eintrag «Geladene Musik» unter «Bibliothek», wenn «Geladen» keinen eigenen Tab bekommt.
  func hlGeladenAbschnitt() -> CPListSection? {
    guard !Self.hlGeladenImTabBar else { return nil }
    let eintrag = CPListItem(
      text: String(localized: "Cached Library"), detailText: nil, image: UIImage.cache,
      accessoryImage: nil, accessoryType: .disclosureIndicator
    )
    eintrag.handler = { [weak self] _, completion in
      guard let self else { completion(); return }
      cachedTab.updateSections(createCachedSections())
      interfaceController?.pushTemplate(cachedTab, animated: true, completion: nil)
      completion()
    }
    return CPListSection(items: [eintrag])
  }
}
