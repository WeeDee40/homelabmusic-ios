//
//  HLSuche.swift
//  HomeLabMusic
//
//  Abschnitt «Entdecken» in Amperfys Suche (SearchVC): unter den Treffern aus der Bibliothek die Suche
//  des Medienwunsch-Dienstes (Künstler, Songs, Alben, Genre, Stimmung), wie «Zum Wünschen» bei HomeLabTV.
//
//  This program is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//

import AmperfyKit
import SwiftUI
import UIKit

extension HLSuche {
  /// Songs aus der Bibliothek stehen schon oben in Amperfys Treffern.
  var neueSongs: [HLSong] { songs.filter { $0.status != "bibliothek" } }

  var hatInhalt: Bool {
    top != nil || abschnitte?.isEmpty == false || !kuenstler.isEmpty || !neueSongs.isEmpty || !alben.isEmpty
      || playlists?.isEmpty == false
  }
}

@MainActor
final class HLSuchModell: ObservableObject {
  @Published private(set) var ergebnis: HLSuche?
  @Published private(set) var laedt = false
  @Published private(set) var fehler: String?
  @Published private(set) var vorschlaege = [HLVorschlag]()
  /// Der Abschnitt kommt oder geht: SearchVC baut die Tabelle neu auf.
  var geaendert: (() -> ())?
  /// Text ins Suchfeld setzen und suchen (Vorschlag, «Zuletzt gesucht»); setzt SearchVC.
  var uebernehmen: ((String) -> ())?
  private(set) var text = ""
  private var aufgabe: Task<(), Never>?
  private var vorschlagAufgabe: Task<(), Never>?
  private var merkAufgabe: Task<(), Never>?

  var sichtbar: Bool { laedt || fehler != nil || ergebnis?.hatInhalt == true || !vorschlaege.isEmpty }

  /// Vorschläge kommen schneller als die Treffer; ab drei Wörtern keine (dann ist es ein Satz).
  private func vorschlaegeHolen(_ q: String) {
    vorschlagAufgabe?.cancel()
    guard q.count >= 2, q.split(separator: " ").count < 3 else {
      if !vorschlaege.isEmpty { vorschlaege = []; geaendert?() }
      return
    }
    vorschlagAufgabe = Task {
      try? await Task.sleep(for: .milliseconds(200))
      guard !Task.isCancelled, let neu = try? await HLAPI.shared.vorschlaege(q), !Task.isCancelled,
            q == text else { return }
      let warLeer = vorschlaege.isEmpty
      vorschlaege = neu
      if warLeer != neu.isEmpty { geaendert?() }
    }
  }

  /// Eine Suche, deren Treffer 2,5 s stehen bleiben, kommt in «Zuletzt gesucht» (Zwischenstände beim Tippen nicht).
  private func merken(_ q: String) {
    merkAufgabe?.cancel()
    merkAufgabe = Task {
      try? await Task.sleep(for: .milliseconds(2500))
      guard !Task.isCancelled, q == text else { return }
      HLSuchVerlauf.shared.merken(q)
    }
  }

  /// Mit Pause, weil die Suche bei jedem Tastendruck kommt. Kurz für Namen, lang ab drei Wörtern:
  /// dann fragt der Dienst Claude (kostet etwas), also erst, wenn die Eingabe steht.
  static func pause(fuer q: String) -> Duration {
    q.split(separator: " ").count >= 3 ? .milliseconds(1250) : .milliseconds(400)
  }

  func suchen(_ eingabe: String) {
    let q = eingabe.trimmingCharacters(in: .whitespaces)
    guard q != text else { return }                  // auch beim Zurückkehren von einer Künstlerseite
    aufgabe?.cancel()
    merkAufgabe?.cancel()
    text = q
    fehler = nil
    vorschlaegeHolen(q)
    guard q.count >= 2 else {
      ergebnis = nil
      laedt = false
      geaendert?()
      return
    }
    laedt = true
    geaendert?()
    aufgabe = Task {
      try? await Task.sleep(for: Self.pause(fuer: q))
      guard !Task.isCancelled else { return }
      do {
        let r = try await HLAPI.shared.suche(q)
        guard !Task.isCancelled else { return }
        ergebnis = r
        if r.hatInhalt { merken(q) }
      } catch {
        guard !Task.isCancelled else { return }
        ergebnis = nil
        fehler = "Entdecken gerade nicht erreichbar."
      }
      laedt = false
      geaendert?()
    }
  }
}

