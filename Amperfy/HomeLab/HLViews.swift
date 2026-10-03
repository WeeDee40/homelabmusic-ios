//
//  HLViews.swift
//  HomeLabMusic
//
//  Tab «Entdecken»: Läuft gerade, Suche, Künstler, Alben, Sender, Wünschen.
//  Vorbild ist die Web-Seite /app des Musikwunsch-Dienstes.
//
//  This program is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//

import SwiftUI
import UIKit

// MARK: - Navigation

enum HLZiel: Hashable {
  case suche(String)
  case kuenstler(Int)
  case album(Int)
  case sender(art: String, id: String)
}

struct HLEntdeckenView: View {
  @ObservedObject private var player = HLPlayer.shared
  @State private var pfad = NavigationPath()
  @State private var suchtext = ""

  var body: some View {
    NavigationStack(path: $pfad) {
      HLStartView()
        .navigationTitle("Entdecken")
        .searchable(text: $suchtext, prompt: "Künstler, Song oder Album")
        .onSubmit(of: .search) {
          let q = suchtext.trimmingCharacters(in: .whitespaces)
          if !q.isEmpty { pfad.append(HLZiel.suche(q)) }
        }
        .navigationDestination(for: HLZiel.self) { ziel in
          switch ziel {
          case let .suche(q): HLSucheView(q: q)
          case let .kuenstler(id): HLKuenstlerView(id: id)
          case let .album(id): HLAlbumView(id: id)
          case let .sender(art, id): HLSenderView(art: art, id: id)
          }
        }
    }
    .environment(\.hlOeffnen) { pfad.append($0) }
    .safeAreaInset(edge: .bottom) {
      if player.aktuell != nil { HLMiniPlayer { pfad.append($0) } }
    }
    .overlay(alignment: .bottom) {
      if let text = player.hinweis {
        Text(text)
          .font(.subheadline)
          .padding(.horizontal, 16).padding(.vertical, 10)
          .background(.thinMaterial, in: Capsule())
          .padding(.bottom, player.aktuell != nil ? 90 : 24)
          .transition(.opacity)
      }
    }
    .animation(.default, value: player.hinweis)
  }
}

private struct HLOeffnenKey: EnvironmentKey {
  static let defaultValue: @MainActor (HLZiel) -> () = { _ in }
}

extension EnvironmentValues {
  var hlOeffnen: @MainActor (HLZiel) -> () {
    get { self[HLOeffnenKey.self] }
    set { self[HLOeffnenKey.self] = newValue }
  }
}

// MARK: - Bausteine

/// Kapsel-Knopf. Wertet den Tipp selbst aus: in Listenzeilen lösen sonst alle Knöpfe einer Zeile gemeinsam aus.
struct HLKapsel: PrimitiveButtonStyle {
  var haupt = false

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .labelStyle(.titleAndIcon)
      .font(.subheadline.weight(.semibold))
      .lineLimit(1)
      .fixedSize()
      .padding(.horizontal, 14).padding(.vertical, 9)
      .foregroundStyle(haupt ? Color.white : Color.accentColor)
      .background(haupt ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(Color.secondary.opacity(0.15)), in: Capsule())
      .contentShape(Capsule())
      .onTapGesture { configuration.trigger() }   // eigener Tipp: Listenzeilen lösen sonst alle Knöpfe aus
  }
}

@MainActor
final class HLBildSpeicher {
  static let shared = HLBildSpeicher()
  private let cache = NSCache<NSURL, UIImage>()

  func bild(_ url: URL) async -> UIImage? {
    if let b = cache.object(forKey: url as NSURL) { return b }
    var req = URLRequest(url: url)
    for (k, v) in await HLAPI.shared.kopf(fuer: url) { req.setValue(v, forHTTPHeaderField: k) }
    guard let (daten, _) = try? await URLSession.shared.data(for: req), let b = UIImage(data: daten) else { return nil }
    cache.setObject(b, forKey: url as NSURL)
    return b
  }
}

struct HLBild: View {
  let pfad: String?
  var groesse: CGFloat = 48
  var rund = false
  @State private var bild: UIImage?

  var body: some View {
    ZStack {
      Color.secondary.opacity(0.15)
      if let bild { Image(uiImage: bild).resizable().scaledToFill() }
    }
    .frame(width: groesse, height: groesse)
    .clipShape(rund ? AnyShape(Circle()) : AnyShape(RoundedRectangle(cornerRadius: groesse / 7)))
    .task(id: pfad) {
      guard let url = HLAPI.shared.url(pfad) else { return }
      bild = await HLBildSpeicher.shared.bild(url)
    }
  }
}

