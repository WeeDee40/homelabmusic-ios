//
//  HLCover.swift
//  HomeLabMusic
//
//  Playlist-Cover von Navidrome statt Amperfys Mosaik aus den ersten vier Songs: Navidrome liefert das
//  hochgeladene Bild (z. B. die Wochenmix-Cover) und sonst ein eigenes Mosaik. Zwischengespeichert
//  für die Laufzeit der App.
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
  private static let speicher = NSCache<NSString, UIImage>()
  private static var fehlgeschlagen = Set<String>()

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
    if let b = speicher.object(forKey: id as NSString) { return b }
    guard !id.isEmpty, !fehlgeschlagen.contains(id),
          let req = HLAPI.shared.subsonicAnfrage("getCoverArt", ["id": "pl-\(id)", "size": "600"]) else { return nil }
    guard let (daten, antwort) = try? await URLSession.shared.data(for: req),
          (antwort as? HTTPURLResponse)?.statusCode == 200,
          (antwort as? HTTPURLResponse)?.mimeType?.hasPrefix("image") == true,
          let b = UIImage(data: daten) else {
      fehlgeschlagen.insert(id)                        // nicht bei jeder Anzeige erneut versuchen
      return nil
    }
    speicher.setObject(b, forKey: id as NSString)
    return b
  }
}
