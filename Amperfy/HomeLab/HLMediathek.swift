//
//  HLMediathek.swift
//  HomeLabMusic
//
//  «Mediathek»: was eine Person bewusst zu ihrer Musik hinzugefügt hat (wie bei Apple Music).
//  Gespeichert auf dem Server als private Navidrome-Playlist der Person, erkannt an der Kennung im
//  Kommentar (der Name darf sich ändern). Damit ist die Mediathek auf iPhone, iPad und Mac gleich.
//  In der App ist die Playlist ausgeblendet; beim Abgleich setzen wir in Core Data pro Konto:
//    Song.hlInMediathek, Artist.hlInMediathek, Album.hlMediathekSeit (Modellversion «HomeLabMusic 1»).
//  hlMediathekSeit ist kein echtes Datum, sondern die Reihenfolge in der Playlist (spätester eigener Song
//  des Albums): so ist «Neu in meiner Mediathek» auf allen Geräten gleich sortiert.
//
//  This program is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//

import AmperfyKit
import CoreData
import UIKit

// MARK: - Felder der Modellversion «HomeLabMusic 1»

extension SongMO {
  @NSManaged public var hlInMediathek: Bool
}

extension ArtistMO {
  @NSManaged public var hlInMediathek: Bool
}

extension AlbumMO {
  @NSManaged public var hlMediathekSeit: Date?
}

// MARK: - HLMediathek

@MainActor
final class HLMediathek {
  static let shared = HLMediathek()

  /// Steht im Kommentar der Playlist; daran wird sie erkannt.
  static let kennung = "homelabmusic-mediathek"
  static let playlistName = "Mediathek"

  /// Eintrag der Playlist, wie Navidrome ihn liefert (für Abgleich und späteres Wiederfinden nach ID-Wechsel).
  struct Eintrag: Codable, Equatable, Sendable {
    var id: String
    var titel: String
    var kuenstler: String
    var dauer: Int
    var mbid: String?
  }

  /// Stand pro Konto (auf dem Gerät).
  private struct Stand: Codable {
    var playlistId: String?
    var geaendert: String?           // «changed» der Playlist beim letzten Abgleich
    var kommentar: String?
  }

  enum Fehler: LocalizedError {
    case keinKonto, keinePlaylist, server(String)
    var errorDescription: String? {
      switch self {
      case .keinKonto: return "Kein Konto angemeldet."
      case .keinePlaylist: return "Die Mediathek ist auf dem Server noch nicht angelegt."
      case let .server(t): return t
      }
    }
  }

  /// Nach jedem Abgleich (Listen neu laden).
  static let geaendertNotification = Notification.Name("HLMediathekGeaendert")

  private var laeuft: Task<Void, Never>?
  fileprivate var uebernahmeFehlschlag = Date.distantPast
  private var zuletzt = Date.distantPast

  private var account: Account? { HLAPI.shared.account }
  private var storage: PersistentStorage { AmperKit.shared.storage }

  // MARK: Stand

  private func standSchluessel(_ account: Account) -> String { "homelabmusic.mediathek.\(account.info.ident)" }

  private func stand(_ account: Account) -> Stand {
    guard let d = UserDefaults.standard.data(forKey: standSchluessel(account)),
          let s = try? JSONDecoder().decode(Stand.self, from: d) else { return Stand() }
    return s
  }

  private func speichern(_ s: Stand, _ account: Account) {
    if let d = try? JSONEncoder().encode(s) { UserDefaults.standard.set(d, forKey: standSchluessel(account)) }
  }

  /// Playlist-ID der Mediathek des aktiven Kontos (zum Ausblenden), nil solange unbekannt.
  var playlistId: String? { account.flatMap { stand($0).playlistId } }

  /// Kommentar der Playlist (Etappe Migration merkt sich darin den Stand der Erstübernahme).
  var kommentar: String? { account.flatMap { stand($0).kommentar } }

  // MARK: Start

  private var kontoIdent: String?

