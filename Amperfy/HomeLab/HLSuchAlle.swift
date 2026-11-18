//
//  HLSuchAlle.swift
//  HomeLabMusic
//
//  Suche «Alle» aus einem Guss (PLAN-musik-erlebnis.md, Etappe H): Amperfys Treffer aus der Datenbank und die
//  Treffer des Medienwunsch-Dienstes in einer einzigen Ansicht, wie bei Apple Music. Jeder Künstler, jedes Album
//  und jeder Song erscheint einmal; Eigenes (Mediathek, ✓) steht vor dem Server und vor Neuem.
//
//  This program is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//

import AmperfyKit
import SwiftUI
import UIKit

/// Treffer aus Amperfys Datenbank (setzt SearchVC nach jeder Eingabe).
@MainActor
struct HLLokal {
  var text = ""
  var kuenstler: [Artist] = []
  var alben: [Album] = []
  var songs: [Song] = []
  var playlists: [Playlist] = []

  var istLeer: Bool { kuenstler.isEmpty && alben.isEmpty && songs.isEmpty && playlists.isEmpty }
}

// MARK: - Bild aus Amperfy

/// Cover, Künstlerbild oder Playlist-Mosaik eines Eintrags aus Amperfys Datenbank (wie Amperfys Zeilen).
struct HLAmperfyBild: UIViewRepresentable {
  let eintrag: PlayableContainable
  var groesse: CGFloat = 48
  var rund = false

  func makeUIView(context: Context) -> EntityImageView {
    let bild = EntityImageView(frame: CGRect(x: 0, y: 0, width: groesse, height: groesse))
    bild.clipsToBounds = true
    return bild
  }

  func updateUIView(_ bild: EntityImageView, context: Context) {
    let theme = appDelegate.storage.settings.accounts.getSetting(eintrag.account?.info).read.themePreference
    bild.display(theme: theme, container: eintrag, cornerRadius: rund ? .big : .small)
    bild.layer.cornerRadius = rund ? groesse / 2 : groesse / 7
    if let k = eintrag as? Artist, let artwork = k.artwork, let info = k.account?.info {
      appDelegate.getMeta(info).artworkDownloadManager.download(object: artwork)
    }
  }

  func sizeThatFits(_ proposal: ProposedViewSize, uiView: EntityImageView, context: Context) -> CGSize? {
    CGSize(width: groesse, height: groesse)
  }
}

// MARK: - Zusammenführen

enum HLKuenstlerTreffer: Identifiable {
  case server(HLKuenstler)
  case lokal(Artist)

  var id: String {
    switch self {
    case let .server(k): return "d\(k.id)"
    case let .lokal(a): return "n\(a.id)"
    }
  }

  var name: String {
    switch self {
    case let .server(k): return k.name
    case let .lokal(a): return a.name
    }
  }
}

enum HLAlbumTreffer: Identifiable {
  case server(HLAlbum)
  case lokal(Album)

  var id: String {
    switch self {
    case let .server(a): return "d\(a.id)"
    case let .lokal(a): return "n\(a.id)"
    }
  }
}

enum HLPlaylistTreffer: Identifiable {
  case server(HLPlaylistKurz)
  case lokal(Playlist)

  var id: String {
    switch self {
    case let .server(p): return "d\(p.id)"
    case let .lokal(p): return "n\(p.id)"
    }
  }
}

@MainActor
enum HLSuchMischung {
  private static func norm(_ s: String?) -> String { HLDeezer.norm(s ?? "") }

  /// Stabil sortieren: kleinere Stufe zuerst, sonst bleibt die Trefferfolge.
  private static func nachStufe<T>(_ liste: [T], _ stufe: (T) -> Int) -> [T] {
    liste.enumerated().sorted { (stufe($0.element), $0.offset) < (stufe($1.element), $1.offset) }.map(\.element)
  }

  /// Künstler vom Dienst (Deezer, mit Stand auf dem Server) und aus der Datenbank (auch, was Deezer nicht kennt);
  /// der Top-Treffer fehlt hier, er steht schon darüber.
  static func kuenstler(_ server: [HLKuenstler], _ lokal: [Artist], ohne top: String?) -> [HLKuenstlerTreffer] {
    var gesehen = Set([top.map(norm)].compactMap { $0 })
    var liste = [HLKuenstlerTreffer]()
    for k in server where gesehen.insert(norm(k.name)).inserted { liste.append(.server(k)) }
    for a in lokal where gesehen.insert(norm(a.name)).inserted { liste.append(.lokal(a)) }
    let stufen = HLMediathekUI.stufenAktiv
    return nachStufe(liste) { t in
      switch t {
      case let .lokal(a): return stufen && !a.managedObject.hlInMediathek ? 1 : 0
      case let .server(k):
        if stufen, HLMediathekUI.mediathekAnzahl(kuenstler: k.name) > 0 { return 0 }
        return (k.inBibliothek ?? 0) > 0 ? 1 : 2
      }
    }
  }

