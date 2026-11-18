//
//  HLViews.swift
//  HomeLabMusic
//
//  Tab «Entdecken»: Läuft gerade, Künstler, Alben, Mix, Wünschen. Die Suche steckt in Amperfys Suche (HLSuche.swift).
//  Vorbild ist die Web-Seite /app des Medienwunsch-Dienstes.
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
  case kuenstler(Int)
  case album(Int)
  case playlist(Int)                                   // öffentliche Deezer-Playlist (Suche)
  case sender(art: String, id: String)
  case bibliothek(kuenstler: String)                   // Amperfys Künstlerseite der Bibliothek
  case stoebern(titel: String, suche: String)          // Kachel der leeren Suche
}

/// Navigationsstapel des Tabs «Entdecken»; geteilt, damit auch der Mini-Player dort Seiten öffnen kann.
@MainActor
final class HLNavigation: ObservableObject {
  static let shared = HLNavigation()
  @Published var pfad = NavigationPath()

  /// Amperfys Seiten sind UIKit: die öffnet Amperfy im Tab «Library», alles andere kommt auf den eigenen Stapel.
  func oeffnen(_ ziel: HLZiel) {
    if case let .bibliothek(name) = ziel { HLTab.bibliothekOeffnen(kuenstler: name) } else { pfad.append(ziel) }
  }
}

struct HLEntdeckenView: View {
  @ObservedObject private var navigation = HLNavigation.shared
  @State private var shazamOffen = false
  @State private var abgelehntOffen = false

  var body: some View {
    NavigationStack(path: $navigation.pfad) {
      HLStartView()
        .navigationTitle("Entdecken")
        .toolbar {
          ToolbarItem(placement: .topBarTrailing) {
            Button { shazamOffen = true } label: { Image(systemName: "shazam.logo") }
              .accessibilityLabel("Song erkennen")
          }
          ToolbarItem(placement: .topBarTrailing) {
            Menu {
              Button("Nicht mein Ding …", systemImage: "hand.thumbsdown") { abgelehntOffen = true }
            } label: { Image(systemName: "ellipsis") }
          }
        }
        .sheet(isPresented: $abgelehntOffen) { HLAbgelehntView() }
        .sheet(isPresented: $shazamOffen) {
          HLShazamView { ziel in navigation.oeffnen(ziel) }
        }
        .navigationDestination(for: HLZiel.self) { HLZielView(ziel: $0) }
    }
    .environment(\.hlOeffnen) { navigation.oeffnen($0) }
    .modifier(HLSpielRahmen())
  }
}

struct HLZielView: View {
  let ziel: HLZiel

  var body: some View {
    switch ziel {
    case let .kuenstler(id): HLKuenstlerView(id: id)
    case let .album(id): HLAlbumView(id: id)
    case let .playlist(id): HLPlaylistView(id: id)
    case let .sender(art, id): HLMixView(art: art, id: id)
    case .bibliothek: EmptyView()                      // läuft über HLTab.bibliothekOeffnen
    case let .stoebern(titel, suche): HLStoebernSeite(titel: titel, suche: suche)
    }
  }
}

/// Hinweise («Gewünscht») über einer ganzen Seite. Den laufenden Song zeigt nur Amperfys Mini-Player
/// (mit Wunsch-Knopf und Menü, HLMiniKnopf.swift), eine eigene Leiste gibt es seit 06.11.2026 nicht mehr.
struct HLSpielRahmen: ViewModifier {
  @ObservedObject private var player = HLPlayer.shared

  func body(content: Content) -> some View {
    content
      .overlay(alignment: .bottom) {
        if let text = player.hinweis { HLHinweis(text: text).padding(.bottom, 24) }
      }
      .animation(.default, value: player.hinweis)
  }
}

/// Dasselbe für Amperfys UIKit-Seiten (Suche, Künstlerseite): Die Ansicht ist nur so gross wie ihr Inhalt.
struct HLSpielLeiste: View {
  @ObservedObject private var player = HLPlayer.shared