  /// Kontowechsel (HLTab.einrichten): Stand des neuen Kontos, sofort abgleichen.
  func kontoPruefen() {
    let ident = account?.info.ident
    guard ident != kontoIdent else { return }
    let ersterStart = kontoIdent == nil
    kontoIdent = ident
    if !ersterStart { abgleichen(erzwingen: true) }
  }

  func einrichten() {
    NotificationCenter.default.addObserver(
      forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main
    ) { _ in
      MainActor.assumeIsolated { HLMediathek.shared.abgleichen() }
    }
    #if DEBUG
      // Test ohne Oberfläche: xcrun simctl launch … -HLMediathekTest "add:id1,id2" | "remove:id1" | "delete" | "probe"
      // (Probe: Erstübernahme sammeln, nichts schreiben; Ergebnis in tmp/hl-probe.json)
      if let test = UserDefaults.standard.string(forKey: "HLMediathekTest") {
        let teile = test.split(separator: ":", maxSplits: 1).map(String.init)
        let ids = (teile.count > 1 ? teile[1] : "").split(separator: ",").map(String.init)
        Task {
          do {
            if teile.first == "add" { try await hinzufuegen(songIds: ids) }
            if teile.first == "remove" { try await entfernen(songIds: ids) }
            if teile.first == "probe", let account {
              let q = try await quellenSammeln(account, server: true, geraet: true, wuenscheNoetig: false)
              let ids = try await ohneKinder(q.alle, album: q.album, account: account)
              print("HLMediathekTest Probe: Favoriten \(q.favoriten.count), Favoriten-Alben \(q.favoritenAlben.count), " +
                "Playlists \(q.playlists.count), Wünsche \(q.wuensche.count), Downloads \(q.downloads.count) → " +
                "\(ids.count) Songs ohne Doppelte und Kinder")
              let d = try JSONSerialization.data(withJSONObject: [
                "favoriten": q.favoriten, "favoritenAlben": q.favoritenAlben, "playlists": q.playlists,
                "wuensche": q.wuensche, "downloads": q.downloads, "ergebnis": ids,
              ])
              try d.write(to: FileManager.default.temporaryDirectory.appendingPathComponent("hl-probe.json"))
            }
            let gefunden = try await playlistFinden()?["id"] as? String
            if teile.first == "delete", let id = gefunden {
              _ = await HLAPI.shared.subsonic("deletePlaylist", ["id": id])
              if let k = geraetSchluessel { UserDefaults.standard.removeObject(forKey: k) }
              try await abgleichenUndWarten()
            }
            print("HLMediathekTest fertig: \(test), Playlist \(playlistId ?? "-")")
          } catch { print("HLMediathekTest Fehler: \(error)") }
        }
        return
      }
    #endif
    abgleichen(erzwingen: true)
  }

  /// Abgleich im Hintergrund; höchstens einmal pro Minute, ausser erzwungen.
  func abgleichen(erzwingen: Bool = false) {
    guard laeuft == nil, erzwingen || Date().timeIntervalSince(zuletzt) > 60 else { return }
    zuletzt = Date()
    laeuft = Task {
      defer { laeuft = nil }
      do { try await exklusiv { try await self.abgleichJetzt(erzwingen: erzwingen) } } catch {
        print("HLMediathek: Abgleich fehlgeschlagen: \(error)")
      }
    }
  }

  /// Abgleich jetzt (erzwungen) und abwarten.
  func abgleichenUndWarten() async throws {
    zuletzt = Date()
    try await exklusiv { try await self.abgleichJetzt(erzwingen: true) }
  }

  /// Abgleiche und Änderungen laufen strikt nacheinander: zwei gleichzeitige Playlist-Abgleiche von
  /// Amperfy legen dieselben Songs doppelt an.
  private var sperre: Task<Void, Never>?

  private func exklusiv<T: Sendable>(_ arbeit: @escaping @MainActor () async throws -> T) async throws -> T {
    let vorher = sperre
    let aufgabe = Task { @MainActor () async throws -> T in
      await vorher?.value
      return try await arbeit()
    }
    sperre = Task { _ = try? await aufgabe.value }
    return try await aufgabe.value
  }

  // MARK: Abgleich