struct HLStatusKnopf: View {
  let song: HLSong
  var kurz = false
  @ObservedObject private var player = HLPlayer.shared

  var body: some View {
    let status = player.status(song)
    Button {
      player.wuenschen(song)
    } label: {
      switch status {
      case "bibliothek":
        Image(systemName: "checkmark").foregroundStyle(.green)
          .frame(width: 34, height: 30).background(.green.opacity(0.14), in: Capsule())
      case "angefragt":
        Image(systemName: "hourglass").foregroundStyle(.orange)
          .frame(width: 34, height: 30).background(.orange.opacity(0.14), in: Capsule())
      default:
        Group {
          if kurz { Image(systemName: "plus") } else { Label("Wunsch", systemImage: "plus").font(.subheadline.weight(.semibold)) }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, kurz ? 0 : 12)
        .frame(minWidth: 34, minHeight: 30)
        .background(Color.accentColor, in: Capsule())
      }
    }
    .buttonStyle(.plain)
    .opacity(song.deezerId == nil && status != "bibliothek" ? 0 : 1)
  }
}

struct HLSongZeile: View {
  let songs: [HLSong]
  let i: Int
  var mitAlbum = true
  @ObservedObject private var player = HLPlayer.shared
  @Environment(\.hlOeffnen) private var oeffnen

  var body: some View {
    let s = songs[i]
    let spielt = player.aktuell?.schluessel == s.schluessel
    HStack(spacing: 12) {
      HLBild(pfad: s.bild)
        .onTapGesture { if let k = s.kuenstlerId { oeffnen(.kuenstler(k)) } }
      VStack(alignment: .leading, spacing: 2) {
        Text(s.titel ?? "").font(.body.weight(.semibold)).lineLimit(1)
          .foregroundStyle(spielt ? Color.accentColor : .primary)
        Text(([s.istVorschau ? "▶ 30 s" : nil, s.kuenstler, mitAlbum ? s.album : nil].compactMap { $0 })
          .joined(separator: " · "))
          .font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .contentShape(Rectangle())
      .onTapGesture { player.spielen(songs, ab: i) }
      HLStatusKnopf(song: s)
    }
    .opacity(s.istVorschau && s.vorschau == nil ? 0.45 : 1)
    .contextMenu {
      if let id = s.deezerId {
        Button("Sender ab diesem Song", systemImage: "dot.radiowaves.left.and.right") { oeffnen(.sender(art: "song", id: "\(id)")) }
      } else if let nd = s.navidromeId {
        Button("Sender ab diesem Song", systemImage: "dot.radiowaves.left.and.right") { oeffnen(.sender(art: "navidrome", id: nd)) }
      }
      if let k = s.kuenstlerId {
        Button("Künstler ansehen", systemImage: "person") { oeffnen(.kuenstler(k)) }
      }
      if let a = s.albumId {
        Button("Album ansehen", systemImage: "square.stack") { oeffnen(.album(a)) }
      }
    }
  }
}

struct HLKuenstlerBand: View {
  let liste: [HLKuenstler]
  @Environment(\.hlOeffnen) private var oeffnen

  var body: some View {
    ScrollView(.horizontal, showsIndicators: false) {
      HStack(alignment: .top, spacing: 14) {
        ForEach(liste, id: \.id) { a in
          Button { oeffnen(.kuenstler(a.id)) } label: {
            VStack(spacing: 4) {
              HLBild(pfad: a.bild, groesse: 96, rund: true)
              Text(a.name).font(.subheadline.weight(.semibold)).lineLimit(1)
              if let n = a.inBibliothek, n > 0 {
                Text("\(n) bei dir").font(.caption).foregroundStyle(.secondary)
              }
            }
            .frame(width: 104)
          }
          .buttonStyle(.plain)
        }
      }
      .padding(.vertical, 4)
    }
  }
}

struct HLAlbumGitter: View {
  let liste: [HLAlbum]
  @Environment(\.hlOeffnen) private var oeffnen

  var body: some View {
    LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 14)], spacing: 14) {
      ForEach(liste, id: \.id) { a in
        Button { oeffnen(.album(a.id)) } label: {
          VStack(alignment: .leading, spacing: 3) {
            GeometryReader { g in HLBild(pfad: a.bild, groesse: g.size.width) }
              .aspectRatio(1, contentMode: .fit)
            Text(a.titel ?? "").font(.subheadline.weight(.semibold)).lineLimit(1)
            Text([a.jahr, a.typText].compactMap { $0 }.joined(separator: " · "))
              .font(.caption).foregroundStyle(.secondary)
          }
        }
        .buttonStyle(.plain)
      }
    }
    .padding(.vertical, 4)
  }
}

