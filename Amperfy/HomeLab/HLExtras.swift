//
//  HLExtras.swift
//  HomeLabMusic
//
//  Liste der abgelehnten Songs, Benachrichtigung «Dein Wunsch ist da» und die
//  Einträge, die HomeLabMusic in Amperfys Song-Menü hängt (siehe EntityPreviewActionBuilder).
//
//  This program is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//

import AmperfyKit
import CoreData
import SwiftUI
import UIKit
import UserNotifications

// MARK: - Abgelehnte Songs und Künstler

struct HLAbgelehntView: View {
  @State private var eintraege: [HLAbgelehnt] = []
  @State private var geladen = false
  @Environment(\.dismiss) private var schliessen

  var body: some View {
    NavigationStack {
      List {
        Section {
          if geladen, eintraege.isEmpty { Text("Noch nichts abgelehnt.").foregroundStyle(.secondary) }
          ForEach(eintraege, id: \.self) { e in
            Label(e.anzeige, systemImage: e.art == "kuenstler" ? "person.slash" : "hand.thumbsdown")
              .swipeActions {
                Button("Wieder erlauben") { Task { await aufheben(e) } }.tint(.green)
              }
          }
        } footer: {
          Text("Diese Songs kommen nicht mehr in Vorschlägen, Mixen und im Wochenmix. Nach drei abgelehnten Songs eines Künstlers wird der ganze Künstler nicht mehr vorgeschlagen. Nach links wischen hebt das auf.")
        }
      }
      .navigationTitle("Nicht mein Ding")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Fertig") { schliessen() } } }
      .task { await laden() }
    }
  }

  private func laden() async {
    eintraege = (try? await HLAPI.shared.abgelehnt().eintraege) ?? []
    geladen = true
  }

  private func aufheben(_ e: HLAbgelehnt) async {
    _ = try? await HLAPI.shared.aufheben(e)
    await laden()
  }
}

// MARK: - «Dein Wunsch ist da»

@MainActor
enum HLBenachrichtigung {
  private static let gemeldetKey = "homelabmusic.gemeldeteWuensche"
  private static var takt: Timer?

  /// Beim Start: alle 2 Minuten und beim Zurückkehren in die App nachsehen.
  static func starten() {
    guard takt == nil else { return }
    takt = Timer.scheduledTimer(withTimeInterval: 120, repeats: true) { _ in
      MainActor.assumeIsolated { Task { await pruefen() } }
    }
    NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil,
                                           queue: .main) { _ in
      MainActor.assumeIsolated { Task { await pruefen() } }
    }
    Task { await pruefen() }
  }

  /// Gelieferte Wünsche, die noch nicht gemeldet wurden, als Mitteilung zeigen (auch aus der Hintergrundaufgabe).
  static func pruefen() async {
    HLAPI.shared.kontoSicherstellen()
    guard let liste = try? await HLAPI.shared.wuensche().wuensche else { return }
    let geliefert = liste.filter { $0.status == "geliefert" && $0.songId != nil && $0.id != nil }
    let ids = Set(geliefert.compactMap { $0.id })
    guard let bisher = UserDefaults.standard.array(forKey: gemeldetKey) as? [Int] else {
      UserDefaults.standard.set(Array(ids), forKey: gemeldetKey)     // erster Lauf: nichts nachmelden
      return
    }
    let neu = geliefert.filter { !Set(bisher).contains($0.id!) }
    guard !neu.isEmpty else { return }
    UserDefaults.standard.set(Array(Array(Set(bisher).union(ids)).sorted().suffix(200)), forKey: gemeldetKey)
    let zentrale = UNUserNotificationCenter.current()
    _ = try? await zentrale.requestAuthorization(options: [.alert, .sound, .badge])
    for w in neu {
      let inhalt = UNMutableNotificationContent()
      inhalt.title = "Dein Wunsch ist da"
      inhalt.body = "\(w.titel) – \(w.kuenstler)"
      inhalt.sound = .default
      inhalt.userInfo = ["hl_song_id": w.songId!, "hl_titel": w.titel, "hl_kuenstler": w.kuenstler]
      try? await zentrale.add(UNNotificationRequest(identifier: "hl-wunsch-\(w.id!)", content: inhalt, trigger: nil))
    }
  }

  /// Antippen der Mitteilung: Song abspielen. true, wenn es unsere Mitteilung war.
  static func behandeln(_ userInfo: [AnyHashable: Any]) -> Bool {
    guard let id = userInfo["hl_song_id"] as? String else { return false }
    HLAPI.shared.kontoSicherstellen()
    let song = HLSong(typ: "bibliothek", status: "bibliothek", deezerId: nil, titel: userInfo["hl_titel"] as? String,
                      kuenstler: userInfo["hl_kuenstler"] as? String, kuenstlerId: nil, album: nil, albumId: nil,
                      bild: "/entdecken/cover/mf-\(id)", bildGross: nil, dauer: nil, vorschau: nil,
                      navidromeId: id, navidromeCover: nil)
    HLPlayer.shared.spielen([song], ab: 0)
    return true
  }
}

