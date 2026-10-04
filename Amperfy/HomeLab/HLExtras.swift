//
//  HLExtras.swift
//  HomeLabMusic
//
//  «Klingt ähnlich» (AudioMuse), Liste der abgelehnten Songs, Benachrichtigung «Dein Wunsch ist da» und die
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

// MARK: - Klingt ähnlich

/// Inhalt «Klingt ähnlich» (im Entdecken-Tab als Seite, aus Amperfys Menü als Blatt).
struct HLAehnlichInhalt: View {
  let navidromeId: String
  var nachAbspielen: () -> () = {}

  var body: some View {
    HLLaden(laden: { try await HLAPI.shared.aehnlich(navidromeId: navidromeId) }) { d in
      List {
        Section {
          HStack(spacing: 14) {
            HLBild(pfad: d.seed.bild, groesse: 64)
            VStack(alignment: .leading, spacing: 3) {
              Text(d.seed.titel ?? "").font(.headline).lineLimit(2)
              Text(d.seed.kuenstler ?? "").foregroundStyle(.secondary).lineLimit(1)
            }
          }
          Button { HLPlayer.shared.spielen([d.seed] + d.songs, ab: 0); nachAbspielen() } label: {
            Label("Alle abspielen", systemImage: "play.fill")
          }
          .buttonStyle(HLKapsel(haupt: true))
          .listRowSeparator(.hidden)
        }
        Section("Klingt ähnlich, aus deiner Bibliothek") {
          if d.songs.isEmpty { Text("Nichts Ähnliches gefunden.").foregroundStyle(.secondary) }
          ForEach(d.songs.indices, id: \.self) { HLSongZeile(songs: d.songs, i: $0) }
        }
      }
    }
    .navigationTitle("Klingt ähnlich")
    .navigationBarTitleDisplayMode(.inline)
  }
}

struct HLAehnlichView: View {
  let navidromeId: String
  @Environment(\.dismiss) private var schliessen

  var body: some View {
    NavigationStack {
      HLAehnlichInhalt(navidromeId: navidromeId) { schliessen() }
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Fertig") { schliessen() } } }
    }
  }
}

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
          Text("Diese Songs kommen nicht mehr in Vorschlägen, Sendern und im Wochenmix. Nach drei abgelehnten Songs eines Künstlers wird der ganze Künstler nicht mehr vorgeschlagen. Nach links wischen hebt das auf.")
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
  /// Zusätzliche Menüeinträge für einen Bibliotheks-Song (eingebunden in EntityPreviewActionBuilder).
  static func aktionen(fuer container: PlayableContainable, auf ansicht: UIViewController) -> [UIMenuElement] {
    guard let song = (container as? AbstractPlayable)?.asSong, HLAPI.shared.account != nil else { return [] }
    let id = song.id, titel = song.title, kuenstler = song.creatorName
    let aehnlich = UIAction(title: "Klingt ähnlich", image: UIImage(systemName: "waveform.path.ecg")) { _ in
      ansicht.present(UIHostingController(rootView: HLAehnlichView(navidromeId: id)), animated: true)
    }
    let ablehnen = UIAction(title: "Nicht mein Ding", image: UIImage(systemName: "hand.thumbsdown"),
                            attributes: .destructive) { _ in
      HLPlayer.shared.ablehnen(HLSong(typ: "bibliothek", status: "bibliothek", deezerId: nil, titel: titel,
                                      kuenstler: kuenstler, kuenstlerId: nil, album: nil, albumId: nil, bild: nil,
                                      bildGross: nil, dauer: nil, vorschau: nil, navidromeId: id, navidromeCover: nil))
    }
    return [UIMenu(title: "HomeLabMusic", options: .displayInline, children: [aehnlich, ablehnen])]
  }
}