/// Eine einzige Tabellenzeile: Amperfys Tabelle kennt nur Einträge aus der Datenbank.
struct HLSuchTreffer: View {
  @ObservedObject var modell: HLSuchModell

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      if !modell.vorschlaege.isEmpty {
        HLVorschlagBand(liste: modell.vorschlaege) { modell.uebernehmen?($0.suche) }
      }
      if modell.laedt {
        HStack(spacing: 10) {
          ProgressView()
          Text(modell.text.split(separator: " ").count >= 3 ? "Suche passende Titel …" : "Suche weiter …")
            .foregroundStyle(.secondary)
        }
      }
      if let fehler = modell.fehler { Text(fehler).foregroundStyle(.secondary) }
      if let d = modell.ergebnis { inhalt(d) }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  @ViewBuilder private func inhalt(_ d: HLSuche) -> some View {
    if let top = d.top { HLTopKarte(top: top) }
    // Genre/Stimmung/Thema erkannt: diese Abschnitte zuerst, die Titelsuche danach
    ForEach(d.abschnitte ?? [], id: \.self) { a in
      VStack(alignment: .leading, spacing: 10) {
        HStack(alignment: .bottom) {
          VStack(alignment: .leading, spacing: 1) {
            Text(a.titel).font(.headline)
            if let u = a.untertitel { Text(u).font(.caption).foregroundStyle(.secondary) }
          }
          Spacer()
          Button { HLPlayer.shared.spielen(a.songs, ab: 0) } label: {
            Label("Alle", systemImage: "play.fill").font(.caption.weight(.semibold))
          }
          .buttonStyle(.plain).foregroundStyle(Color.accentColor)
        }
        HLSongRaster(songs: a.songs)
      }
    }
    if !d.kuenstler.isEmpty {
      VStack(alignment: .leading, spacing: 6) {
        Text("Künstler").font(.headline)
        HLKuenstlerBand(liste: d.kuenstler)
      }
    }
    let songs = d.neueSongs
    if !songs.isEmpty {
      VStack(alignment: .leading, spacing: 10) {
        Text("Songs").font(.headline)
        HLSongRaster(songs: songs)
      }
    }
    if let listen = d.playlists, !listen.isEmpty {
      VStack(alignment: .leading, spacing: 6) {
        Text("Playlists").font(.headline)
        HLPlaylistBand(liste: listen)
      }
    }
    if !d.alben.isEmpty {
      VStack(alignment: .leading, spacing: 6) {
        Text("Alben").font(.headline)
        HLAlbumBand(alben: d.alben)
      }
    }
  }
}