  private func abgleichJetzt(erzwingen: Bool = false) async throws {
    guard let account else { throw Fehler.keinKonto }
    do { try await uebernahmeWennNoetig(account) } catch {
      print("HLMediathek: Erstübernahme noch nicht möglich: \(error)")
    }
    var s = stand(account)
    guard let playlist = try await playlistFinden() else {
      // (noch) keine Mediathek: nichts markieren; Anlegen übernimmt die Erstübernahme
      let hatte = s.playlistId != nil
      if hatte || erzwingen { try await flagsSetzen([], account: account) }
      speichern(Stand(), account)
      if hatte { HLBibliothek.shared.playlistFilterNeu() }
      return
    }
    let id = playlist["id"] as? String
    let geaendert = playlist["changed"] as? String
    let neueId = id != s.playlistId
    s.playlistId = id
    s.kommentar = playlist["comment"] as? String
    if neueId { HLBibliothek.shared.playlistFilterNeu() }
    guard erzwingen || neueId || geaendert != s.geaendert || !flagsGesetzt(account) else {
      speichern(s, account)
      return
    }
    let eintraege = try await eintraegeLaden(id!)
    try await songsSicherstellen(eintraege.map(\.id), playlistId: id!, account: account)
    try await flagsSetzen(eintraege, account: account)
    HLListenFilter.neuBerechnet()
    s.geaendert = geaendert
    speichern(s, account)
    schattenSpeichern(eintraege, account)
    UserDefaults.standard.set(true, forKey: standSchluessel(account) + ".flags")
    NotificationCenter.default.post(name: Self.geaendertNotification, object: nil)
  }

  private func flagsGesetzt(_ account: Account) -> Bool {
    UserDefaults.standard.bool(forKey: standSchluessel(account) + ".flags")
  }

  /// Eigene Playlist mit der Kennung im Kommentar. Bei mehreren (zwei Geräte gleichzeitig angelegt)
  /// gilt die älteste.
  private func playlistFinden() async throws -> [String: Any]? {
    guard let ich = HLAPI.shared.benutzername else { throw Fehler.keinKonto }
    guard let antwort = await HLAPI.shared.subsonic("getPlaylists") else {
      throw Fehler.server("Playlists nicht lesbar.")
    }
    let liste = (antwort["playlists"] as? [String: Any])?["playlist"] as? [[String: Any]] ?? []
    return liste
      .filter { ($0["owner"] as? String) == ich && (($0["comment"] as? String)?.contains(Self.kennung) ?? false) }
      .min { ($0["created"] as? String ?? "") < ($1["created"] as? String ?? "") }
  }

  private func eintraegeLaden(_ playlistId: String) async throws -> [Eintrag] {
    guard let antwort = await HLAPI.shared.subsonic("getPlaylist", ["id": playlistId]) else {
      throw Fehler.server("Mediathek nicht lesbar.")
    }
    let songs = (antwort["playlist"] as? [String: Any])?["entry"] as? [[String: Any]] ?? []
    return songs.compactMap { e in
      guard let id = e["id"] as? String else { return nil }
      let mbid = (e["musicBrainzId"] as? String).flatMap { $0.isEmpty ? nil : $0 }
      return Eintrag(id: id, titel: e["title"] as? String ?? "", kuenstler: e["artist"] as? String ?? "",
                     dauer: e["duration"] as? Int ?? 0, mbid: mbid)
    }
  }