// MARK: - Einträge in Amperfys Song-Menü

@MainActor
enum HLMenue {
  /// Menü für eine laufende Vorschau (im Amperfy-Player als Radio).
  private static func vorschauAktionen(_ s: HLSong) -> [UIMenuElement] {
    var aktionen = [UIMenuElement]()
    switch HLPlayer.shared.status(s) {
    case "neu":
      aktionen.append(UIAction(title: HLMediathekUI.wunschText, image: UIImage(systemName: "plus.circle")) { _ in
        HLPlayer.shared.wuenschen(s)
      })
    case "angefragt":
      aktionen.append(UIAction(title: "Hinzugefügt, kommt bald", image: UIImage(systemName: "hourglass"),
                               attributes: .disabled) { _ in })
    default:
      break
    }
    if let id = s.deezerId {
      aktionen.append(UIMenu(title: "Mix ab diesem Song", image: UIImage(systemName: "dot.radiowaves.left.and.right"),
                             children: HLMix.Stufe.allCases.map { stufe in
        UIAction(title: stufe.menuTitel, state: stufe == HLMix.shared.stufe ? .on : .off) { _ in
          HLMix.shared.starten(art: "song", id: "\(id)", stufe: stufe)
        }
      }))
    }
    aktionen.append(UIAction(title: "Nicht mein Ding", image: UIImage(systemName: "hand.thumbsdown"),
                             attributes: .destructive) { _ in HLPlayer.shared.ablehnen(s) })
    return [UIMenu(title: "Vorschau · \(s.kuenstler ?? "")", options: .displayInline, children: aktionen)]
  }

  /// Unser «Mix ab diesem Song» ersetzt Amperfys «Instant Mix» (der bleibt als Ersatz bei Ausfall).
  static var ersetztInstantMix: Bool { HLAPI.shared.account != nil }

  /// Zusätzliche Menüeinträge für einen Bibliotheks-Song (eingebunden in EntityPreviewActionBuilder).
  static func aktionen(fuer container: PlayableContainable, auf ansicht: UIViewController) -> [UIMenuElement] {
    if let vorschau = HLPlayer.shared.vorschau(container as? AbstractPlayable) { return vorschauAktionen(vorschau) }
    let mediathek = HLMediathekUI.menue(fuer: container)
    guard let song = (container as? AbstractPlayable)?.asSong, HLAPI.shared.account != nil else {
      return mediathek.isEmpty ? [] : [UIMenu(title: "HomeLabMusic", options: .displayInline, children: mediathek)]
    }
    let id = song.id, titel = song.title, kuenstler = song.creatorName
    let mix = UIMenu(title: "Mix ab diesem Song", image: UIImage(systemName: "dot.radiowaves.left.and.right"),
                     children: HLMix.Stufe.allCases.map { stufe in
      UIAction(title: stufe.menuTitel, state: stufe == HLMix.shared.stufe ? .on : .off) { _ in
        HLMix.shared.starten(art: "navidrome", id: id, stufe: stufe)
      }
    })
    let ablehnen = UIAction(title: "Nicht mein Ding", image: UIImage(systemName: "hand.thumbsdown"),
                            attributes: .destructive) { _ in
      HLPlayer.shared.ablehnen(HLSong(typ: "bibliothek", status: "bibliothek", deezerId: nil, titel: titel,
                                      kuenstler: kuenstler, kuenstlerId: nil, album: nil, albumId: nil, bild: nil,
                                      bildGross: nil, dauer: nil, vorschau: nil, navidromeId: id, navidromeCover: nil))
    }
    return [UIMenu(title: "HomeLabMusic", options: .displayInline, children: mediathek + [mix, ablehnen])]
  }
}