/// «Top-Treffer» wie bei Apple Music: der eine Künstler, Song, das Album oder die Playlist, die am besten passt.
struct HLTopKarte: View {
  let top: HLTopTreffer
  @Environment(\.hlOeffnen) private var oeffnen

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Top-Treffer").font(.headline)
      HStack(spacing: 14) {
        HLBild(pfad: bild, groesse: 76, rund: top.art == "kuenstler")
        VStack(alignment: .leading, spacing: 3) {
          Text(titel).font(.title3.weight(.semibold)).lineLimit(2)
          Text(untertitel).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        if top.art == "song", let s = top.song {
          HLStatusKnopf(song: s, kurz: true)
        } else {
          Image(systemName: "chevron.right").foregroundStyle(.tertiary)
        }
      }
      .padding(12)
      .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 14))
      .contentShape(RoundedRectangle(cornerRadius: 14))
      .onTapGesture { antippen() }
    }
  }

  private var bild: String? {
    switch top.art {
    case "kuenstler": return top.kuenstler?.bild
    case "song": return top.song?.bild
    case "album": return top.album?.bild
    default: return top.playlist?.bild
    }
  }

  private var titel: String {
    switch top.art {
    case "kuenstler": return top.kuenstler?.name ?? ""
    case "song": return top.song?.titel ?? ""
    case "album": return top.album?.titel ?? ""
    default: return top.playlist?.titel ?? ""
    }
  }

  private var untertitel: String {
    switch top.art {
    case "kuenstler":
      guard let k = top.kuenstler else { return "Künstler" }
      return ["Künstler", HLMediathekUI.kuenstlerText(name: k.name, aufServer: k.inBibliothek ?? 0)]
        .compactMap { $0 }.joined(separator: " · ")
    case "song":
      let stufe = top.song.map { HLPlayer.shared.stufe($0) }
      return ["Song", top.song?.kuenstler, stufe == .mediathek ? (HLMediathekUI.stufenAktiv ? "in deiner Mediathek" : "bei dir")
        : stufe == .server ? "auf dem Server" : nil]
        .compactMap { $0 }.joined(separator: " · ")
    case "album":
      return ["Album", top.album?.kuenstler].compactMap { $0 }.joined(separator: " · ")
    default:
      let p = top.playlist
      return ["Playlist", p?.anzahl.map { "\($0) Songs" }, p?.vonText].compactMap { $0 }.joined(separator: " · ")
    }
  }

  private func antippen() {
    switch top.art {
    case "kuenstler": if let k = top.kuenstler { oeffnen(.kuenstler(k.id)) }
    case "song": if let s = top.song { HLPlayer.shared.spielen([s], ab: 0) }
    case "album": if let a = top.album { oeffnen(.album(a.id)) }
    default: if let p = top.playlist { oeffnen(.playlist(p.id)) }
    }
  }
}

/// Waagrechte Reihe öffentlicher Playlists.
struct HLPlaylistBand: View {
  let liste: [HLPlaylistKurz]
  @Environment(\.hlOeffnen) private var oeffnen

  var body: some View {
    ScrollView(.horizontal, showsIndicators: false) {
      HStack(alignment: .top, spacing: 14) {
        ForEach(liste, id: \.id) { p in
          VStack(alignment: .leading, spacing: 3) {
            HLBild(pfad: p.bild, groesse: 130)
            Text(p.titel ?? "").font(.subheadline.weight(.semibold)).lineLimit(2)
            Text([p.anzahl.map { "\($0) Songs" }, p.vonText].compactMap { $0 }.joined(separator: " · "))
              .font(.caption).foregroundStyle(.secondary).lineLimit(1)
          }
          .frame(width: 130)
          .contentShape(Rectangle())
          .onTapGesture { oeffnen(.playlist(p.id)) }
        }
      }
      .padding(.vertical, 4)
    }
  }
}

/// Öffentliche Playlist: reinhören (Bibliothek ganz, Rest als Vorschau), in die Mediathek holen, Fehlendes wünschen.
struct HLPlaylistView: View {
  let id: Int

  var body: some View {
    HLLaden(laden: { try await HLAPI.shared.playlist(id) }) { d in
      let p = d.playlist
      List {
        Section {
          HStack(alignment: .bottom, spacing: 16) {
            HLBild(pfad: p.bildGross ?? p.bild, groesse: 130)
            VStack(alignment: .leading, spacing: 4) {
              Text(p.titel ?? "").font(.title3.bold()).lineLimit(3)
              if let von = p.vonText { Text(von).font(.subheadline).foregroundStyle(.secondary) }
              Text(["\(d.songs.count) Songs", HLSammelKnoepfe.standText(d.songs)].compactMap { $0 }
                .joined(separator: " · "))
                .font(.subheadline).foregroundStyle(.secondary)
            }
          }
          HLSammelKnoepfe(songs: d.songs)
            .listRowSeparator(.hidden)
        }
        Section("Songs") {
          ForEach(d.songs.indices, id: \.self) { HLSongZeile(songs: d.songs, i: $0) }
        }
      }
      .navigationTitle(p.titel ?? "Playlist")
    }
    .navigationBarTitleDisplayMode(.inline)
  }
}

/// Alles, was SearchVC von «Entdecken» braucht: Treffer-Abschnitt, Kacheln zum Stöbern, Hinweise.
@MainActor
final class HLSuchEinbau {
  let modell = HLSuchModell()
  private weak var vc: UIViewController?
  private var genres: [HLKachel]?

