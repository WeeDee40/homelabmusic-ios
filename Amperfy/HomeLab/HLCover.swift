//
//  HLCover.swift
//  HomeLabMusic
//
//  Playlist-Cover von Navidrome statt Amperfys Mosaik aus den ersten vier Songs: Navidrome liefert das
//  hochgeladene Bild (z. B. die Wochenmix-Cover) und sonst ein eigenes Mosaik.
//
//  Die Bilder liegen auf dem Gerät (HLBildAblage, unten in dieser Datei; auch für die Senderbilder aus
//  HLPlayer.senderBild). Ohne Verbindung zum Server (Tailscale hängt, Funkloch) zeigt die App darum die
//  zuletzt geladenen Bilder, und ein fehlgeschlagener Abruf wird von selbst wiederholt. Bis Build 36
//  merkte sie sich einen Fehlschlag bis zum nächsten App-Start und zeigte so lange Mosaik und Radio-Symbol.
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
enum HLCover {
  static func einrichten() {
    EntityImageView.playlistCover = { id in await bild(id) }
    LibraryEntityImage.fehlendesKuenstlerBild = { artist in kuenstlerBild(artist) }
  }

  // MARK: - Künstlerbilder

  private static var kuenstlerVersucht = Set<NSManagedObjectID>()

  /// Amperfy gibt nur den Künstlern aus der ersten Vollsynchronisation (getArtists) einen Bildeintrag.
  /// Wer später über Songs oder Alben dazukommt (z. B. ein erfüllter Wunsch), bleibt ohne und zeigt das
  /// Mikrofon. Hier einmal pro App-Lauf über die Künstlersuche nachholen (eine Anfrage, liefert coverArt).
  /// Doppelte Einträge mit derselben Server-ID (Amperfy-Fehler #809) füllt Amperfy nur einmal: dann das
  /// Bild des Zwillings übernehmen.
  static func kuenstlerBild(_ artist: Artist) {
    guard artist.artwork == nil, !artist.id.isEmpty, !artist.name.isEmpty,
          let konto = artist.account?.info,
          kuenstlerVersucht.insert(artist.managedObject.objectID).inserted else { return }
    let app = UIApplication.shared.delegate as! AppDelegate
    Task { @MainActor in
      if zwillingsBild(artist) == nil {
        try? await app.getMeta(konto).librarySyncer.searchArtists(searchText: artist.name)
      }
      if artist.artwork == nil, let bild = zwillingsBild(artist) {
        artist.artwork = bild
        app.storage.main.library.saveContext()
      }
      guard let art = artist.artwork else { return }
      app.getMeta(konto).artworkDownloadManager.download(object: art)
    }
  }

  private static func zwillingsBild(_ artist: Artist) -> Artwork? {
    guard let kontext = artist.managedObject.managedObjectContext else { return nil }
    let anfrage = NSFetchRequest<ArtistMO>(entityName: "Artist")
    guard let konto = artist.managedObject.account else { return nil }
    anfrage.predicate = NSPredicate(format: "id == %@ AND account == %@ AND artwork != nil", artist.id, konto)
    anfrage.fetchLimit = 1
    guard let mo = (try? kontext.fetch(anfrage))?.first, let bild = mo.artwork else { return nil }
    return Artwork(managedObject: bild)
  }

  private static var versucht = [String: Date]()

