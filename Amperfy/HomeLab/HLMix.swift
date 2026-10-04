//
//  HLMix.swift
//  HomeLabMusic
//
//  «Mix ab diesem Song»: endloser Mix nach Klang (AudioMuse), mit regelbarem Anteil neuer Songs und Lernen im
//  laufenden Mix (ganz gehört, Stern, Wunsch -> hin; früh übersprungen, «Nicht mein Ding» -> weg). Der Server
//  rechnet zustandslos: die App schickt bei jedem Nachladen die bisherigen Songs und Reaktionen mit.
//  Antwortet der Musikwunsch-Dienst nicht, spielt Navidromes Instant Mix (nur Bibliothek).
//
//  This program is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//

import AmperfyKit
import SwiftUI
import UIKit

@MainActor
final class HLMix: ObservableObject {
  static let shared = HLMix()
  static let praefix = "Mix ab "
  private static let stufeKey = "homelabmusic.mixNeu"

  enum Stufe: String, CaseIterable, Identifiable {
    case aus, etwas, viel
    var id: String { rawValue }
    var anteil: Double { switch self { case .aus: 0; case .etwas: 0.25; case .viel: 0.6 } }
    var titel: String { switch self { case .aus: "Aus"; case .etwas: "Etwas"; case .viel: "Viel" } }
    var menuTitel: String {
      switch self { case .aus: "Nur Bibliothek"; case .etwas: "Etwas Neues"; case .viel: "Viel Neues" }
    }
  }

  @Published var stufe: Stufe {
    didSet { UserDefaults.standard.set(stufe.rawValue, forKey: Self.stufeKey) }
  }
  @Published private(set) var name = ""
  @Published private(set) var liste: [HLSong] = []
  @Published private(set) var aktiv = false
  @Published private(set) var laedt = false
  @Published private(set) var fehler: String?

  private(set) var seed: [String: String] = [:]
  private var kontext = ""
  private var signale: [[String: String]] = []
  private var bewertet = Set<String>()

  private init() {
    stufe = Stufe(rawValue: UserDefaults.standard.string(forKey: Self.stufeKey) ?? "") ?? .etwas
  }

  /// Mix starten. art: "navidrome" (Bibliotheks-Song), "song" (Deezer-Song) oder "kuenstler" (Deezer-Künstler).
  func starten(art: String, id: String, stufe neueStufe: Stufe? = nil) {
    if let neueStufe { stufe = neueStufe }
    seed = ["art": art, "id": id]
    signale = []
    bewertet = []
    liste = []
    fehler = nil
    laedt = true
    Task {
      defer { laedt = false }
      do {
        let r = try await HLAPI.shared.mix(seed: seed, neu: stufe.anteil, gespielt: [], signale: [])
        let songs = (r.start.map { [$0] } ?? []) + r.songs
        guard !songs.isEmpty else { throw HLAPIFehler.server("Kein Mix möglich.") }
        name = r.name
        kontext = r.name.hasPrefix(Self.praefix) ? r.name : Self.praefix + r.name
        liste = songs
        aktiv = true
        HLPlayer.shared.spielen(songs, ab: 0, kontext: kontext)
      } catch {
        aktiv = false
        if art == "navidrome", await ersatzMix(navidromeId: id) { return }
        fehler = error.localizedDescription
        HLPlayer.shared.zeigeHinweis("Mix nicht möglich: \(error.localizedDescription)")
      }
    }
  }

  /// Reaktion auf einen Song dieses Mixes merken (wirkt beim nächsten Nachladen).
  func signal(_ song: HLSong, art: String) {
    guard aktiv, liste.contains(where: { $0.schluessel == song.schluessel }) else { return }
    let key = "\(song.schluessel)|\(art)"
    guard !bewertet.contains(key) else { return }
    bewertet.insert(key)
    var s = ["art": art, "kuenstler": song.kuenstler ?? ""]
    if let n = song.navidromeId { s["navidrome_id"] = n }
    if let d = song.deezerId { s["deezer_id"] = "\(d)" }
    signale.append(s)
  }

