//
//  HLCarPlayKachel.swift
//  HomeLabMusic
//
//  Bilder für die Kacheln in CarPlay (Bibliothek, Geladen, Zufällig abspielen, Weiterhören).
//  Amperfy zeigt dort nur ein Symbol auf grüner Fläche. Hier: Cover aus der eigenen Musik (Mediathek bzw.
//  Kinder, im Tab «Geladen» nur Geladenes), 2×2-Mosaik oder ein einzelnes Cover, mit einer kleinen Plakette
//  unten rechts, die zeigt, wofür die Kachel steht.
//
//  Die Bilder entstehen auf dem Gerät aus Covern, die schon geladen sind (kein Netz nötig) und werden eine
//  Stunde lang wiederverwendet. Die Auswahl «zufällig» wechselt einmal am Tag, damit die Kacheln nicht bei
//  jedem Antippen springen. Gibt es keine Cover (z. B. Ordner, Playlists, Radiosender), bleibt Amperfys Symbol.
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

@MainActor
enum HLCarPlayKachel {
  enum Art: Hashable {
    case bibliothek(LibraryDisplayType)
    case zufallAlben
    case zufallSongs
    case weiterhoeren
    case weiterhoerenPodcast
  }

  private static var ablage = [String: (bild: UIImage, zeit: Date)]()
  private static let gueltig: TimeInterval = 3600

  private static var appDelegate: AppDelegate { UIApplication.shared.delegate as! AppDelegate }

  /// Setzt das Bild der Kachel, sobald es gezeichnet ist (das Symbol bleibt bis dahin stehen).
  static func setzen(
    _ element: CPListImageRowItemRowElement,
    art: Art,
    nurGeladen: Bool,
    traits: UITraitCollection
  ) {
    let schluessel = "\(art)|\(nurGeladen)|\(HLListenFilter.mediathekAktiv)|\(HLBibliothek.shared.istKinderModus)"
    if let fertig = ablage[schluessel], Date().timeIntervalSince(fertig.zeit) < gueltig {
      element.image = fertig.bild.carPlayImage(carTraitCollection: traits)
      return
    }
    guard let quelle = quelle(art, nurGeladen: nurGeladen), !quelle.pfade.isEmpty else { return }
    Task { @MainActor in
      let pfade = quelle.pfade, plakette = quelle.plakette
      let bild = await Task.detached(priority: .utility) { zeichnen(pfade: pfade, plakette: plakette) }.value
      guard let bild else { return }
      ablage[schluessel] = (bild, Date())
      element.image = bild.carPlayImage(carTraitCollection: traits)
    }
  }

  // MARK: Welche Cover

  private struct Quelle {
    var pfade: [String]
    var plakette: UIImage?
  }

  private static func quelle(_ art: Art, nurGeladen: Bool) -> Quelle? {
    switch art {
    case let .bibliothek(typ):
      let plakette = typ.image
      switch typ {
      case .artists:
        return Quelle(pfade: kuenstler(nurGeladen: nurGeladen, zusatz: nil, samen: 1), plakette: plakette)
      case .favoriteArtists:
        return Quelle(pfade: kuenstler(nurGeladen: nurGeladen, zusatz: favorit, samen: 2), plakette: plakette)
      case .albums:
        return Quelle(pfade: alben(nurGeladen: nurGeladen, samen: 3), plakette: plakette)
      case .songs, .downloads:
        return Quelle(pfade: alben(nurGeladen: nurGeladen || typ == .downloads, samen: 4), plakette: plakette)
      case .genres:
        return Quelle(pfade: alben(nurGeladen: nurGeladen, samen: 5), plakette: plakette)
      case .favoriteAlbums:
        return Quelle(pfade: alben(nurGeladen: nurGeladen, zusatz: favorit, samen: 6), plakette: plakette)
      case .favoriteSongs:
        let mitLieblingssong = NSPredicate(format: "SUBQUERY(songs, $s, $s.isFavorite == YES).@count > 0")
        return Quelle(pfade: alben(nurGeladen: nurGeladen, zusatz: mitLieblingssong, samen: 7), plakette: plakette)
      case .newestAlbums:
        return Quelle(pfade: neuesteAlben(nurGeladen: nurGeladen), plakette: plakette)
      case .recentAlbums:
        let gespielt = NSPredicate(format: "recentIndex > 0")
        let sortierung = [NSSortDescriptor(key: "recentIndex", ascending: true)]
        return Quelle(
          pfade: alben(nurGeladen: nurGeladen, zusatz: gespielt, sortierung: sortierung, samen: 0),
          plakette: plakette
        )
      case .podcasts:
        return Quelle(pfade: podcasts(), plakette: plakette)
      case .directories, .playlists, .radios:
        return nil
      }
    case .zufallAlben:
      return Quelle(pfade: alben(nurGeladen: nurGeladen, samen: 8), plakette: UIImage(systemName: "shuffle"))
    case .zufallSongs:
      return Quelle(pfade: alben(nurGeladen: nurGeladen, samen: 9), plakette: UIImage(systemName: "shuffle"))
    case .weiterhoeren, .weiterhoerenPodcast:
      guard let laufend = appDelegate.player.currentlyPlaying,
            laufend.isPodcastEpisode == (art == .weiterhoerenPodcast),
            let pfad = laufend.imagePath(setting: einstellung) else { return nil }
      return Quelle(pfade: [pfad], plakette: UIImage(systemName: "play.fill"))
    }
  }