  /// Player: Song-Cover und (als Ersatz) Album-Cover anfordern; Amperfy tut das nur in Listen. Ein
  /// fehlgeschlagener oder erledigter Download-Eintrag ohne Datei blockiert Amperfy bis zum nächsten
  /// Kaltstart (DownloadRequestManager.addLowPrio ignoriert vorhandene Cover-Einträge), darum wegräumen.
  /// Je Cover höchstens alle 5 Minuten.
  static func nachladen(_ p: AbstractPlayable) {
    guard let konto = p.account?.info else { return }
    let app = UIApplication.shared.delegate as! AppDelegate
    let fm = CacheFileManager.shared
    var geaendert = false
    for art in [p.artwork, p.asSong?.album?.artwork].compactMap({ $0 }) where art.status != .IsDefaultImage {
      if let pfad = art.relFilePath, fm.fileExits(relFilePath: pfad) { continue }   // da
      let schluessel = art.uniqueID
      if let t = versucht[schluessel], Date().timeIntervalSince(t) < 300 { continue }
      versucht[schluessel] = Date()
      if art.relFilePath != nil {                       // Pfad ohne Datei
        art.relFilePath = nil
        art.status = .NotChecked
        geaendert = true
      }
      if let dl = art.managedObject.download, dl.errorDate != nil || dl.finishDate != nil {
        art.managedObject.managedObjectContext?.delete(dl)
        geaendert = true
      }
      if geaendert { app.storage.main.library.saveContext() }
      app.getMeta(konto).artworkDownloadManager.download(object: art)
    }
  }

  private static func bild(_ id: String) async -> UIImage? {
    guard !id.isEmpty else { return nil }
    // auffrischen: Das Cover einer Playlist kann sich ändern, ihre ID bleibt gleich
    return await HLBildAblage.shared.bild("pl-\(id)", auffrischen: true) {
      HLAPI.shared.subsonicAnfrage("getCoverArt", ["id": "pl-\(id)", "size": "600"])
    }
  }
}

// MARK: - Bilder auf dem Gerät

/// Ablage für Bilder vom eigenen Server, die Amperfy nicht kennt (Playlist-Cover, Senderbilder):
/// im Speicher, als Datei unter Caches/hl-bilder und sonst vom Server.
@MainActor
final class HLBildAblage {
  static let shared = HLBildAblage()

  private enum Antwort {
    case bild(UIImage, Data)
    case keines        // Server hat geantwortet, liefert aber kein Bild (404 oder kein Bildformat)
    case fehler        // keine Antwort oder vorübergehender Fehler (401, 5xx): später nochmals
  }

  private static let pausen: [Double] = [5, 15, 30, 60, 120]   // Sekunden zwischen den Versuchen
  private static let hoechstens = 400                          // Dateien

  private let speicher = NSCache<NSString, UIImage>()
  private var laufend = [String: Task<UIImage?, Never>]()
  private var erledigt = Set<String>()            // in diesem App-Lauf hat der Server schon geantwortet
  private var versucht = [String: Date]()         // letztes Auffrischen ohne Antwort
  private let ordner: URL

  private init() {
    ordner = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("hl-bilder", isDirectory: true)
    try? FileManager.default.createDirectory(at: ordner, withIntermediateDirectories: true)
    aufraeumen()
  }

  /// Bild zu einem Schlüssel. `anfrage` baut die Abfrage an den Server (jedes Mal neu, das Salz wechselt).
  /// `auffrischen`: ein gespeichertes Bild einmal je App-Lauf im Hintergrund mit dem Server abgleichen;
  /// angezeigt wird das neue Bild beim nächsten Aufbau der Ansicht.
  func bild(_ schluessel: String, auffrischen: Bool, anfrage: @escaping @MainActor () -> URLRequest?) async -> UIImage? {
    if let b = speicher.object(forKey: schluessel as NSString) {
      if auffrischen { abgleichen(schluessel, anfrage) }
      return b
    }
    let datei = pfad(schluessel)
    if let daten = try? Data(contentsOf: datei), let b = UIImage(data: daten) {
      speicher.setObject(b, forKey: schluessel as NSString)
      if auffrischen { abgleichen(schluessel, anfrage) }
      return b
    }
    if erledigt.contains(schluessel) { return nil }   // Server hat in diesem Lauf schon «kein Bild» gesagt
    if let t = laufend[schluessel] { return await t.value }
    let aufgabe = Task { @MainActor [weak self] () -> UIImage? in
      defer { self?.laufend[schluessel] = nil }
      for pause in [0.0] + Self.pausen {
        if pause > 0 { try? await Task.sleep(for: .seconds(pause)) }
        guard let self else { return nil }
        switch await self.holen(anfrage) {
        case let .bild(b, daten):
          self.ablegen(schluessel, b, daten)
          return b
        case .keines:
          self.erledigt.insert(schluessel)
          return nil
        case .fehler:
          continue
        }
      }
      return nil   // nichts gemerkt: die nächste Anzeige versucht es wieder
    }
    laufend[schluessel] = aufgabe
    return await aufgabe.value
  }