  /// Künstler, Album oder Mix im Navigationsstapel der Suche öffnen.
  private var oeffnen: @MainActor (HLZiel) -> () {
    { [weak self] ziel in
      self?.vc?.navigationController?.pushViewController(HLTab.zielAnsicht(ziel), animated: true)
    }
  }

  func zelle() -> UITableViewCell {
    hostZelle {
      HLSuchTreffer(modell: self.modell).environment(\.hlOeffnen, self.oeffnen)
    }
  }

  /// Leere Suche: Kacheln für Stimmungen und die grössten Genres der Bibliothek (wie «Alles durchsuchen»).
  func stoebernZelle(account: Account) -> UITableViewCell {
    if genres == nil { genres = HLKachel.genres(account: account) }
    let liste = genres ?? []
    return hostZelle {
      HLStoebernView(genres: liste, suchen: { [weak self] text in self?.modell.uebernehmen?(text) }) { [weak self] k in
        self?.oeffnen(.stoebern(titel: k.titel, suche: k.suche, playlists: k.bild))
      }
    }
  }

  private func hostZelle(@ViewBuilder _ inhalt: () -> some View) -> UITableViewCell {
    let zelle = UITableViewCell()
    zelle.selectionStyle = .none
    zelle.backgroundColor = .clear
    zelle.contentConfiguration = UIHostingConfiguration(content: inhalt)
    return zelle
  }

  /// Hinweise («Gewünscht»): stehen über der Tabelle und scrollen nicht mit.
  func leisteEinbauen(in vc: UIViewController) {
    self.vc = vc
    HLSpielLeiste.einbauen(in: vc)
  }
}

// MARK: - Stöbern

struct HLKachel: Hashable {
  let titel: String
  let suche: String
  /// Suchwort für Playlists auf der Kategorie-Seite und (nur Genres) für das Hintergrundbild, Englisch trifft besser.
  let bild: String
  /// Feste Kacheln zeichnen ein Symbol statt eines Deezer-Bilds: Deezers Titelbilder zeigen meist einen Künstler
  /// (Silvester: Daft Punk).
  var symbol: String? = nil

  /// Stimmungen, die der Medienwunsch-Dienst erkennt (entdecken.py, STIMMUNG; er schreibt klein). Höchstens
  /// zwei Wörter: ab drei Wörtern fragt er Claude. Der Suchtext erscheint in der Überschrift («Klingt nach …»).
  static let stimmungen: [HLKachel] = [
    HLKachel(titel: "Entspannt", suche: "Entspannt", bild: "chill", symbol: "leaf.fill"),
    HLKachel(titel: "Gute Laune", suche: "Gute Laune", bild: "good vibes", symbol: "sun.max.fill"),
    HLKachel(titel: "Party", suche: "Party", bild: "party", symbol: "party.popper.fill"),
    HLKachel(titel: "Zum Joggen", suche: "Zum Joggen", bild: "running", symbol: "figure.run"),
    HLKachel(titel: "Konzentration", suche: "Konzentration", bild: "focus", symbol: "brain.head.profile"),
    HLKachel(titel: "Melancholisch", suche: "Melancholisch", bild: "melancholic", symbol: "cloud.rain.fill"),
    HLKachel(titel: "Romantisch", suche: "Romantisch", bild: "love songs", symbol: "heart.fill"),
    HLKachel(titel: "Autofahren", suche: "Autofahren", bild: "road trip", symbol: "car.fill"),
  ]