  /// Songs, die auf dem Gerät noch fehlen (Amperfy lädt Songs erst beim Öffnen eines Albums), über
  /// Amperfys eigenen Playlist-Abgleich anlegen lassen: legt Songs, Alben und Künstler vollständig an.
  private func songsSicherstellen(_ ids: [String], playlistId: String, account: Account) async throws {
    guard !ids.isEmpty else { return }
    let accountId = account.managedObject.objectID
    let fehlen = try await storage.async.performAndGet { c in
      let konto = c.context.object(with: accountId) as! AccountMO
      var vorhanden = Set<String>()
      for teil in ids.hlTeile(500) {
        let r = NSFetchRequest<NSDictionary>(entityName: "Song")
        r.resultType = .dictionaryResultType
        r.propertiesToFetch = ["id"]
        r.predicate = NSPredicate(format: "account == %@ AND id IN %@ AND title != nil", konto, teil)
        for d in (try? c.context.fetch(r)) ?? [] { if let id = d["id"] as? String { vorhanden.insert(id) } }
      }
      return ids.count - vorhanden.count
    }
    guard fehlen > 0 else { return }
    let syncer = (UIApplication.shared.delegate as! AppDelegate).getMeta(account.info).librarySyncer
    let bibliothek = storage.main.library
    if bibliothek.getPlaylist(for: account, id: playlistId) == nil {
      try await syncer.syncDownPlaylistsWithoutSongs()
    }
    guard let playlist = bibliothek.getPlaylist(for: account, id: playlistId) else { return }
    try await syncer.syncDown(playlist: playlist)
  }

  /// Markierungen setzen, ein Durchgang im Hintergrund-Kontext.
  private func flagsSetzen(_ eintraege: [Eintrag], account: Account) async throws {
    let accountId = account.managedObject.objectID
    var position = [String: Int]()
    for (i, e) in eintraege.enumerated() { position[e.id] = i + 1 }
    let positionen = position
    try await storage.async.perform { c in
      let ctx = c.context
      let konto = ctx.object(with: accountId) as! AccountMO

      // Songs
      let alt = NSFetchRequest<SongMO>(entityName: "Song")
      alt.predicate = NSPredicate(format: "account == %@ AND hlInMediathek == YES", konto)
      for s in (try? ctx.fetch(alt)) ?? [] where positionen[s.id] == nil { s.hlInMediathek = false }
      var albumPos = [NSManagedObjectID: Int]()
      var kuenstler = Set<NSManagedObjectID>()
      for teil in Array(positionen.keys).hlTeile(500) {
        let r = NSFetchRequest<SongMO>(entityName: "Song")
        r.predicate = NSPredicate(format: "account == %@ AND id IN %@", konto, teil)
        r.relationshipKeyPathsForPrefetching = ["album", "artist", "album.artist"]
        for s in (try? ctx.fetch(r)) ?? [] {
          if !s.hlInMediathek { s.hlInMediathek = true }
          let pos = positionen[s.id] ?? 0
          if let album = s.album { albumPos[album.objectID] = max(albumPos[album.objectID] ?? 0, pos) }
          if let k = s.artist { kuenstler.insert(k.objectID) }
          if let k = s.album?.artist { kuenstler.insert(k.objectID) }
        }
      }

      // Alben: Reihenfolge als Datum (Sekunden nach dem Referenzdatum)
      let altAlben = NSFetchRequest<AlbumMO>(entityName: "Album")
      altAlben.predicate = NSPredicate(format: "account == %@ AND hlMediathekSeit != nil", konto)
      for a in (try? ctx.fetch(altAlben)) ?? [] where albumPos[a.objectID] == nil { a.hlMediathekSeit = nil }
      for (id, pos) in albumPos {
        guard let a = try? ctx.existingObject(with: id) as? AlbumMO else { continue }
        let datum = Date(timeIntervalSinceReferenceDate: TimeInterval(pos))
        if a.hlMediathekSeit != datum { a.hlMediathekSeit = datum }
      }

      // Künstler
      let altK = NSFetchRequest<ArtistMO>(entityName: "Artist")
      altK.predicate = NSPredicate(format: "account == %@ AND hlInMediathek == YES", konto)
      for k in (try? ctx.fetch(altK)) ?? [] where !kuenstler.contains(k.objectID) { k.hlInMediathek = false }
      for id in kuenstler {
        guard let k = try? ctx.existingObject(with: id) as? ArtistMO, !k.hlInMediathek else { continue }
        k.hlInMediathek = true
      }
    }
  }

  // MARK: Schatten (für den ID-Abgleich nach einem Re-Import)

  private func schattenDatei(_ account: Account) -> URL {
    FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("hl-mediathek-\(account.info.ident).json")
  }

