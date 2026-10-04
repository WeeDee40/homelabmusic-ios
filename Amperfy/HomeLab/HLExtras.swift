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
  /// Unser «Mix ab diesem Song» ersetzt Amperfys «Instant Mix» (der bleibt als Ersatz bei Ausfall).
  static var ersetztInstantMix: Bool { HLAPI.shared.account != nil }

  /// Zusätzliche Menüeinträge für einen Bibliotheks-Song (eingebunden in EntityPreviewActionBuilder).
  static func aktionen(fuer container: PlayableContainable, auf ansicht: UIViewController) -> [UIMenuElement] {
    guard let song = (container as? AbstractPlayable)?.asSong, HLAPI.shared.account != nil else { return [] }
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
    return [UIMenu(title: "HomeLabMusic", options: .displayInline, children: [mix, ablehnen])]
  }
}