/// Lädt Daten und zeigt Laden, Fehler oder Inhalt.
struct HLLaden<T: Sendable, Inhalt: View>: View {
  let laden: @MainActor () async throws -> T
  @ViewBuilder let inhalt: (T) -> Inhalt
  @State private var daten: T?
  @State private var fehler: String?

  var body: some View {
    Group {
      if let daten {
        inhalt(daten)
      } else if let fehler {
        ContentUnavailableView {
          Label("Nicht geladen", systemImage: "exclamationmark.triangle")
        } description: { Text(fehler) } actions: {
          Button("Nochmals") { Task { await holen() } }
        }
      } else {
        ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
      }
    }
    .task { if daten == nil { await holen() } }
  }

  private func holen() async {
    fehler = nil
    do { daten = try await laden() } catch { fehler = error.localizedDescription }
  }
}

// MARK: - Seiten

struct HLStartView: View {
  @State private var jetzt: HLJetzt?
  @State private var wuensche: [HLWunsch] = []
  @State private var geladen = false
  @State private var fehler: String?
  @State private var zuletzt = Date.distantPast
  @Environment(\.hlOeffnen) private var oeffnen

  var body: some View {
    List {
      if let j = jetzt {
        Section(j.quelle == "laeuft" ? "Läuft gerade" : "Zuletzt gehört") {
          HStack(spacing: 14) {
            HLBild(pfad: j.song.bild, groesse: 76)
            VStack(alignment: .leading, spacing: 3) {
              Text(j.song.titel ?? "").font(.headline).lineLimit(2)
              Text(j.song.kuenstler ?? "").foregroundStyle(.secondary).lineLimit(1)
            }
          }
          HStack {
            Button {
              if let id = j.song.navidromeId { oeffnen(.sender(art: "navidrome", id: id)) }
            } label: { Label("Sender starten", systemImage: "dot.radiowaves.left.and.right") }
              .buttonStyle(HLKapsel(haupt: true))
            if let k = j.song.kuenstlerId {
              Button("Künstler entdecken") { oeffnen(.kuenstler(k)) }.buttonStyle(HLKapsel())
            }
          }
          .listRowSeparator(.hidden)
        }
      }
      if !wuensche.isEmpty {
        Section("Deine letzten Wünsche") {
          let liste = Array(wuensche.prefix(10))
          let abspielbar = liste.filter(\.abspielbar)
          ForEach(liste, id: \.self) { w in
            HStack(spacing: 12) {
              if w.abspielbar { HLBild(pfad: w.alsSong.bild, groesse: 40) }
              VStack(alignment: .leading) {
                Text(w.titel).font(.body.weight(.semibold)).lineLimit(1)
                  .foregroundStyle(HLPlayer.shared.aktuell?.navidromeId == w.songId && w.songId != nil
                    ? Color.accentColor : .primary)
                Text(w.kuenstler).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
              }
              Spacer()
              if w.abspielbar {
                Image(systemName: "play.circle.fill").font(.title2).foregroundStyle(Color.accentColor)
              } else {
                Text(Self.statusText[w.status] ?? w.status).font(.footnote).foregroundStyle(.secondary)
              }
            }
            .contentShape(Rectangle())
            .onTapGesture {                              // gelieferte Wünsche ab hier der Reihe nach spielen
              guard w.abspielbar, let i = abspielbar.firstIndex(of: w) else { return }
              HLPlayer.shared.spielen(abspielbar.map(\.alsSong), ab: i)
            }
          }
        }
      }
      if let fehler {
        Section { Text(fehler).foregroundStyle(.secondary) }
      }
    }
    .overlay { if !geladen { ProgressView() } }
    .onAppear { neuLaden() }                       // beim Öffnen des Tabs und beim Zurückkehren
    .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
      neuLaden()                                     // App kommt wieder in den Vordergrund
    }
    .refreshable { await laden() }
  }

  static let statusText = ["angefragt": "⏳ kommt bald", "geliefert": "✓ da", "gefunden": "✓ hattest du",
                           "nicht_gefunden": "– nicht gefunden"]

  /// Neu laden, höchstens alle 3 Sekunden; der alte Inhalt bleibt bis dahin stehen.
  private func neuLaden() {
    guard Date().timeIntervalSince(zuletzt) > 3 else { return }
    zuletzt = Date()
    Task { await laden() }
  }

  private func laden() async {
    fehler = nil
    async let j = try? HLAPI.shared.jetzt()
    do { wuensche = try await HLAPI.shared.wuensche().wuensche } catch { fehler = error.localizedDescription }
    if let neu = await j { jetzt = neu }
    geladen = true
  }
}