  private static let favorit = NSPredicate(format: "isFavorite == YES")
  private static let mitBild = NSPredicate(format: "artwork.status == %d", ImageStatus.CustomImage.rawValue)
  private static let geladen = NSPredicate(format: "SUBQUERY(songs, $s, $s.relFilePath != nil).@count > 0")

  private static var einstellung: ArtworkDisplayPreference {
    appDelegate.storage.settings.accounts.getSetting(HLAPI.shared.account?.info).read.artworkDisplayPreference
  }

  private static func praedikat(_ entitaet: String, nurGeladen: Bool, zusatz: NSPredicate?) -> NSPredicate {
    var teile = [mitBild]
    if let konto = HLAPI.shared.account { teile.append(NSPredicate(format: "account == %@", konto.managedObject.objectID)) }
    // Bibliothek (Musik oder Kinder) und Mediathek wie in den Listen der App; «Geladen» zeigt alles Geladene
    if nurGeladen {
      teile.append(geladen)
      if let bib = HLBibliothek.filter[entitaet] { teile.append(bib) }
    } else if let filter = HLListenFilter.praedikat(entitaet: entitaet, basis: nil, suche: false) {
      teile.append(filter)
    }
    if let zusatz { teile.append(zusatz) }
    return NSCompoundPredicate(andPredicateWithSubpredicates: teile)
  }

  private static func alben(
    nurGeladen: Bool,
    zusatz: NSPredicate? = nil,
    sortierung: [NSSortDescriptor] = [],
    samen: Int
  ) -> [String] {
    let anfrage = NSFetchRequest<AlbumMO>(entityName: "Album")
    anfrage.predicate = praedikat("Album", nurGeladen: nurGeladen, zusatz: zusatz)
    anfrage.sortDescriptors = sortierung
    anfrage.fetchLimit = sortierung.isEmpty ? 400 : 12
    let treffer = (try? appDelegate.storage.main.context.fetch(anfrage)) ?? []
    let reihe = sortierung.isEmpty ? tagesMischung(treffer, samen: samen) : treffer
    return pfade(reihe.map { Album(managedObject: $0) })
  }

  /// «Zuletzt hinzugefügt»: in der Mediathek die zuletzt dazugekommenen, sonst die neuesten des Servers.
  private static func neuesteAlben(nurGeladen: Bool) -> [String] {
    if HLListenFilter.mediathekAktiv, !nurGeladen {
      return alben(
        nurGeladen: false,
        sortierung: [NSSortDescriptor(key: "hlMediathekSeit", ascending: false)],
        samen: 0
      )
    }
    return alben(
      nurGeladen: nurGeladen,
      zusatz: NSPredicate(format: "newestIndex > 0"),
      sortierung: [NSSortDescriptor(key: "newestIndex", ascending: true)],
      samen: 0
    )
  }

  private static func kuenstler(nurGeladen: Bool, zusatz: NSPredicate?, samen: Int) -> [String] {
    let anfrage = NSFetchRequest<ArtistMO>(entityName: "Artist")
    anfrage.predicate = praedikat("Artist", nurGeladen: nurGeladen, zusatz: zusatz)
    anfrage.fetchLimit = 400
    let treffer = (try? appDelegate.storage.main.context.fetch(anfrage)) ?? []
    return pfade(tagesMischung(treffer, samen: samen).map { Artist(managedObject: $0) })
  }

  private static func podcasts() -> [String] {
    let anfrage = NSFetchRequest<PodcastMO>(entityName: "Podcast")
    anfrage.predicate = mitBild
    anfrage.fetchLimit = 40
    let treffer = (try? appDelegate.storage.main.context.fetch(anfrage)) ?? []
    return pfade(treffer.map { Podcast(managedObject: $0) })
  }

  /// Bis zu vier vorhandene Bilddateien, ohne doppelte.
  private static func pfade(_ eintraege: [AbstractLibraryEntity]) -> [String] {
    var gesehen = Set<String>()
    var ergebnis = [String]()
    for eintrag in eintraege {
      guard let pfad = eintrag.imagePath(setting: einstellung), !gesehen.contains(pfad),
            FileManager.default.fileExists(atPath: pfad) else { continue }
      gesehen.insert(pfad)
      ergebnis.append(pfad)
      if ergebnis.count == 4 { break }
    }
    return ergebnis
  }