  private func schattenSpeichern(_ eintraege: [Eintrag], _ account: Account) {
    let datei = schattenDatei(account)
    try? FileManager.default.createDirectory(at: datei.deletingLastPathComponent(), withIntermediateDirectories: true)
    if let d = try? JSONEncoder().encode(eintraege) { try? d.write(to: datei, options: .atomic) }
  }

  func schatten() -> [Eintrag] {
    guard let account, let d = try? Data(contentsOf: schattenDatei(account)) else { return [] }
    return (try? JSONDecoder().decode([Eintrag].self, from: d)) ?? []
  }

  // MARK: Ändern

  /// Gehört der Song zur Mediathek? (laut letztem Abgleich bzw. eigener Änderung)
  func enthaelt(_ song: Song) -> Bool { song.managedObject.hlInMediathek }

  /// Kommentar der Playlist; `uebernahmeMarke` zeigt, dass die Erstübernahme für diese Person erledigt ist.
  static let uebernahmeMarke = "uebernahme=1"
  private static func kommentarText(uebernahme: Bool) -> String {
    "\(kennung) – von HomeLabMusic verwaltet, bitte nicht umbenennen oder löschen."
      + (uebernahme ? " \(uebernahmeMarke)" : "")
  }

  /// Legt die Playlist an (leer), falls es sie noch nicht gibt. Gibt die ID zurück.
  /// Haben zwei Geräte gleichzeitig angelegt, gilt die ältere; die eigene neue wird wieder gelöscht.
  @discardableResult
  func anlegen() async throws -> String {
    if let p = try await playlistFinden(), let id = p["id"] as? String { return id }
    guard let antwort = await HLAPI.shared.subsonic("createPlaylist", ["name": Self.playlistName]),
          let id = (antwort["playlist"] as? [String: Any])?["id"] as? String
    else { throw Fehler.server("Mediathek konnte nicht angelegt werden.") }
    let text = Self.kommentarText(uebernahme: false)
    guard await HLAPI.shared.subsonic("updatePlaylist", ["playlistId": id, "comment": text, "public": "false"]) != nil
    else { throw Fehler.server("Mediathek konnte nicht beschriftet werden.") }
    if let aelter = try await playlistFinden()?["id"] as? String, aelter != id {
      _ = await HLAPI.shared.subsonic("deletePlaylist", ["id": id])
      return aelter
    }
    return id
  }

  /// Songs ohne Abgleich an die Playlist anhängen; schon enthaltene und doppelte werden übersprungen.
  /// Gibt die tatsächlich neuen zurück.
  @discardableResult
  private func zufuegen(_ songIds: [String], playlistId id: String) async throws -> [String] {
    let schon = Set(try await eintraegeLaden(id).map(\.id))
    var gesehen = Set<String>()
    let neu = songIds.filter { !schon.contains($0) && gesehen.insert($0).inserted }
    for teil in neu.hlTeile(100) {
      try await mehrfach("updatePlaylist", ["playlistId": id], teil.map { ("songIdToAdd", $0) })
    }
    return neu
  }

  /// Songs hinzufügen; schon enthaltene werden übersprungen. Vor dem ersten Hinzufügen läuft die
  /// Erstübernahme, damit die Bibliothek nicht plötzlich nur diesen einen Song zeigt.
  func hinzufuegen(songIds: [String]) async throws {
    try await exklusiv { try await self.hinzufuegenJetzt(songIds) }
  }

  private func hinzufuegenJetzt(_ songIds: [String]) async throws {
    guard let account else { throw Fehler.keinKonto }
    try await uebernahmeWennNoetig(account, erzwingen: true)
    let id = try await anlegen()
    let neu = try await zufuegen(songIds, playlistId: id)
    await sofortMarkieren(neu, drin: true, account: account)
    HLListenFilter.neuBerechnet()
    zuletzt = Date()
    try await abgleichJetzt(erzwingen: true)
  }

  /// Songs entfernen (nur der Eintrag in der Mediathek, nie die Datei).
  func entfernen(songIds: [String]) async throws {
    try await exklusiv { try await self.entfernenJetzt(songIds) }
  }