  /// Die grössten Genres der Bibliothek (ohne Hörspiele), höchstens acht.
  /// Anlässe und Jahrzehnte (entdecken.py, THEMEN; die Suche muss dort ein Thema treffen). Monate: Saison,
  /// passende stehen zuerst, Anlässe ausser Saison zuletzt.
  static let anlaesse: [(HLKachel, [Int])] = [
    (HLKachel(titel: "Weihnachten", suche: "Weihnachtslieder", bild: "christmas hits", symbol: "gift.fill"), [11, 12]),
    (HLKachel(titel: "Silvester", suche: "Silvester", bild: "new year party", symbol: "sparkles"), [11, 12, 1]),
    (HLKachel(titel: "Après-Ski", suche: "Après-Ski", bild: "apres ski", symbol: "figure.skiing.downhill"), [12, 1, 2, 3]),
    (HLKachel(titel: "Fasnacht", suche: "Fasnacht", bild: "karneval hits", symbol: "theatermasks.fill"), [1, 2, 3]),
    (HLKachel(titel: "Sommerhits", suche: "Sommerhits", bild: "summer hits", symbol: "beach.umbrella.fill"), [6, 7, 8]),
    (HLKachel(titel: "Oktoberfest", suche: "Oktoberfest", bild: "oktoberfest", symbol: "mug.fill"), [9, 10]),
    (HLKachel(titel: "Halloween", suche: "Halloween", bild: "halloween party", symbol: "moon.stars.fill"), [10]),
    (HLKachel(titel: "Aktuelle Hits", suche: "Aktuelle Hits", bild: "top hits", symbol: "chart.line.uptrend.xyaxis"), []),
    (HLKachel(titel: "Mundart", suche: "Mundart", bild: "mundart", symbol: "mountain.2.fill"), []),
    (HLKachel(titel: "Hochzeit", suche: "Hochzeit", bild: "wedding songs", symbol: "bell.fill"), []),
    (HLKachel(titel: "Geburtstag", suche: "Geburtstag", bild: "birthday party", symbol: "birthday.cake.fill"), []),
    (HLKachel(titel: "Hits der 80er", suche: "80er", bild: "80s hits", symbol: "recordingtape"), []),
    (HLKachel(titel: "Hits der 90er", suche: "90er", bild: "90s hits", symbol: "opticaldisc.fill"), []),
    (HLKachel(titel: "Hits der 2000er", suche: "2000er", bild: "2000s hits", symbol: "headphones"), []),
    (HLKachel(titel: "Disney", suche: "Disney", bild: "disney hits", symbol: "wand.and.stars"), []),
    (HLKachel(titel: "Filmhits", suche: "Filmhits", bild: "movie soundtrack", symbol: "film.fill"), []),
  ]

  static func anlaesseJetzt(_ datum: Date = Date()) -> [HLKachel] {
    let monat = Calendar.current.component(.month, from: datum)
    let saison = anlaesse.filter { $0.1.contains(monat) }.map(\.0)
    let immer = anlaesse.filter { $0.1.isEmpty }.map(\.0)
    let spaeter = anlaesse.filter { !$0.1.isEmpty && !$0.1.contains(monat) }.map(\.0)
    return saison + immer + spaeter
  }

  @MainActor static func genres(account: Account) -> [HLKachel] {
    let weg = ["hörspiel", "hörbuch", "audio drama", "audiobook", "podcast", "kinder", "children", "unknown"]
    return (UIApplication.shared.delegate as! AppDelegate).storage.main.library.getGenres(for: account)
      .filter { g in g.songCount >= 10 && !weg.contains { g.name.lowercased().contains($0) } }
      .sorted { $0.songCount > $1.songCount }
      .prefix(8)
      .map { HLKachel(titel: $0.name, suche: $0.name, bild: $0.name) }
  }

  /// Farben der Reihe nach: Hintergrund, solange das Bild lädt oder wenn es keines gibt.
  static let farben: [Color] = [.indigo, .teal, .pink, .orange, .purple, .blue, .green, .red, .mint, .brown]
}

/// Hintergrundbilder der Kacheln: Titelbild der passendsten Deezer-Playlist (mindestens 15 Songs), je Kachel
/// ein anderes. Direkt bei Deezers öffentlicher Schnittstelle wie HLDeezer; die Adressen bleiben 30 Tage gemerkt.
@MainActor
final class HLKachelBilder: ObservableObject {
  static let shared = HLKachelBilder()
  @Published private(set) var urls = [String: URL]()
  private static let schluessel = "homelabmusic.kachelbilder"           // Suchwort -> [Adresse, Zeitpunkt]
  private var laeuft = false

  private init() {
    let gemerkt = UserDefaults.standard.dictionary(forKey: Self.schluessel) as? [String: [String]] ?? [:]
    let frisch = Date().timeIntervalSince1970 - 30 * 24 * 3600
    for (wort, w) in gemerkt where w.count == 2 && (Double(w[1]) ?? 0) > frisch {
      if let url = URL(string: w[0]) { urls[wort] = url }
    }
  }

