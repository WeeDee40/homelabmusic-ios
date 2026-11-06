//
//  HLSpeicher.swift
//  HomeLabMusic
//
//  Speicher auf dem Gerät begrenzen (auf einem iPhone kamen 12 GB zusammen, Nov. 2026).
//
//  Songs: Amperfy speichert jeden gespielten Song dauerhaft («Auto Cache Played Items»); die Grenze
//  («Cache Size Limit») steht ab Werk auf «No Limit» und stoppt nur neue Downloads, alte löscht Amperfy nie.
//  Hier: einmal 4 GB als Grenze setzen (in den Einstellungen änderbar, «No Limit» wird respektiert) und ab
//  90 % der Grenze die am längsten nicht gehörten Songs löschen, bis 75 % erreicht sind. So stösst Amperfy
//  nie an die Grenze und speichert weiter, was gerade gehört wird. Amperfys «zuletzt gespielt» bleibt in
//  der Datenbank leer, darum führt HLSpeicher eine eigene Liste (Songwechsel in HLPlayer); ohne Eintrag
//  zählt das Speicherdatum der Datei. Der laufende Song bleibt.
//
//  Cover: Amperfy holte sie in Originalgrösse (bis 1,8 MB; seit Build 30 höchstens 1000 px, siehe
//  SubsonicServerApi) und behält sie ohne Grenze. Über 300 MB werden die ältesten gelöscht (bis 200 MB);
//  Amperfy lädt sie bei Bedarf neu.
//
//  This program is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//

import AmperfyKit
import UIKit

@MainActor
enum HLSpeicher {
  static let standardGrenze = 4 * 1024 * 1024 * 1024        // 4 GB
  static let coverGrenze: Int64 = 300_000_000
  static let coverZiel: Int64 = 200_000_000
  private static let gesetztSchluessel = "homelabmusic.speichergrenzeGesetzt"
  private static let gehoertSchluessel = "homelabmusic.zuletztGehoert"   // Song-ID -> Zeitpunkt
  private static var laeuft = false
  private static var uhr: Timer?

  private static var app: AppDelegate { UIApplication.shared.delegate as! AppDelegate }

  /// Einmal pro App-Start: Grenze setzen, gleich prüfen, danach alle 10 Minuten und beim Zurückkehren.
  static func einrichten() {
    let speicher = UserDefaults.standard
    if !speicher.bool(forKey: gesetztSchluessel) {
      if app.storage.settings.user.cacheLimit == 0 { app.storage.settings.user.cacheLimit = standardGrenze }
      speicher.set(true, forKey: gesetztSchluessel)
    }
    pruefen()
    uhr = Timer.scheduledTimer(withTimeInterval: 600, repeats: true) { _ in
      Task { @MainActor in pruefen() }
    }
    NotificationCenter.default.addObserver(
      forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main
    ) { _ in
      Task { @MainActor in pruefen() }
    }
  }

  // MARK: - Zuletzt gehört

  /// Von HLPlayer bei jedem Songwechsel. Höchstens 5000 Einträge (die ältesten fallen weg).
  static func gespielt(_ songId: String) {
    var liste = gehoert
    liste[songId] = Date().timeIntervalSince1970
    if liste.count > 5000 {
      for (id, _) in liste.sorted(by: { $0.value < $1.value }).prefix(liste.count - 5000) { liste[id] = nil }
    }
    UserDefaults.standard.set(liste, forKey: gehoertSchluessel)
  }

  private static var gehoert: [String: Double] {
    UserDefaults.standard.dictionary(forKey: gehoertSchluessel) as? [String: Double] ?? [:]
  }

  // MARK: - Aufräumen

  static func pruefen() {
    guard !laeuft, let account = HLAPI.shared.account else { return }
    laeuft = true
    Task {
      let grenze = Int64(app.storage.settings.user.cacheLimit)
      if grenze > 0 {                                         // 0: «No Limit» bewusst gewählt
        await songsAufraeumen(account: account, grenze: grenze)
      }
      await coverAufraeumen(account: account)
      laeuft = false
    }
  }