  private func entfernenJetzt(_ songIds: [String]) async throws {
    guard let account else { throw Fehler.keinKonto }
    guard let p = try await playlistFinden(), let id = p["id"] as? String else { return }
    let weg = Set(songIds)
    let eintraege = try await eintraegeLaden(id)
    let anzahl = p["songCount"] as? Int ?? eintraege.count
    if anzahl == eintraege.count {
      let indizes = eintraege.enumerated().filter { weg.contains($0.element.id) }.map(\.offset)
      if !indizes.isEmpty {
        // ein Aufruf: Navidrome entfernt alle Indizes auf einmal (keine Verschiebung zwischen den Schritten)
        try await mehrfach("updatePlaylist", ["playlistId": id], indizes.map { ("songIndexToRemove", String($0)) })
      }
    } else if eintraege.contains(where: { weg.contains($0.id) }) {
      // getPlaylist verschweigt Einträge mit fehlender Datei, die Indizes stimmen dann nicht: Liste neu
      // schreiben (fehlende Dateien fallen dabei weg; Titel, Künstler, Dauer stehen in der Schattenliste).
      try await mehrfach("updatePlaylist", ["playlistId": id], (0 ..< anzahl).map { ("songIndexToRemove", String($0)) })
      let bleiben = eintraege.map(\.id).filter { !weg.contains($0) }
      var fehler: Error?
      for _ in 0 ..< 3 {
        do { try await zufuegen(bleiben, playlistId: id); fehler = nil; break } catch { fehler = error }
      }
      if let fehler { throw fehler }
    }
    await sofortMarkieren(songIds, drin: false, account: account)
    HLListenFilter.neuBerechnet()
    zuletzt = Date()
    try await abgleichJetzt(erzwingen: true)
  }

  /// Song-Markierung sofort setzen, damit die Oberfläche nicht auf den Abgleich warten muss.
  private func sofortMarkieren(_ ids: [String], drin: Bool, account: Account) async {
    guard !ids.isEmpty else { return }
    let accountId = account.managedObject.objectID
    try? await storage.async.perform { c in
      let konto = c.context.object(with: accountId) as! AccountMO
      let r = NSFetchRequest<SongMO>(entityName: "Song")
      r.predicate = NSPredicate(format: "account == %@ AND id IN %@", konto, ids)
      for s in (try? c.context.fetch(r)) ?? [] { s.hlInMediathek = drin }
    }
  }

  /// Subsonic-Aufruf mit mehrfach vorkommenden Parametern (songIdToAdd, songIndexToRemove).
  private func mehrfach(_ endpunkt: String, _ parameter: [String: String], _ wiederholt: [(String, String)]) async throws {
    guard var req = HLAPI.shared.subsonicAnfrage(endpunkt, parameter.merging(["f": "json"]) { $1 }),
          let url = req.url, var teile = URLComponents(url: url, resolvingAgainstBaseURL: false)
    else { throw Fehler.keinKonto }
    teile.queryItems = (teile.queryItems ?? []) + wiederholt.map { URLQueryItem(name: $0.0, value: $0.1) }
    req.url = teile.url
    let (daten, _) = try await URLSession.shared.data(for: req)
    guard let json = try? JSONSerialization.jsonObject(with: daten) as? [String: Any],
          let antwort = json["subsonic-response"] as? [String: Any], antwort["status"] as? String == "ok"
    else {
      let text = (((try? JSONSerialization.jsonObject(with: daten)) as? [String: Any])?["subsonic-response"]
        as? [String: Any])?["error"] as? [String: Any]
      throw Fehler.server(text?["message"] as? String ?? "Mediathek: Server hat abgelehnt.")
    }
  }
}

// MARK: - Erstübernahme