// MARK: - Doppelte Einträge (Etappe K)

/// Amperfy legte bei gleichzeitigen Album-Abgleichen Alben, Songs und Künstler doppelt an (Upstream #809, seit
/// a3011f7b behoben). Die alten Doppel bleiben in der Datenbank auf dem Gerät: leere Albumkopien, Songs ohne
/// Album (auf der Albumseite fehlt dann die Zeile). Einmal pro Konto zusammenlegen: Je Navidrome-ID bleibt der
/// Eintrag mit dem meisten Inhalt; Playlist-Einträge, Download, Scrobbles, Suchverlauf, Songs und Alben wandern
/// zu ihm, die Kopien werden gelöscht. Bilder werden vorher gelöst (sie gehören oft beiden). Gilt für alle Konten
/// auf dem Gerät (iPad und Mac haben oft mehrere).
@MainActor
enum HLDoppelte {
  private static let erledigt = "homelabmusic.doppelteZusammengelegt.v2"

  static func zusammenlegen() {
    guard !UserDefaults.standard.bool(forKey: erledigt) else { return }
    Task {
      do {
        let zahl = try await AmperKit.shared.storage.async.performAndGet { c in
          let konten = (try? c.context.fetch(NSFetchRequest<NSManagedObject>(entityName: "Account"))) ?? []
          var summe: [Int] = [0, 0, 0]
          for konto in konten {
            let z: [Int] = Self.arbeit(c.context, konto: konto.objectID)
            for i in 0 ..< 3 { summe[i] += z[i] }
          }
          return summe
        }
        UserDefaults.standard.set(true, forKey: erledigt)
        (UIApplication.shared.delegate as! AppDelegate).eventLogger.debug(topic: "Doppelte", message:
          "Zusammengelegt: \(zahl[0]) Songs, \(zahl[1]) Alben, \(zahl[2]) Künstler")
        if zahl.contains(where: { $0 > 0 }) { HLMediathek.shared.abgleichen(erzwingen: true) }
      } catch {
        (UIApplication.shared.delegate as! AppDelegate).eventLogger.debug(topic: "Doppelte", message: error.localizedDescription)
      }
    }
  }