  /// Songs vom Dienst (mit Stand) und aus der Datenbank, die der Dienst nicht schon brachte.
  static func songs(_ server: [HLSong], _ lokal: [Song]) -> [HLSong] {
    var ids = Set(server.compactMap(\.navidromeId))
    var schluessel = Set(server.map { norm($0.kuenstler) + "|" + norm($0.titel) })
    var liste = server
    for s in lokal where ids.insert(s.id).inserted {
      guard schluessel.insert(norm(s.creatorName) + "|" + norm(s.title)).inserted else { continue }
      liste.append(alsHLSong(s))
    }
    let player = HLPlayer.shared
    return nachStufe(liste) { s in
      switch player.stufe(s) {
      case .mediathek: return 0
      case .server: return 1
      case .angefragt: return 2
      case .neu: return 3
      }
    }
  }

  static func alsHLSong(_ s: Song) -> HLSong {
    HLSong(typ: "bibliothek", status: "bibliothek", deezerId: nil, titel: s.title, kuenstler: s.creatorName,
           kuenstlerId: nil, album: s.album?.name, albumId: nil, bild: "/entdecken/cover/mf-\(s.id)",
           bildGross: nil, dauer: Double(s.duration), vorschau: nil, navidromeId: s.id, navidromeCover: nil)
  }

  /// Alben aus der Datenbank (eigene zuerst), dann vom Dienst ohne die, die es schon gibt.
  static func alben(_ server: [HLAlbum], _ lokal: [Album]) -> [HLAlbumTreffer] {
    let stufen = HLMediathekUI.stufenAktiv
    let eigene = nachStufe(lokal) { stufen && $0.managedObject.hlMediathekSeit == nil ? 1 : 0 }
    var gesehen = Set(lokal.map { norm($0.subtitle) + "|" + norm($0.name) })
    let neue = server.filter { gesehen.insert(norm($0.kuenstler) + "|" + norm($0.titel)).inserted }
    return eigene.map { .lokal($0) } + neue.map { .server($0) }
  }

  /// Eigene Playlists (Navidrome, ohne die Mediathek-Playlist), dann öffentliche von Deezer.
  static func playlists(_ server: [HLPlaylistKurz], _ lokal: [Playlist]) -> [HLPlaylistTreffer] {
    lokal.filter { $0.name != HLMediathek.playlistName }.map { .lokal($0) } + server.map { .server($0) }
  }

  /// Künstler aus der Datenbank, der genau wie die Suche heisst (Top-Treffer, wenn der Dienst keinen hat).
  static func lokalerTop(_ lokal: HLLokal) -> Artist? {
    let q = norm(lokal.text)
    return lokal.kuenstler.first { norm($0.name) == q }
  }
}

// MARK: - Bausteine

/// Top-Treffer aus der Datenbank (der Dienst ist nicht erreichbar oder kennt den Künstler nicht).
struct HLLokalTopKarte: View {
  let kuenstler: Artist
  let oeffnen: (PlayableContainable) -> ()

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Top-Treffer").font(.headline)
      HStack(spacing: 14) {
        HLAmperfyBild(eintrag: kuenstler, groesse: 76, rund: true)
        VStack(alignment: .leading, spacing: 3) {
          Text(kuenstler.name).font(.title3.weight(.semibold)).lineLimit(2)
          Text(["Künstler", HLMediathekUI.kuenstlerText(name: kuenstler.name, aufServer: kuenstler.songCount)]
            .compactMap { $0 }.joined(separator: " · "))
            .font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        Image(systemName: "chevron.right").foregroundStyle(.tertiary)
      }
      .padding(12)
      .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 14))
      .contentShape(RoundedRectangle(cornerRadius: 14))
      .onTapGesture { oeffnen(kuenstler) }
    }
  }
}

/// ✓ oben rechts auf einem Bild: in deiner Mediathek.
private struct HLHaken: View {
  var body: some View {
    Image(systemName: "checkmark.circle.fill")
      .font(.title3)
      .symbolRenderingMode(.palette)
      .foregroundStyle(.white, Color.accentColor)
      .padding(5)
      .accessibilityLabel("In deiner Mediathek")
  }
}

struct HLMischKuenstlerBand: View {
  let liste: [HLKuenstlerTreffer]
  let lokalOeffnen: (PlayableContainable) -> ()
  @Environment(\.hlOeffnen) private var oeffnen