struct HLSucheView: View {
  let q: String

  var body: some View {
    HLLaden(laden: { try await HLAPI.shared.suche(q) }) { d in
      List {
        if !d.kuenstler.isEmpty { Section("Künstler") { HLKuenstlerBand(liste: d.kuenstler) } }
        Section("Songs") {
          if d.songs.isEmpty { Text("Nichts gefunden.").foregroundStyle(.secondary) }
          ForEach(d.songs.indices, id: \.self) { HLSongZeile(songs: d.songs, i: $0) }
        }
        if !d.alben.isEmpty { Section("Alben") { HLAlbumGitter(liste: d.alben) } }
      }
    }
    .navigationTitle(q)
    .navigationBarTitleDisplayMode(.inline)
  }
}

struct HLKuenstlerView: View {
  let id: Int
  @Environment(\.hlOeffnen) private var oeffnen

  var body: some View {
    HLLaden(laden: { try await HLAPI.shared.kuenstler(id) }) { d in
      List {
        Section {
          HStack(spacing: 16) {
            HLBild(pfad: d.kuenstler.bildGross ?? d.kuenstler.bild, groesse: 120, rund: true)
            VStack(alignment: .leading, spacing: 4) {
              Text(d.kuenstler.name).font(.title2.bold())
              Text("\((d.kuenstler.fans ?? 0).formatted()) Fans · \(d.kuenstler.albenAnzahl ?? 0) Alben")
                .font(.subheadline).foregroundStyle(.secondary)
              Text(Self.bibliothekText(d.kuenstler.inBibliothek ?? 0))
                .font(.subheadline).foregroundStyle(.secondary)
            }
          }
          HStack {
            Button { HLPlayer.shared.spielen(d.top, ab: 0) } label: { Label("Reinhören", systemImage: "play.fill") }
              .buttonStyle(HLKapsel(haupt: true))
            Button { oeffnen(.sender(art: "kuenstler", id: "\(id)")) } label: {
              Label("Sender", systemImage: "dot.radiowaves.left.and.right")
            }
            .buttonStyle(HLKapsel())
          }
          .listRowSeparator(.hidden)
        }
        Section("Beliebte Songs") {
          ForEach(d.top.indices, id: \.self) { HLSongZeile(songs: d.top, i: $0) }
        }
        if !d.alben.isEmpty { Section("Alben und Singles") { HLAlbumGitter(liste: d.alben) } }
        if !d.aehnlich.isEmpty { Section("Ähnliche Künstler") { HLKuenstlerBand(liste: d.aehnlich) } }
      }
      .navigationTitle(d.kuenstler.name)
    }
    .navigationBarTitleDisplayMode(.inline)
  }

  static func bibliothekText(_ n: Int) -> String {
    n == 0 ? "Noch nichts in deiner Bibliothek" : "\(n) \(n == 1 ? "Song" : "Songs") in deiner Bibliothek"
  }
}

struct HLAlbumView: View {
  let id: Int
  @State private var gewuenscht = false
  @Environment(\.hlOeffnen) private var oeffnen