  /// Anzahl entfernter Kopien: [Songs, Alben, Künstler].
  nonisolated private static func arbeit(_ ctx: NSManagedObjectContext, konto: NSManagedObjectID) -> [Int] {
    let account = ctx.object(with: konto)
    func gruppen(_ entitaet: String) -> [[NSManagedObject]] {
      let r = NSFetchRequest<NSManagedObject>(entityName: entitaet)
      r.predicate = NSPredicate(format: "account == %@", account)
      r.propertiesToFetch = ["id"]
      var nachId = [String: [NSManagedObject]]()
      for o in (try? ctx.fetch(r)) ?? [] {
        guard let id = o.value(forKey: "id") as? String, !id.isEmpty else { continue }
        nachId[id, default: []].append(o)
      }
      return nachId.values.filter { $0.count > 1 }
    }
    /// Inhalt einer Zu-vielen-Beziehung; manche sind geordnet (NSOrderedSet), dann liefert «as? Set» nichts.
    func menge(_ o: NSManagedObject, _ k: String) -> [NSManagedObject] {
      switch o.value(forKey: k) {
      case let m as NSOrderedSet: return m.array.compactMap { $0 as? NSManagedObject }
      case let m as NSSet: return m.allObjects.compactMap { $0 as? NSManagedObject }
      default: return []
      }
    }
    func umhaengen(_ von: NSManagedObject, _ nach: NSManagedObject, _ beziehung: String, _ rueck: String) {
      for x in menge(von, beziehung) { x.setValue(nach, forKey: rueck) }
    }
    /// Gemeinsames aller Einträge: Suchverlauf mitnehmen, Bild lösen, Kopie löschen. Vor dem Löschen müssen die
    /// Rückbeziehungen verbucht sein (processPendingChanges): sonst sieht die Löschregel die umgehängten Songs,
    /// Playlist-Einträge und Downloads noch bei der Kopie und nimmt ihnen das Album bzw. löscht sie mit.
    func loeschen(_ kopie: NSManagedObject, behalten: NSManagedObject) -> Bool {
      umhaengen(kopie, behalten, "searchHistory", "searchedLibraryEntity")
      if behalten.value(forKey: "artwork") == nil { behalten.setValue(kopie.value(forKey: "artwork"), forKey: "artwork") }
      kopie.setValue(nil, forKey: "artwork")
      ctx.processPendingChanges()
      for k in ["songs", "albums", "playlistItems", "scrobbleEntries", "searchHistory"]
      where kopie.entity.relationshipsByName[k] != nil && !menge(kopie, k).isEmpty {
        return false                                  // hängt noch etwas daran: lieber stehen lassen
      }
      if kopie.entity.relationshipsByName["download"] != nil, let d = kopie.value(forKey: "download") as? NSManagedObject,
         d.value(forKey: "playable") as? NSManagedObject == behalten {
        return false
      }
      ctx.delete(kopie)
      return true
    }

    var zahl = [0, 0, 0]
    // Songs: der mit Album, Download, Mediathek, Playlist-Einträgen bleibt
    for g in gruppen("Song") {
      func wert(_ s: NSManagedObject) -> Int {
        (s.value(forKey: "album") != nil ? 8 : 0) + (s.value(forKey: "download") != nil ? 4 : 0)
          + ((s.value(forKey: "hlInMediathek") as? Bool) == true ? 2 : 0) + (menge(s, "playlistItems").isEmpty ? 0 : 1)
      }
      let behalten = g.max { wert($0) < wert($1) }!
      for kopie in g where kopie != behalten {
        umhaengen(kopie, behalten, "playlistItems", "playable")
        umhaengen(kopie, behalten, "scrobbleEntries", "playable")
        if behalten.value(forKey: "download") == nil, let d = kopie.value(forKey: "download") as? NSManagedObject {
          d.setValue(behalten, forKey: "playable")
        }
        if (kopie.value(forKey: "hlInMediathek") as? Bool) == true { behalten.setValue(true, forKey: "hlInMediathek") }
        for k in ["album", "artist", "genre"] where behalten.value(forKey: k) == nil {
          behalten.setValue(kopie.value(forKey: k), forKey: k)
        }
        if loeschen(kopie, behalten: behalten) { zahl[0] += 1 }
      }
    }
    // Alben: das mit den meisten Songs bleibt
    for g in gruppen("Album") {
      let behalten = g.max { menge($0, "songs").count < menge($1, "songs").count }!
      for kopie in g where kopie != behalten {
        umhaengen(kopie, behalten, "songs", "album")
        if behalten.value(forKey: "hlMediathekSeit") == nil {
          behalten.setValue(kopie.value(forKey: "hlMediathekSeit"), forKey: "hlMediathekSeit")
        }
        for k in ["artist", "genre"] where behalten.value(forKey: k) == nil {
          behalten.setValue(kopie.value(forKey: k), forKey: k)
        }
        if loeschen(kopie, behalten: behalten) { zahl[1] += 1 }
      }
    }
    // Künstler: der mit den meisten Alben und Songs bleibt
    for g in gruppen("Artist") {
      func wert(_ k: NSManagedObject) -> Int { menge(k, "albums").count + menge(k, "songs").count }
      let behalten = g.max { wert($0) < wert($1) }!
      for kopie in g where kopie != behalten {
        umhaengen(kopie, behalten, "albums", "artist")
        umhaengen(kopie, behalten, "songs", "artist")
        if (kopie.value(forKey: "hlInMediathek") as? Bool) == true { behalten.setValue(true, forKey: "hlInMediathek") }
        if loeschen(kopie, behalten: behalten) { zahl[2] += 1 }
      }
    }
    return zahl
  }
}