  /// Vom Player-Takt: endet der Mix bald, nachladen; spielt etwas anderes, Mix beenden.
  func pruefen() {
    guard aktiv else { return }
    guard HLPlayer.shared.amperfyKontext == kontext else {
      aktiv = false
      return
    }
    if !laedt, HLPlayer.shared.naechsteAnzahl < 5 { nachladen() }
  }

  private func nachladen() {
    laedt = true
    let gespielt = liste.map { $0.navidromeId ?? "\($0.deezerId ?? 0)" }
    Task {
      defer { laedt = false }
      guard let r = try? await HLAPI.shared.mix(seed: seed, neu: stufe.anteil, gespielt: gespielt, signale: signale),
            !r.songs.isEmpty, aktiv else { return }
      liste += r.songs
      HLPlayer.shared.anhaengen(r.songs)
    }
  }

  /// Ersatz, wenn der Musikwunsch-Dienst nicht antwortet: Navidromes Instant Mix (nur Bibliothek).
  private func ersatzMix(navidromeId: String) async -> Bool {
    guard let account = HLAPI.shared.account,
          let song = AmperKit.shared.storage.main.library.getSong(for: account, id: navidromeId),
          let aehnlich = try? await (UIApplication.shared.delegate as! AppDelegate).getMeta(account.info)
            .librarySyncer.requestSimilarSongs(song: song, count: 99), !aehnlich.isEmpty else { return false }
    HLPlayer.shared.spielenAmperfy([song] + aehnlich, kontext: "Instant Mix")
    HLPlayer.shared.zeigeHinweis("Musikwunsch nicht erreichbar – Instant Mix aus der Bibliothek.")
    return true
  }
}

// MARK: - Mix-Seite im Entdecken-Tab

struct HLMixView: View {
  let art: String
  let id: String
  @ObservedObject private var mix = HLMix.shared
  @ObservedObject private var player = HLPlayer.shared

  var body: some View {
    List {
      Section {
        Picker("Neues", selection: Binding(get: { mix.stufe }, set: { neu in
          mix.stufe = neu
          mix.starten(art: art, id: id)
        })) {
          ForEach(HLMix.Stufe.allCases) { Text($0.titel).tag($0) }
        }
        .pickerStyle(.segmented)
        Text(erklaerung).font(.footnote).foregroundStyle(.secondary)
        Button { mix.starten(art: art, id: id) } label: { Label("Neu mischen", systemImage: "arrow.clockwise") }
          .buttonStyle(HLKapsel())
          .listRowSeparator(.hidden)
      } header: {
        Text("Neues im Mix")
      }
      Section {
        if mix.liste.isEmpty {
          if mix.laedt { ProgressView().frame(maxWidth: .infinity) }
          if let f = mix.fehler { Text(f).foregroundStyle(.secondary) }
        }
        ForEach(mix.liste.indices, id: \.self) { HLSongZeile(songs: mix.liste, i: $0) }
        if mix.laedt, !mix.liste.isEmpty { ProgressView().frame(maxWidth: .infinity) }
      } header: {
        Text(mix.aktiv ? "Läuft endlos weiter" : "Songs")
      } footer: {
        Text("Der Mix lernt mit: ganz gehörte Songs, Sterne und Wünsche ziehen ihn hin, früh übersprungene und «Nicht mein Ding» weg.")
      }
    }
    .navigationTitle(mix.name.isEmpty ? "Mix" : mix.name)
    .navigationBarTitleDisplayMode(.inline)
    .onAppear {
      if mix.seed != ["art": art, "id": id] || !mix.aktiv { mix.starten(art: art, id: id) }
    }
  }

  private var erklaerung: String {
    switch mix.stufe {
    case .aus: "Nur Songs aus deiner Bibliothek, nach Klang."
    case .etwas: "Vor allem Bekanntes, ab und zu ein neuer Song als 30-Sekunden-Vorschau."
    case .viel: "Viele neue Songs zum Entdecken, gemischt mit passenden aus deiner Bibliothek."
    }
  }
}