  var body: some View {
    VStack(spacing: 8) {
      if let text = player.hinweis { HLHinweis(text: text) }
    }
    .frame(maxWidth: .infinity)
    .padding(.bottom, 8)
    .animation(.default, value: player.hinweis)
  }

  /// Über einer UIKit-Seite einbauen, unten über der Tab-Leiste bzw. der Tastatur.
  @MainActor static func einbauen(in vc: UIViewController) {
    let host = UIHostingController(rootView: HLSpielLeiste())
    host.sizingOptions = .intrinsicContentSize
    host.safeAreaRegions = []
    host.view.backgroundColor = .clear
    host.view.isUserInteractionEnabled = false
    host.view.translatesAutoresizingMaskIntoConstraints = false
    host.view.layer.zPosition = 100
    vc.addChild(host)
    vc.view.addSubview(host.view)
    let unten = host.view.bottomAnchor.constraint(equalTo: vc.view.safeAreaLayoutGuide.bottomAnchor)
    unten.priority = .defaultHigh
    NSLayoutConstraint.activate([
      host.view.leadingAnchor.constraint(equalTo: vc.view.safeAreaLayoutGuide.leadingAnchor),
      host.view.trailingAnchor.constraint(equalTo: vc.view.safeAreaLayoutGuide.trailingAnchor),
      unten,
      host.view.bottomAnchor.constraint(lessThanOrEqualTo: vc.view.keyboardLayoutGuide.topAnchor),
    ])
    host.didMove(toParent: vc)
  }
}

struct HLHinweis: View {
  let text: String