/// Einmal pro Person (auf dem Server vermerkt im Playlist-Kommentar): alles, was schon «ihr» ist, kommt in die
/// Mediathek – Favoriten (Songs und ganze Favoriten-Alben), Songs eigener Playlists (ohne Wochenmix und die
/// Mediathek selbst) und alle gelieferten Wünsche (Medienwunsch). Einmal pro Gerät dazu die heruntergeladenen
/// Songs. Nur hinzufügen, nie entfernen; nichts aus der Kinder-Bibliothek.
extension HLMediathek {
  struct Quellen: Sendable {
    var favoriten = [String]()
    var favoritenAlben = [String]()
    var playlists = [String]()
    var wuensche = [String]()
    var downloads = [String]()
    var wunschIds = [Int]()
    var album = [String: String]()          // Song-ID → Album-ID, soweit bekannt

    var alle: [String] { favoriten + favoritenAlben + playlists + downloads + wuensche }  // Wünsche zuletzt = «neu»
  }

  fileprivate var geraetSchluessel: String? { HLAPI.shared.account.map { "homelabmusic.mediathek.\($0.info.ident).geraet" } }

  /// Prüft, ob Erstübernahme (Server) bzw. Geräte-Übernahme fehlen, und holt sie nach.
  /// Nach einem Fehler höchstens stündlich neu, ausser `erzwingen` (Hinzufügen braucht sie zwingend).
  func uebernahmeWennNoetig(_ account: Account, erzwingen: Bool = false) async throws {
    #if DEBUG
      // Debug-Builds (Simulator, angemeldet mit echten Konten): nur mit -HLMediathekUebernahme YES, sonst würden
      // Tests Wünsche auf dem Server als übernommen markieren
      guard UserDefaults.standard.bool(forKey: "HLMediathekUebernahme") else { return }
    #endif
    let p = try await playlistFinden()
    let serverFertig = (p?["comment"] as? String)?.contains(Self.uebernahmeMarke) ?? false
    let geraetFertig = geraetSchluessel.map { UserDefaults.standard.bool(forKey: $0) } ?? true
    guard !serverFertig || !geraetFertig else { return }
    guard erzwingen || Date().timeIntervalSince(uebernahmeFehlschlag) > 3600 else { return }
    do {
      let q = try await quellenSammeln(account, server: !serverFertig, geraet: !geraetFertig)
      let ids = try await ohneKinder(q.alle, album: q.album, account: account)
      let id = try await anlegen()
      let neu = try await zufuegen(ids, playlistId: id)
      if !q.wunschIds.isEmpty { _ = try await HLAPI.shared.mediathekQuittieren(q.wunschIds) }
      if !serverFertig {
        let text = Self.kommentarText(uebernahme: true)
        guard await HLAPI.shared.subsonic("updatePlaylist", ["playlistId": id, "comment": text]) != nil
        else { throw Fehler.server("Mediathek konnte nicht beschriftet werden.") }
      }
      if let k = geraetSchluessel { UserDefaults.standard.set(true, forKey: k) }
      print("HLMediathek: Erstübernahme \(neu.count) Songs (Favoriten \(q.favoriten.count), Favoriten-Alben " +
        "\(q.favoritenAlben.count), Playlists \(q.playlists.count), Wünsche \(q.wuensche.count), Downloads \(q.downloads.count))")
      if !serverFertig, !neu.isEmpty {
        (UIApplication.shared.delegate as? AppDelegate)?.eventLogger.info(
          topic: "Mediathek",
          message: "Deine Mediathek ist eingerichtet: \(neu.count) Songs aus Favoriten, eigenen Playlists, Wünschen und Downloads. Mit «+» kommt Neues dazu."
        )
      }
    } catch {
      uebernahmeFehlschlag = Date()
      throw error
    }
  }