  var body: some View {
    HLLaden(laden: { try await HLAPI.shared.album(id) }) { d in
      let a = d.album
      let fehlt = (a.anzahl ?? 0) - (a.inBibliothek ?? 0)
      List {
        Section {
          HStack(alignment: .bottom, spacing: 16) {
            HLBild(pfad: a.bildGross ?? a.bild, groesse: 130)
            VStack(alignment: .leading, spacing: 4) {
              Text(a.titel ?? "").font(.title3.bold()).lineLimit(3)
              Button(a.kuenstler ?? "") { if let k = a.kuenstlerId { oeffnen(.kuenstler(k)) } }
                .buttonStyle(.plain).foregroundStyle(Color.accentColor)
              Text([a.jahr, "\(a.anzahl ?? 0) Songs", (a.inBibliothek ?? 0) > 0 ? "\(a.inBibliothek!) bei dir" : nil]
                .compactMap { $0 }.joined(separator: " · "))
                .font(.subheadline).foregroundStyle(.secondary)
            }
          }
          HStack {
            Button { HLPlayer.shared.spielen(d.songs, ab: 0) } label: { Label("Reinhören", systemImage: "play.fill") }
              .buttonStyle(HLKapsel(haupt: true))
            if fehlt > 0 {
              Button {
                gewuenscht = true
                Task {
                  do {
                    let r = try await HLAPI.shared.wunsch(album: id)
                    HLPlayer.shared.alsAngefragtMarkieren(d.songs)
                    HLPlayer.shared.zeigeHinweis(r.meldung ?? "Gewünscht.")
                  } catch {
                    gewuenscht = false
                    HLPlayer.shared.zeigeHinweis(error.localizedDescription)
                  }
                }
              } label: {
                Label(gewuenscht ? "Gewünscht" : "Album wünschen (\(fehlt))",
                      systemImage: gewuenscht ? "hourglass" : "plus")
              }
              .buttonStyle(HLKapsel())
              .disabled(gewuenscht)
            } else {
              Label("Komplett bei dir", systemImage: "checkmark").foregroundStyle(.green).font(.subheadline)
            }
          }
          .listRowSeparator(.hidden)
        }
        Section("Songs") {
          ForEach(d.songs.indices, id: \.self) { HLSongZeile(songs: d.songs, i: $0, mitAlbum: false) }
        }
      }
      .navigationTitle(a.titel ?? "Album")
    }
    .navigationBarTitleDisplayMode(.inline)
  }
}

struct HLSenderView: View {
  let art: String
  let id: String
  @State private var runde = 0

  var body: some View {
    HLLaden(laden: { try await HLAPI.shared.sender(art: art, id: id) }) { d in
      List {
        Section {
          Text("Neue Songs als 30-Sekunden-Vorschau, gemischt mit passenden Songs aus deiner Bibliothek.")
            .font(.subheadline).foregroundStyle(.secondary)
          HStack {
            Button { HLPlayer.shared.spielen(d.songs, ab: 0) } label: { Label("Abspielen", systemImage: "play.fill") }
              .buttonStyle(HLKapsel(haupt: true))
            Button { runde += 1 } label: { Label("Neu mischen", systemImage: "arrow.clockwise") }
              .buttonStyle(HLKapsel())
          }
          .listRowSeparator(.hidden)
        }
        Section("Songs") {
          ForEach(d.songs.indices, id: \.self) { HLSongZeile(songs: d.songs, i: $0) }
        }
      }
      .navigationTitle(d.sender.name)
      .onAppear { if HLPlayer.shared.aktuell == nil { HLPlayer.shared.spielen(d.songs, ab: 0) } }
    }
    .id(runde)
    .navigationBarTitleDisplayMode(.inline)
  }
}

// MARK: - Leiste zum laufenden Song (Abspielen/Weiter macht der Amperfy-Mini-Player darunter)

struct HLMiniPlayer: View {
  let oeffnen: (HLZiel) -> ()
  @ObservedObject private var player = HLPlayer.shared

  var body: some View {
    if let s = player.aktuell {
      VStack(spacing: 0) {
        GeometryReader { g in
          Rectangle().fill(Color.accentColor).frame(width: g.size.width * player.fortschritt)
        }
        .frame(height: 3)
        HStack(spacing: 10) {
          HLBild(pfad: s.bild, groesse: 44)
          VStack(alignment: .leading, spacing: 1) {
            Text(s.titel ?? "").font(.subheadline.weight(.semibold)).lineLimit(1)
            Text((s.istVorschau ? "Vorschau · " : "") + (s.kuenstler ?? ""))
              .font(.caption).foregroundStyle(.secondary).lineLimit(1)
          }
          .frame(maxWidth: .infinity, alignment: .leading)
          .contentShape(Rectangle())
          .onTapGesture { if let k = s.kuenstlerId { oeffnen(.kuenstler(k)) } }
          HLStatusKnopf(song: s, kurz: true)
          Button {
            if let id = s.deezerId { oeffnen(.sender(art: "song", id: "\(id)")) }
            else if let nd = s.navidromeId { oeffnen(.sender(art: "navidrome", id: nd)) }
          } label: { Image(systemName: "dot.radiowaves.left.and.right").frame(width: 36, height: 36) }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 12).padding(.vertical, 8)
      }
      .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
      .padding(.horizontal, 10).padding(.bottom, 6)
    }
  }
}