  var body: some View {
    Text(text)
      .font(.subheadline)
      .padding(.horizontal, 16).padding(.vertical, 10)
      .background(.thinMaterial, in: Capsule())
      .transition(.opacity)
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

  func zwischengespeichert(_ url: URL) -> UIImage? { cache.object(forKey: url as NSURL) }

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
    let stufe = player.stufe(song)
    Button {
      player.wuenschen(song)                            // auf dem Server: sofort in die Mediathek
    } label: {
      switch stufe {
      case .mediathek:
        Image(systemName: "checkmark").foregroundStyle(.green)
          .frame(width: 34, height: 30).background(.green.opacity(0.14), in: Capsule())
      case .server:
        Image(systemName: "plus").fontWeight(.semibold).foregroundStyle(Color.accentColor)
          .frame(width: 34, height: 30).background(Color.accentColor.opacity(0.14), in: Capsule())
          .accessibilityLabel("Zur Mediathek hinzufügen")
      case .angefragt:
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
    if !player.ausgeblendet.contains(s.schluessel) { zeile(s) }
  }

  @ViewBuilder private func zeile(_ s: HLSong) -> some View {
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
    .swipeActions(edge: .trailing) {
      Button { player.ablehnen(s) } label: { Label("Nicht mein Ding", systemImage: "hand.thumbsdown") }.tint(.red)
    }
    .contextMenu {
      if let nd = s.navidromeId {
        Button("Mix ab diesem Song", systemImage: "dot.radiowaves.left.and.right") { oeffnen(.sender(art: "navidrome", id: nd)) }
      } else if let id = s.deezerId {
        Button("Mix ab diesem Song", systemImage: "dot.radiowaves.left.and.right") { oeffnen(.sender(art: "song", id: "\(id)")) }
      }
      Button("Nicht mein Ding", systemImage: "hand.thumbsdown", role: .destructive) { player.ablehnen(s) }
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
              if let text = HLMediathekUI.kuenstlerText(name: a.name, aufServer: a.inBibliothek ?? 0) {
                Text(text).font(.caption).foregroundStyle(.secondary).lineLimit(1)
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

/// Waagrechte Reihe neuer Alben (Startseite).
struct HLAlbumBand: View {
  let alben: [HLAlbum]
  @Environment(\.hlOeffnen) private var oeffnen

  var body: some View {
    ScrollView(.horizontal, showsIndicators: false) {
      HStack(alignment: .top, spacing: 14) {
        ForEach(alben, id: \.id) { a in
          VStack(alignment: .leading, spacing: 3) {
            ZStack(alignment: .topTrailing) {
              HLBild(pfad: a.bild, groesse: 130)
              if a.vorhanden == true {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.white, .green).font(.title3).padding(6)
              }
            }
            Text(a.titel ?? "").font(.subheadline.weight(.semibold)).lineLimit(1)
            Text(a.kuenstler ?? "").font(.caption).foregroundStyle(.secondary).lineLimit(1)
            Text([a.typText, Self.datum(a.jahrDatum)].compactMap { $0 }.joined(separator: " · "))
              .font(.caption2).foregroundStyle(.secondary)
          }
          .frame(width: 130)
          .contentShape(Rectangle())
          .onTapGesture { oeffnen(.album(a.id)) }
        }
      }
      .padding(.vertical, 4)
    }
  }

  static func datum(_ iso: String?) -> String? {
    guard let iso, iso.count >= 10 else { return nil }
    let t = iso.split(separator: "-")
    return "\(t[2]).\(t[1])."
  }
}

/// Waagrechte Reihe von Song-Vorschlägen (Startseite); Antippen spielt die Reihe ab hier.
struct HLSongBand: View {
  let songs: [HLSong]
  @ObservedObject private var player = HLPlayer.shared

  var body: some View {
    ScrollView(.horizontal, showsIndicators: false) {
      HStack(alignment: .top, spacing: 14) {
        ForEach(songs.indices.filter { !player.ausgeblendet.contains(songs[$0].schluessel) }, id: \.self) { i in
          let s = songs[i]
          VStack(alignment: .leading, spacing: 3) {
            ZStack(alignment: .bottomTrailing) {
              HLBild(pfad: s.bild, groesse: 130)
                .overlay {
                  if player.aktuell?.schluessel == s.schluessel {
                    Image(systemName: "waveform").font(.title).foregroundStyle(.white)
                      .padding(10).background(.black.opacity(0.35), in: Circle())
                  }
                }
              HLStatusKnopf(song: s, kurz: true).padding(6)
            }
            Text(s.titel ?? "").font(.subheadline.weight(.semibold)).lineLimit(1)
            Text(s.kuenstler ?? "").font(.caption).foregroundStyle(.secondary).lineLimit(1)
          }
          .frame(width: 130)
          .contentShape(Rectangle())
          .onTapGesture { player.spielen(songs, ab: i) }
          .contextMenu {
            Button("Nicht mein Ding", systemImage: "hand.thumbsdown", role: .destructive) { player.ablehnen(s) }
          }
        }
      }
      .padding(.vertical, 4)
    }
  }
}

/// Download-Stand eines offenen Wunsches, bei Problemen mit «Andere Version».
struct HLFortschrittAnzeige: View {
  let wunsch: HLWunsch
  let fortschritt: HLFortschritt
  let neuLaden: () -> ()
  @State private var laeuft = false

  var body: some View {
    VStack(alignment: .trailing, spacing: 4) {
      Text(fortschritt.text).font(.caption)
        .foregroundStyle(fortschritt.phase == "fehler" ? Color.orange : .secondary)
        .multilineTextAlignment(.trailing)
      if let p = fortschritt.prozent { ProgressView(value: p).frame(width: 90) }
      if fortschritt.andere, let id = wunsch.id {
        Button(laeuft ? "Sucht …" : "Andere Version") {
          laeuft = true
          Task {
            if let r = try? await HLAPI.shared.andereVersion(wunschId: id) { HLPlayer.shared.zeigeHinweis(r.meldung ?? "") }
            laeuft = false
            neuLaden()
          }
        }
        .font(.caption.weight(.semibold)).buttonStyle(.borderless).disabled(laeuft)
      }
    }
    .frame(maxWidth: 170, alignment: .trailing)
  }
}

// MARK: - Seiten

/// Ein Song aus dem Radio: nachgeschlagen in Bibliothek bzw. bei Deezer, mit den passenden Knöpfen.
struct HLRadioZeile: View {
  let eintrag: HLRadioEintrag
  var gross = false
  @ObservedObject private var player = HLPlayer.shared
  @Environment(\.hlOeffnen) private var oeffnen

  var body: some View {
    let song = player.radioTreffer[eintrag.schluessel]
    VStack(alignment: .leading, spacing: 10) {
      HStack(spacing: 12) {
        HLBild(pfad: song?.bild, groesse: gross ? 64 : 44)
        VStack(alignment: .leading, spacing: 3) {
          Text(song?.titel ?? eintrag.titel).font(.body.weight(.semibold)).lineLimit(1)
          Text(song?.kuenstler ?? eintrag.kuenstler).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
          if let song { HLStatusZeile(status: player.status(song), klein: true) }
        }
        Spacer(minLength: 0)
        if song == nil { ProgressView() }
      }
      if let song, gross {
        HLTrefferKnoepfe(song: song, kompakt: true) { oeffnen($0) }
      }
    }
    .contentShape(Rectangle())
    .contextMenu {
      if let song {
        if let k = song.kuenstlerId { Button("Künstler ansehen", systemImage: "person") { oeffnen(.kuenstler(k)) } }
        if song.vorschau != nil || song.navidromeId != nil {
          Button("Abspielen", systemImage: "play") { player.spielen([song], ab: 0) }
        }
        if player.status(song) == "neu" {
          Button(HLMediathekUI.wunschText, systemImage: "plus") {
            if song.deezerId != nil { player.wuenschen(song) } else { player.wuenschenOhneDeezer(song) }
          }
        }
      }
    }
    .onAppear { player.nachschlagen(eintrag) }
  }
}

struct HLStartView: View {
  @ObservedObject private var player = HLPlayer.shared
  @State private var jetzt: HLJetzt?
  @State private var wuensche: [HLWunsch] = []
  @State private var reihen: [HLReihe] = []
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
            } label: { Label("Mix starten", systemImage: "dot.radiowaves.left.and.right") }
              .buttonStyle(HLKapsel(haupt: true))
            if let k = j.song.kuenstlerId {
              Button("Künstler entdecken") { oeffnen(.kuenstler(k)) }.buttonStyle(HLKapsel())
            }
          }
          .listRowSeparator(.hidden)
        }
      }
      if !player.radioVerlauf.isEmpty {
        Section(player.radioLaeuft ? "Läuft im Radio · \(player.radioVerlauf[0].sender)" : "Zuletzt im Radio") {
          ForEach(player.radioVerlauf, id: \.self) { e in
            HLRadioZeile(eintrag: e, gross: e == player.radioVerlauf.first)
          }
        }
      }
      ForEach(reihen, id: \.self) { r in
        Section {
          if r.typ == "alben", let alben = r.alben {
            HLAlbumBand(alben: alben)
          } else if let songs = r.songs {
            HLSongBand(songs: songs)
          }
        } header: {
          VStack(alignment: .leading, spacing: 1) {
            Text(r.titel)
            if let u = r.untertitel { Text(u).font(.caption).textCase(nil) }
          }
          .contentShape(Rectangle())
          .onTapGesture { if let k = r.kuenstlerId { oeffnen(.kuenstler(k)) } }
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
              } else if let f = w.fortschritt {
                HLFortschrittAnzeige(wunsch: w, fortschritt: f) { Task { await laden() } }
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
                           "nicht_gefunden": "– nicht gefunden", "weg": "– nicht mehr da"]

  /// Neu laden, höchstens alle 3 Sekunden; der alte Inhalt bleibt bis dahin stehen.
  private func neuLaden() {
    guard Date().timeIntervalSince(zuletzt) > 3 else { return }
    zuletzt = Date()
    Task { await laden() }
  }

  private func laden() async {
    fehler = nil
    async let j = try? HLAPI.shared.jetzt()
    async let r = try? HLAPI.shared.reihen()
    do { wuensche = try await HLAPI.shared.wuensche().wuensche } catch { fehler = error.localizedDescription }
    if let neu = await j { jetzt = neu }
    if let neu = await r { reihen = neu.reihen }
    geladen = true
  }
}

struct HLKuenstlerView: View {
  let id: Int
  @State private var folgt: Bool?
  @State private var folgtLaeuft = false
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
              if (d.kuenstler.inBibliothek ?? 0) > 0 {    // zur Künstlerseite der Bibliothek
                Button {
                  oeffnen(.bibliothek(kuenstler: d.kuenstler.name))
                } label: {
                  Label(Self.bibliothekText(d.kuenstler.inBibliothek ?? 0, name: d.kuenstler.name), systemImage: "music.note.house")
                    .font(.subheadline)
                }
                .buttonStyle(.plain).foregroundStyle(Color.accentColor)
              } else {
                Text(Self.bibliothekText(0)).font(.subheadline).foregroundStyle(.secondary)
              }
            }
          }
          let istGefolgt = folgt ?? d.kuenstler.folgt ?? false
          ViewThatFits(in: .horizontal) {                 // zu schmal: Mix und Folgen nur als Symbol
            knoepfe(d, istGefolgt, senderKurz: false, folgenKurz: false)
            knoepfe(d, istGefolgt, senderKurz: true, folgenKurz: false)
            knoepfe(d, istGefolgt, senderKurz: true, folgenKurz: true)
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

  @ViewBuilder private func knoepfe(_ d: HLKuenstlerSeite, _ istGefolgt: Bool, senderKurz: Bool, folgenKurz: Bool) -> some View {
    HStack {
      Button { HLPlayer.shared.spielen(d.top, ab: 0) } label: { Label("Reinhören", systemImage: "play.fill") }
        .buttonStyle(HLKapsel(haupt: true))
      Button { oeffnen(.sender(art: "kuenstler", id: "\(id)")) } label: {
        if senderKurz { Image(systemName: "dot.radiowaves.left.and.right") } else {
          Label("Mix", systemImage: "dot.radiowaves.left.and.right")
        }
      }
      .buttonStyle(HLKapsel())
      Button {
        folgtLaeuft = true
        Task {
          if let r = try? await HLAPI.shared.folgen(kuenstlerId: id, name: d.kuenstler.name, folgen: !istGefolgt) {
            folgt = r.folgt ?? !istGefolgt
            HLPlayer.shared.zeigeHinweis(r.meldung ?? "")
          }
          folgtLaeuft = false
        }
      } label: {
        if folgenKurz { Image(systemName: istGefolgt ? "checkmark" : "person.badge.plus") } else {
          Label(istGefolgt ? "Gefolgt" : "Folgen", systemImage: istGefolgt ? "checkmark" : "plus")
        }
      }
      .buttonStyle(HLKapsel(haupt: false))
      .disabled(folgtLaeuft)
    }
  }

  static func bibliothekText(_ n: Int, name: String = "") -> String {
    guard HLMediathekUI.stufenAktiv else {
      return n == 0 ? "Noch nichts in deiner Bibliothek" : "\(n) \(n == 1 ? "Song" : "Songs") in deiner Bibliothek"
    }
    if n == 0 { return "Noch nichts auf dem Server" }
    let eigene = HLMediathekUI.mediathekAnzahl(kuenstler: name)
    return eigene > 0 ? "\(eigene) in deiner Mediathek · \(n) auf dem Server" : "\(n) auf dem Server"
  }
}

struct HLAlbumView: View {
  let id: Int
  @State private var gewuenscht = false
  @Environment(\.hlOeffnen) private var oeffnen