  /// Alles sammeln, ohne etwas zu schreiben (auch für den Probelauf).
  func quellenSammeln(_ account: Account, server: Bool, geraet: Bool, wuenscheNoetig: Bool = true) async throws -> Quellen {
    var q = Quellen()
    if server {
      // Favoriten
      guard let s = await HLAPI.shared.subsonic("getStarred2")?["starred2"] as? [String: Any]
      else { throw Fehler.server("Favoriten nicht lesbar.") }
      for e in s["song"] as? [[String: Any]] ?? [] { merken(e, in: &q.favoriten, &q.album) }
      for a in s["album"] as? [[String: Any]] ?? [] {
        guard let id = a["id"] as? String,
              let alb = await HLAPI.shared.subsonic("getAlbum", ["id": id])?["album"] as? [String: Any]
        else { throw Fehler.server("Favoriten-Album nicht lesbar.") }
        for e in alb["song"] as? [[String: Any]] ?? [] { merken(e, in: &q.favoritenAlben, &q.album) }
      }
      // eigene Playlists (ohne Wochenmix und Mediathek)
      guard let ich = HLAPI.shared.benutzername,
            let pl = (await HLAPI.shared.subsonic("getPlaylists")?["playlists"] as? [String: Any])?["playlist"]
            as? [[String: Any]] else { throw Fehler.server("Playlists nicht lesbar.") }
      for p in pl where (p["owner"] as? String) == ich {
        let kommentar = p["comment"] as? String ?? ""
        guard !kommentar.contains(Self.kennung), !kommentar.hasPrefix("Wochenmix"), let id = p["id"] as? String
        else { continue }
        guard let liste = await HLAPI.shared.subsonic("getPlaylist", ["id": id])?["playlist"] as? [String: Any]
        else { throw Fehler.server("Playlist nicht lesbar.") }
        for e in liste["entry"] as? [[String: Any]] ?? [] { merken(e, in: &q.playlists, &q.album) }
      }
      // Wünsche (Medienwunsch); ohne sie keine Erstübernahme
      do {
        let offen = try await HLAPI.shared.mediathekOffen().offen
        q.wuensche = offen.map(\.songId)
        q.wunschIds = offen.map(\.id)
      } catch {
        if wuenscheNoetig { throw error }
        print("HLMediathek: Wünsche nicht lesbar: \(error)")
      }
    }
    if geraet {
      let accountId = account.managedObject.objectID
      let geladen: [[String]] = try await storage.async.performAndGet { c in
        let konto = c.context.object(with: accountId) as! AccountMO
        let r = NSFetchRequest<SongMO>(entityName: "Song")
        r.predicate = NSPredicate(format: "account == %@ AND relFilePath != nil", konto)
        r.relationshipKeyPathsForPrefetching = ["album"]
        return ((try? c.context.fetch(r)) ?? []).map { [$0.id, $0.album?.id ?? ""] }
      }
      for paar in geladen {
        q.downloads.append(paar[0])
        if !paar[1].isEmpty { q.album[paar[0]] = paar[1] }
      }
    }
    return q
  }

  private func merken(_ e: [String: Any], in liste: inout [String], _ album: inout [String: String]) {
    guard let id = e["id"] as? String else { return }
    liste.append(id)
    if let a = e["albumId"] as? String { album[id] = a }
  }

  /// Songs aus der Kinder-Bibliothek und unbekannte IDs (z. B. ersetzter Wunsch) weglassen.
  func ohneKinder(_ ids: [String], album: [String: String], account: Account) async throws -> [String] {
    let kinder = Set(HLBibliothek.shared.bibliotheken.filter(\.istKinder).flatMap(\.alben))
    var albumVon = album
    let bibliothek = storage.main.library
    var ergebnis = [String]()
    var gesehen = Set<String>()
    for id in ids where gesehen.insert(id).inserted {
      if albumVon[id] == nil {
        if let s = bibliothek.getSong(for: account, id: id), !s.title.isEmpty, let a = s.album?.id {
          albumVon[id] = a
        } else if let s = await HLAPI.shared.subsonic("getSong", ["id": id])?["song"] as? [String: Any] {
          albumVon[id] = s["albumId"] as? String ?? ""
        } else {
          continue                                       // gibt es auf dem Server nicht (mehr)
        }
      }
      if let a = albumVon[id], kinder.contains(a) { continue }
      ergebnis.append(id)
    }
    return ergebnis
  }
}

extension Array {
  /// In Stücke zu höchstens n Elementen teilen.
  func hlTeile(_ n: Int) -> [[Element]] {
    stride(from: 0, to: count, by: n).map { Array(self[$0 ..< Swift.min($0 + n, count)]) }
  }
}