  /// Gespeichertes Bild im Hintergrund mit dem Server abgleichen (ein Versuch, höchstens einmal je Minute).
  private func abgleichen(_ schluessel: String, _ anfrage: @escaping @MainActor () -> URLRequest?) {
    guard !erledigt.contains(schluessel), laufend[schluessel] == nil else { return }
    if let t = versucht[schluessel], Date().timeIntervalSince(t) < 60 { return }
    versucht[schluessel] = Date()
    laufend[schluessel] = Task { @MainActor [weak self] () -> UIImage? in
      guard let self else { return nil }
      defer { self.laufend[schluessel] = nil }
      switch await self.holen(anfrage) {
      case let .bild(b, daten):
        self.erledigt.insert(schluessel)
        if (try? Data(contentsOf: self.pfad(schluessel))) != daten { self.ablegen(schluessel, b, daten) }
        return b
      case .keines:                                   // Bild gibt es auf dem Server nicht mehr
        self.erledigt.insert(schluessel)
        self.speicher.removeObject(forKey: schluessel as NSString)
        try? FileManager.default.removeItem(at: self.pfad(schluessel))
        return nil
      case .fehler:
        return self.speicher.object(forKey: schluessel as NSString)
      }
    }
  }

  #if DEBUG
    /// Zum Prüfen im Simulator: Solange die Datei Caches/hl-ohne-server existiert, gilt der Server als
    /// nicht erreichbar (Playlist-Cover, Senderbilder, Liste der Senderbilder). Anlegen und löschen vom Mac aus.
    static var ohneServer: Bool {
      FileManager.default.fileExists(atPath: FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("hl-ohne-server").path)
    }
  #endif

  private func holen(_ anfrage: @MainActor () -> URLRequest?) async -> Antwort {
    #if DEBUG
      if Self.ohneServer { return .fehler }
    #endif
    guard let req = anfrage() else { return .fehler }   // kein Konto angemeldet
    guard let (daten, antwort) = try? await URLSession.shared.data(for: req),
          let http = antwort as? HTTPURLResponse else { return .fehler }
    if http.statusCode == 200 {
      guard http.mimeType?.hasPrefix("image") == true, let b = UIImage(data: daten) else { return .keines }
      return .bild(b, daten)
    }
    return http.statusCode == 404 ? .keines : .fehler
  }

  private func ablegen(_ schluessel: String, _ bild: UIImage, _ daten: Data) {
    erledigt.insert(schluessel)
    speicher.setObject(bild, forKey: schluessel as NSString)
    try? daten.write(to: pfad(schluessel), options: .atomic)
  }

  private func pfad(_ schluessel: String) -> URL {
    let name = String(schluessel.map { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" ? $0 : "_" })
    return ordner.appendingPathComponent(name)
  }

  /// Mehr als `hoechstens` Dateien: die ältesten löschen (gelöschte Playlists, ersetzte Senderbilder).
  private func aufraeumen() {
    let fm = FileManager.default
    guard let dateien = try? fm.contentsOfDirectory(at: ordner, includingPropertiesForKeys: [.contentModificationDateKey]),
          dateien.count > Self.hoechstens else { return }
    let nachAlter = dateien.sorted {
      let a = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
      let b = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
      return a < b
    }
    for datei in nachAlter.prefix(dateien.count - Self.hoechstens) { try? fm.removeItem(at: datei) }
  }
}