  func laden(_ kacheln: [HLKachel]) async {
    guard !laeuft else { return }
    laeuft = true
    defer { laeuft = false }
    var vergeben = Set(urls.values)
    for k in kacheln where urls[k.bild] == nil {
      guard let url = await suchen(k.bild, ausser: vergeben) else { continue }
      urls[k.bild] = url
      vergeben.insert(url)
      var gemerkt = UserDefaults.standard.dictionary(forKey: Self.schluessel) as? [String: [String]] ?? [:]
      gemerkt[k.bild] = [url.absoluteString, "\(Date().timeIntervalSince1970)"]
      UserDefaults.standard.set(gemerkt, forKey: Self.schluessel)
    }
  }

  private func suchen(_ wort: String, ausser: Set<URL>) async -> URL? {
    var teile = URLComponents(string: "https://api.deezer.com/search/playlist")!
    teile.queryItems = [URLQueryItem(name: "q", value: wort), URLQueryItem(name: "limit", value: "10")]
    struct Antwort: Decodable {
      struct Liste: Decodable { let nb_tracks: Int?; let picture_xl: String? }
      let data: [Liste]?
    }
    guard let url = teile.url,
          let (daten, _) = try? await URLSession.shared.data(from: url),
          let antwort = try? JSONDecoder().decode(Antwort.self, from: daten) else { return nil }
    return (antwort.data ?? [])
      .filter { ($0.nb_tracks ?? 0) >= 15 }
      .compactMap { $0.picture_xl.flatMap(URL.init(string:)) }
      .first { !ausser.contains($0) }
  }
}

struct HLStoebernView: View {
  let genres: [HLKachel]
  let suchen: (String) -> ()
  let waehlen: (HLKachel) -> ()
  @ObservedObject private var bilder = HLKachelBilder.shared
  @ObservedObject private var verlauf = HLSuchVerlauf.shared

  var body: some View {
    VStack(alignment: .leading, spacing: 20) {
      if !verlauf.liste.isEmpty {
        VStack(alignment: .leading, spacing: 4) {
          HStack {
            Text("Zuletzt gesucht").font(.title3.bold())
            Spacer()
            Button("Löschen") { verlauf.leeren() }.font(.subheadline)
          }
          ForEach(verlauf.liste, id: \.self) { q in
            HStack(spacing: 10) {
              Image(systemName: "clock.arrow.circlepath").foregroundStyle(.secondary)
              Text(q).frame(maxWidth: .infinity, alignment: .leading)
              Image(systemName: "arrow.up.left").font(.caption).foregroundStyle(.tertiary)
            }
            .padding(.vertical, 7)
            .contentShape(Rectangle())
            .onTapGesture { suchen(q) }
            .contextMenu {
              Button("Aus dem Verlauf entfernen", systemImage: "trash", role: .destructive) { verlauf.entfernen(q) }
            }
          }
        }
      }
      gruppe("Stimmungen", HLKachel.stimmungen, farbeAb: 0)
      gruppe("Anlässe", HLKachel.anlaesseJetzt(), farbeAb: 2)
      if !genres.isEmpty { gruppe("Genres auf dem Server", genres, farbeAb: 4) }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.vertical, 8)
    .task { await bilder.laden(genres) }
  }

  private func gruppe(_ titel: String, _ liste: [HLKachel], farbeAb: Int) -> some View {
    VStack(alignment: .leading, spacing: 10) {
      Text(titel).font(.title3.bold())
      LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
        ForEach(Array(liste.enumerated()), id: \.element) { i, k in
          Button { waehlen(k) } label: {
            HLKachelBild(url: k.symbol == nil ? bilder.urls[k.bild] : nil,
                         farbe: HLKachel.farben[(farbeAb + i) % HLKachel.farben.count], symbol: k.symbol)
              .aspectRatio(1.6, contentMode: .fit)
              .overlay(alignment: .bottomLeading) {
                Text(k.titel)
                  .font(.headline).foregroundStyle(.white).lineLimit(2).multilineTextAlignment(.leading)
                  .shadow(color: .black.opacity(0.5), radius: 3)
                  .padding(10)
              }
              .clipShape(RoundedRectangle(cornerRadius: 12))
              .contentShape(RoundedRectangle(cornerRadius: 12))
          }
          .buttonStyle(.plain)
        }
      }
    }
  }
}