  var body: some View {
    HLLaden(laden: { try await HLAPI.shared.album(id) }) { d in
      let a = d.album
      List {
        Section {
          HStack(alignment: .bottom, spacing: 16) {
            HLBild(pfad: a.bildGross ?? a.bild, groesse: 130)
            VStack(alignment: .leading, spacing: 4) {
              Text(a.titel ?? "").font(.title3.bold()).lineLimit(3)
              Button(a.kuenstler ?? "") { if let k = a.kuenstlerId { oeffnen(.kuenstler(k)) } }
                .buttonStyle(.plain).foregroundStyle(Color.accentColor)
              Text([a.jahr, "\(a.anzahl ?? 0) Songs", HLSammelKnoepfe.standText(d.songs)]
                .compactMap { $0 }.joined(separator: " · "))
                .font(.subheadline).foregroundStyle(.secondary)
            }
          }
          HLSammelKnoepfe(songs: d.songs)
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

/// Knöpfe über einer Song-Liste (Album, Playlist): reinhören, was auf dem Server ist in die Mediathek holen,
/// was fehlt wünschen (höchstens 50 auf einmal, ab 6 mit Rückfrage).
struct HLSammelKnoepfe: View {
  let songs: [HLSong]
  @ObservedObject private var player = HLPlayer.shared
  @State private var gewuenscht = false
  @State private var rueckfrage = false

  static let hoechstens = 50

  /// «7 in deiner Mediathek», «5 auf dem Server» bzw. ohne Mediathek «5 bei dir».
  @MainActor static func standText(_ songs: [HLSong]) -> String? {
    let p = HLPlayer.shared
    let eigene = songs.filter { p.stufe($0) == .mediathek }.count
    let server = songs.filter { p.stufe($0) == .server }.count
    guard HLMediathekUI.stufenAktiv else { return eigene > 0 ? "\(eigene) bei dir" : nil }
    if eigene > 0 { return "\(eigene) in deiner Mediathek" }
    return server > 0 ? "\(server) auf dem Server" : nil
  }

  var body: some View {
    let server = songs.filter { player.stufe($0) == .server }
    let fehlend = songs.filter { player.stufe($0) == .neu && $0.deezerId != nil }
    let anzahl = min(fehlend.count, Self.hoechstens)
    VStack(alignment: .leading, spacing: 10) {
      HStack {
        Button { player.spielen(songs, ab: 0) } label: { Label("Reinhören", systemImage: "play.fill") }
          .buttonStyle(HLKapsel(haupt: true))
        if !server.isEmpty {
          Button { player.zurMediathek(server) } label: {
            Label("\(server.count) zur Mediathek", systemImage: "plus")
          }
          .buttonStyle(HLKapsel())
        } else if fehlend.isEmpty, !songs.isEmpty {
          Label(HLMediathekUI.stufenAktiv ? "Alles in deiner Mediathek" : "Alles bei dir", systemImage: "checkmark")
            .foregroundStyle(.green).font(.subheadline)
        }
      }
      if anzahl > 0 {
        Button {
          if anzahl > 5 { rueckfrage = true } else { wuenschen(Array(fehlend.prefix(anzahl))) }
        } label: {
          Label(gewuenscht ? "Gewünscht" : (fehlend.count < songs.count ? "Rest wünschen (\(anzahl))" : "\(anzahl) wünschen"),
                systemImage: gewuenscht ? "hourglass" : "arrow.down.circle")
        }
        .buttonStyle(HLKapsel())
        .disabled(gewuenscht)
      }
    }
    .confirmationDialog("\(anzahl) Songs wünschen?", isPresented: $rueckfrage, titleVisibility: .visible) {
      Button("\(anzahl) Songs wünschen") { wuenschen(Array(fehlend.prefix(anzahl))) }
      Button("Abbrechen", role: .cancel) {}
    } message: {
      Text(fehlend.count > anzahl
        ? "Die ersten \(anzahl) von \(fehlend.count) fehlenden Songs gehen an SoulSync und kommen nach und nach."
        : "Sie gehen an SoulSync und kommen nach und nach.")
    }
  }

  private func wuenschen(_ liste: [HLSong]) {
    gewuenscht = true
    Task {
      do {
        let r = try await HLAPI.shared.wunsch(songs: liste.compactMap(\.deezerId))
        player.alsAngefragtMarkieren(liste)
        player.zeigeHinweis(r.meldung ?? "Gewünscht.")
      } catch {
        gewuenscht = false
        player.zeigeHinweis(error.localizedDescription)
      }
    }
  }
}