  /// Gleiche Reihenfolge den ganzen Tag (je Kachel eigener Samen), am nächsten Tag eine andere.
  private static func tagesMischung<T>(_ liste: [T], samen: Int) -> [T] {
    let tag = Int(Date().timeIntervalSince1970 / 86400)
    var zahl = UInt64(truncatingIfNeeded: tag &* 7919 &+ samen &* 104_729)
    return liste.map { element -> (UInt64, T) in
      zahl = zahl &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
      return (zahl, element)
    }.sorted { $0.0 < $1.0 }.map(\.1)
  }

  #if DEBUG
    /// Test ohne CarPlay: `xcrun simctl launch … -HLKachelTest YES` schreibt alle Kacheln nach tmp/kachel-*.png.
    static func testen() {
      guard UserDefaults.standard.bool(forKey: "HLKachelTest") else { return }
      Task { @MainActor in
        try? await Task.sleep(for: .seconds(8))
        var arten: [(String, Art)] = LibraryDisplayType.allCases.map { ($0.englishName, .bibliothek($0)) }
        arten += [("Zufall Alben", .zufallAlben), ("Zufall Songs", .zufallSongs), ("Weiterhoeren", .weiterhoeren)]
        for geladen in [false, true] {
          for (name, art) in arten {
            guard let q = quelle(art, nurGeladen: geladen), let bild = zeichnen(pfade: q.pfade, plakette: q.plakette),
                  let daten = bild.pngData() else { continue }
            let datei = FileManager.default.temporaryDirectory
              .appendingPathComponent("kachel-\(geladen ? "geladen-" : "")\(name).png")
            try? daten.write(to: datei)
          }
        }
        if let kinder = HLBibliothek.shared.bibliotheken.first(where: \.istKinder) {
          let k = NSFetchRequest<ArtistMO>(entityName: "Artist")
          k.predicate = NSPredicate(format: "id IN %@", kinder.kuenstler)
          let a = NSFetchRequest<AlbumMO>(entityName: "Album")
          a.predicate = NSPredicate(format: "id IN %@", kinder.alben)
          let z = NSFetchRequest<AlbumMO>(entityName: "Album")
          z.predicate = NSPredicate(format: "id IN %@ AND recentIndex > 0", kinder.alben)
          let ctx = appDelegate.storage.main.context
          let namen = ((try? ctx.fetch(k)) ?? []).compactMap(\.name).sorted().prefix(8)
          print("HLKachelTest Kinder: \((try? ctx.count(for: k)) ?? -1) Künstler, \((try? ctx.count(for: a)) ?? -1) Alben, \((try? ctx.count(for: z)) ?? -1) zuletzt; \(namen)")
        }
        print("HLKachelTest fertig")
      }
    }
  #endif

  // MARK: Zeichnen

  /// Vier Cover als 2×2-Mosaik, sonst das erste ganz; Plakette unten rechts.
  nonisolated private static func zeichnen(pfade: [String], plakette: UIImage?) -> UIImage? {
    let bilder = pfade.compactMap { UIImage(contentsOfFile: $0) }
    guard !bilder.isEmpty else { return nil }
    let seite: CGFloat = 360
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    return UIGraphicsImageRenderer(size: CGSize(width: seite, height: seite), format: format).image { _ in
      if bilder.count >= 4 {
        let halb = seite / 2
        for (i, bild) in bilder.prefix(4).enumerated() {
          fuellen(bild, in: CGRect(x: CGFloat(i % 2) * halb, y: CGFloat(i / 2) * halb, width: halb, height: halb))
        }
      } else {
        fuellen(bilder[0], in: CGRect(x: 0, y: 0, width: seite, height: seite))
      }
      guard let plakette else { return }
      let durchmesser = seite * 0.3
      let kreis = CGRect(
        x: seite - durchmesser - seite * 0.05,
        y: seite - durchmesser - seite * 0.05,
        width: durchmesser,
        height: durchmesser
      )
      UIColor.black.withAlphaComponent(0.6).setFill()
      UIBezierPath(ovalIn: kreis).fill()
      let symbol = plakette.withTintColor(.white, renderingMode: .alwaysOriginal)
      let groesse = symbol.size
      let mass = durchmesser * 0.55 / max(groesse.width, groesse.height)
      let breite = groesse.width * mass, hoehe = groesse.height * mass
      symbol.draw(in: CGRect(x: kreis.midX - breite / 2, y: kreis.midY - hoehe / 2, width: breite, height: hoehe))
    }
  }

  /// Bild quadratisch zuschneiden und in das Feld zeichnen (wie «aspect fill»).
  nonisolated private static func fuellen(_ bild: UIImage, in feld: CGRect) {
    let mass = max(feld.width / bild.size.width, feld.height / bild.size.height)
    let breite = bild.size.width * mass, hoehe = bild.size.height * mass
    UIGraphicsGetCurrentContext()?.saveGState()
    UIBezierPath(rect: feld).addClip()
    bild.draw(in: CGRect(x: feld.midX - breite / 2, y: feld.midY - hoehe / 2, width: breite, height: hoehe))
    UIGraphicsGetCurrentContext()?.restoreGState()
  }
}