  var body: some View {
    ScrollView(.horizontal, showsIndicators: false) {
      HStack(alignment: .top, spacing: 14) {
        ForEach(liste) { t in
          Button {
            switch t {
            case let .server(k): oeffnen(.kuenstler(k.id))
            case let .lokal(a): lokalOeffnen(a)
            }
          } label: {
            VStack(spacing: 4) {
              switch t {
              case let .server(k): HLBild(pfad: k.bild, groesse: 96, rund: true)
              case let .lokal(a): HLAmperfyBild(eintrag: a, groesse: 96, rund: true)
              }
              Text(t.name).font(.subheadline.weight(.semibold)).lineLimit(1)
              if let text = untertitel(t) {
                Text(text).font(.caption).foregroundStyle(.secondary).lineLimit(2).multilineTextAlignment(.center)
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

  private func untertitel(_ t: HLKuenstlerTreffer) -> String? {
    switch t {
    case let .server(k): return HLMediathekUI.kuenstlerText(name: k.name, aufServer: k.inBibliothek ?? 0)
    case let .lokal(a): return HLMediathekUI.kuenstlerText(name: a.name, aufServer: a.songCount)
    }
  }
}

struct HLMischAlbumBand: View {
  let liste: [HLAlbumTreffer]
  let lokalOeffnen: (PlayableContainable) -> ()
  @Environment(\.hlOeffnen) private var oeffnen

  var body: some View {
    ScrollView(.horizontal, showsIndicators: false) {
      HStack(alignment: .top, spacing: 14) {
        ForEach(liste) { t in
          switch t {
          case let .lokal(a):
            karte(titel: a.name, unten: a.subtitle) {
              ZStack(alignment: .topTrailing) {
                HLAmperfyBild(eintrag: a, groesse: 130)
                if HLMediathekUI.stufenAktiv, a.managedObject.hlMediathekSeit != nil { HLHaken() }
              }
            }
            .onTapGesture { lokalOeffnen(a) }
            .contextMenu { HLMenueEintraege(eintraege: HLMediathekUI.menue(fuer: a)) }
          case let .server(a):
            karte(titel: a.titel ?? "", unten: a.kuenstler) {
              ZStack(alignment: .topTrailing) {
                HLBild(pfad: a.bild, groesse: 130)
                HLAlbumZeichen(album: a, kuenstler: a.kuenstler)
              }
            }
            .onTapGesture { oeffnen(.album(a.id)) }
          }
        }
      }
      .padding(.vertical, 4)
    }
  }

  private func karte(titel: String, unten: String?, @ViewBuilder bild: () -> some View) -> some View {
    VStack(alignment: .leading, spacing: 3) {
      bild()
      Text(titel).font(.subheadline.weight(.semibold)).lineLimit(1)
      Text(unten ?? "").font(.caption).foregroundStyle(.secondary).lineLimit(1)
    }
    .frame(width: 130)
    .contentShape(Rectangle())
  }
}

struct HLMischPlaylistBand: View {
  let liste: [HLPlaylistTreffer]
  let lokalOeffnen: (PlayableContainable) -> ()
  @Environment(\.hlOeffnen) private var oeffnen

  var body: some View {
    ScrollView(.horizontal, showsIndicators: false) {
      HStack(alignment: .top, spacing: 14) {
        ForEach(liste) { t in
          VStack(alignment: .leading, spacing: 3) {
            switch t {
            case let .lokal(p):
              HLAmperfyBild(eintrag: p, groesse: 130)
              Text(p.name).font(.subheadline.weight(.semibold)).lineLimit(2)
              Text("\(p.songCount) Songs · Deine Playlist").font(.caption).foregroundStyle(.secondary).lineLimit(1)
            case let .server(p):
              HLBild(pfad: p.bild, groesse: 130)
              Text(p.titel ?? "").font(.subheadline.weight(.semibold)).lineLimit(2)
              Text([p.anzahl.map { "\($0) Songs" }, p.vonText].compactMap { $0 }.joined(separator: " · "))
                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
          }
          .frame(width: 130)
          .contentShape(Rectangle())
          .onTapGesture {
            switch t {
            case let .lokal(p): lokalOeffnen(p)
            case let .server(p): oeffnen(.playlist(p.id))
            }
          }
        }
      }
      .padding(.vertical, 4)
    }
  }
}

/// UIKit-Menüeinträge (HLMediathekUI.menue) als SwiftUI-Kontextmenü.
struct HLMenueEintraege: View {
  let eintraege: [UIMenuElement]

  var body: some View {
    ForEach(Array(eintraege.compactMap { $0 as? UIAction }.enumerated()), id: \.offset) { _, a in
      Button(role: a.attributes.contains(.destructive) ? .destructive : nil) {
        a.performWithSender(nil, target: nil)
      } label: {
        if let bild = a.image { Label { Text(a.title) } icon: { Image(uiImage: bild) } } else { Text(a.title) }
      }
    }
  }
}