/// Bild füllend, unten dunkler Verlauf für die Schrift; vor dem Laden die Farbe.
struct HLKachelBild: View {
  let url: URL?
  let farbe: Color
  var symbol: String? = nil
  @State private var bild: UIImage?

  var body: some View {
    Color.clear
      .background(farbe.gradient)
      .overlay(alignment: .topTrailing) {
        if let symbol {
          Image(systemName: symbol)
            .font(.system(size: 46, weight: .semibold))
            .foregroundStyle(.white.opacity(0.9))
            .rotationEffect(.degrees(-10))
            .padding(.top, 12).padding(.trailing, 14)
            .accessibilityHidden(true)
        }
      }
      .overlay {
        if let bild {
          Image(uiImage: bild).resizable().scaledToFill().transition(.opacity)
        }
      }
      .overlay {
        LinearGradient(colors: [.clear, .black.opacity(0.65)], startPoint: .center, endPoint: .bottom)
      }
      .clipped()
      .task(id: url) {
        guard let url else { return }
        let b = await HLBildSpeicher.shared.bild(url)
        withAnimation(.easeIn(duration: 0.2)) { bild = b }
      }
  }
}

/// Kategorie-Seite einer Kachel (Etappe G, wie Apples «Kategorien durchsuchen»): oben die grösste Playlist,
/// darunter Song-Raster «Aus deiner Mediathek», «Auf dem Server» und «Neu», dann weitere Playlists und (bei
/// Anlässen) die Künstler mit den meisten Hits. Ohne Mediathek ein Raster «Bei dir». «Alle» oben nur beim
/// Mediathek-Raster; die anderen haben die Sammelknöpfe (Abspielen/Reinhören, zur Mediathek, wünschen).
struct HLKategorieSeite: View {
  let titel: String
  let suche: String
  let playlistSuche: String?
  @Environment(\.hlOeffnen) private var oeffnen

  var body: some View {
    HLLaden(laden: { try await HLAPI.shared.kategorie(suche, playlists: playlistSuche) },
            gemerkt: { HLAPI.shared.kategorieGemerkt(suche, playlists: playlistSuche) }) { k in
      inhalt(k)
    }
    .navigationTitle(titel)
  }