  private static func songsAufraeumen(account: Account, grenze: Int64) async {
    let fm = CacheFileManager.shared
    guard let rel = fm.getRelSongsDirectory(for: account.info),
          let ordner = fm.getAbsoluteAmperfyPath(relFilePath: rel) else { return }
    var schutz = Set<String>()
    if let laufend = app.player.currentlyPlaying?.id { schutz.insert(laufend) }
    let weg = await aeltesteDateien(
      in: ordner, ab: grenze * 9 / 10, bis: grenze * 3 / 4, zuletzt: gehoert, ausser: schutz
    )
    guard !weg.isEmpty else { return }
    let bib = app.storage.main.library
    var geloescht = 0
    for song in bib.getCachedSongs(for: account) {
      guard let pfad = song.relFilePath, weg.contains(pfad.lastPathComponent) else { continue }
      bib.deleteCache(ofPlayable: song)                       // Datei, Pfad und Amperfys Summe
      geloescht += 1
      if geloescht % 25 == 0 {
        bib.saveContext()
        await Task.yield()                                    // beim ersten Mal Hunderte Dateien
      }
    }
    bib.saveContext()
    fm.recalculatePlayableCacheSizes()
    print("HLSpeicher: \(geloescht) Songs gelöscht, belegt jetzt \(fm.completePlayableCacheSize / 1_000_000) MB")
  }

  /// Älteste Cover-Dateien löschen und ihre Einträge zurücksetzen, damit Amperfy sie bei Bedarf neu lädt.
  private static func coverAufraeumen(account: Account) async {
    let fm = CacheFileManager.shared
    guard let rel = fm.getRelArtworkDirectory(for: account.info),
          let ordner = fm.getAbsoluteAmperfyPath(relFilePath: rel) else { return }
    let weg = await aeltesteDateien(in: ordner, ab: coverGrenze, bis: coverZiel, zuletzt: [:], ausser: [])
    guard !weg.isEmpty else { return }
    let bib = app.storage.main.library
    var geloescht = 0
    for artwork in bib.getArtworks(for: account) {
      guard let pfad = artwork.relFilePath, weg.contains(pfad.lastPathComponent) else { continue }
      if let abs = fm.getAbsoluteAmperfyPath(relFilePath: pfad) { try? FileManager.default.removeItem(at: abs) }
      artwork.relFilePath = nil
      artwork.status = .NotChecked
      // Amperfy lädt ein Cover mit erledigtem Download-Eintrag nie wieder (DownloadRequestManager.addLowPrio)
      if let dl = artwork.managedObject.download { artwork.managedObject.managedObjectContext?.delete(dl) }
      geloescht += 1
      if geloescht % 100 == 0 {
        bib.saveContext()
        await Task.yield()
      }
    }
    bib.saveContext()
    print("HLSpeicher: \(geloescht) Cover gelöscht")
  }

  /// Dateinamen, die weg sollen: nur wenn der Ordner über `ab` liegt, dann die ältesten bis unter `bis`.
  /// Alter = zuletzt gehört (Dateiname ohne Endung = ID), sonst Änderungsdatum der Datei. Im Hintergrund,
  /// weil es Tausende Dateien sein können.
  nonisolated private static func aeltesteDateien(
    in ordner: URL, ab: Int64, bis: Int64, zuletzt: [String: Double], ausser: Set<String>
  ) async -> Set<String> {
    await Task.detached(priority: .utility) {
      let schluessel: [URLResourceKey] = [.fileSizeKey, .contentModificationDateKey]
      let dateien = (try? FileManager.default.contentsOfDirectory(at: ordner, includingPropertiesForKeys: schluessel)) ?? []
      var liste = dateien.compactMap { url -> (name: String, groesse: Int64, alter: Double)? in
        guard let w = try? url.resourceValues(forKeys: Set(schluessel)), let g = w.fileSize else { return nil }
        let id = url.deletingPathExtension().lastPathComponent
        let datei = (w.contentModificationDate ?? .distantPast).timeIntervalSince1970
        return (url.lastPathComponent, Int64(g), max(zuletzt[id] ?? 0, datei))
      }
      var summe = liste.reduce(Int64(0)) { $0 + $1.groesse }
      guard summe > ab else { return [] }
      liste.sort { $0.alter < $1.alter }
      var namen = Set<String>()
      for d in liste where summe > bis {
        guard !ausser.contains((d.name as NSString).deletingPathExtension) else { continue }
        namen.insert(d.name)
        summe -= d.groesse
      }
      return namen
    }.value
  }
}