  @ViewBuilder private func inhalt(_ k: HLKategorie) -> some View {
    let stufen = HLMediathekUI.stufenAktiv
    let eigene = stufen ? k.mediathek : []
    let server = stufen ? k.server : k.mediathek + k.server
    if eigene.isEmpty, server.isEmpty, k.neu.isEmpty, k.playlists.isEmpty {
      ContentUnavailableView("Nichts gefunden", systemImage: "music.note",
                             description: Text("Zu «\(titel)» gibt es gerade keine passenden Songs."))
    } else {
      ScrollView {
        LazyVStack(alignment: .leading, spacing: 28) {
          if let p = k.playlists.first { grossePlaylist(p) }
          if !eigene.isEmpty {
            abschnitt("Aus deiner Mediathek", songs: eigene) { HLSongRaster(songs: eigene) }
          }
          if !server.isEmpty {
            abschnitt(stufen ? "Auf dem Server" : "Bei dir",
                      stufen ? "Noch nicht in deiner Mediathek" : nil) {
              HLSongRaster(songs: server)
              if stufen { HLSammelKnoepfe(songs: server) }
            }
          }
          if !k.neu.isEmpty {
            abschnitt("Neu", "Zum Reinhören und Wünschen") {
              HLSongRaster(songs: k.neu)
              HLSammelKnoepfe(songs: k.neu)
            }
          }
          if k.playlists.count > 1 {
            abschnitt("Playlists") { HLPlaylistBand(liste: Array(k.playlists.dropFirst())) }
          }
          if let ks = k.kuenstler, !ks.isEmpty {
            abschnitt("Künstler") { HLKuenstlerBand(liste: ks) }
          }
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
      }
    }
  }

  private func grossePlaylist(_ p: HLPlaylistKurz) -> some View {
    Button { oeffnen(.playlist(p.id)) } label: {
      HLKachelBild(url: URL(string: p.bildGross ?? p.bild ?? ""), farbe: HLKachel.farben[0])
        .aspectRatio(1.5, contentMode: .fit)
        .overlay(alignment: .bottomLeading) {
          VStack(alignment: .leading, spacing: 2) {
            Text("Playlist").font(.caption.weight(.semibold)).foregroundStyle(.white.opacity(0.8))
            Text(p.titel ?? "").font(.title2.bold()).foregroundStyle(.white).lineLimit(2)
            Text([p.anzahl.map { "\($0) Songs" }, p.vonText].compactMap { $0 }.joined(separator: " · "))
              .font(.subheadline).foregroundStyle(.white.opacity(0.85)).lineLimit(1)
          }
          .multilineTextAlignment(.leading)
          .shadow(color: .black.opacity(0.4), radius: 3)
          .padding(14)
        }
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .contentShape(RoundedRectangle(cornerRadius: 14))
    }
    .buttonStyle(.plain)
  }

  private func abschnitt(_ titel: String, _ untertitel: String? = nil, songs: [HLSong]? = nil,
                         @ViewBuilder inhalt: () -> some View) -> some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(alignment: .firstTextBaseline) {
        VStack(alignment: .leading, spacing: 1) {
          Text(titel).font(.title2.bold())
          if let untertitel { Text(untertitel).font(.subheadline).foregroundStyle(.secondary) }
        }
        Spacer(minLength: 0)
        if let songs, !songs.isEmpty {
          Button { HLPlayer.shared.spielen(songs, ab: 0) } label: {
            Label("Alle", systemImage: "play.fill").font(.caption.weight(.semibold))
          }
          .buttonStyle(HLKapsel(haupt: true))
        }
      }
      inhalt()
    }
  }
}

// MARK: - Vorschläge und Verlauf

/// Waagrechte Reihe von Vorschlägen beim Tippen (Thema, Künstler, Song).
struct HLVorschlagBand: View {
  let liste: [HLVorschlag]
  let waehlen: (HLVorschlag) -> ()

  var body: some View {
    ScrollView(.horizontal, showsIndicators: false) {
      HStack(spacing: 8) {
        ForEach(liste, id: \.self) { v in
          Label(v.text, systemImage: Self.symbol(v.art))
            .font(.subheadline.weight(.medium))
            .lineLimit(1)
            .padding(.horizontal, 12).padding(.vertical, 7)
            .background(Color.secondary.opacity(0.13), in: Capsule())
            .contentShape(Capsule())
            .onTapGesture { waehlen(v) }
        }
      }
      .padding(.vertical, 2)
    }
  }

  static func symbol(_ art: String) -> String {
    switch art {
    case "thema": return "sparkles"
    case "kuenstler": return "music.mic"
    default: return "music.note"
    }
  }
}

/// «Zuletzt gesucht»: die letzten zehn Suchen dieses Geräts (nur der Text, nichts geht an den Server).
@MainActor
final class HLSuchVerlauf: ObservableObject {
  static let shared = HLSuchVerlauf()
  private static let schluessel = "homelabmusic.suchverlauf"
  @Published private(set) var liste: [String]

  private init() {
    liste = UserDefaults.standard.stringArray(forKey: Self.schluessel) ?? []
  }

  func merken(_ q: String) {
    let q = q.trimmingCharacters(in: .whitespaces)
    guard q.count >= 2 else { return }
    // «Weihnachtslied» und danach «Weihnachtslieder»: nur das Längere behalten
    var neu = liste.filter { $0.caseInsensitiveCompare(q) != .orderedSame && !q.lowercased().hasPrefix($0.lowercased()) }
    neu.insert(q, at: 0)
    liste = Array(neu.prefix(10))
    UserDefaults.standard.set(liste, forKey: Self.schluessel)
  }

  func entfernen(_ q: String) {
    liste.removeAll { $0 == q }
    UserDefaults.standard.set(liste, forKey: Self.schluessel)
  }

  func leeren() {
    liste = []
    UserDefaults.standard.removeObject(forKey: Self.schluessel)
  }
}
