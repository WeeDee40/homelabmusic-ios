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
    abschnitte?.isEmpty == false || !kuenstler.isEmpty || !neueSongs.isEmpty || !alben.isEmpty
  }
}

@MainActor
final class HLSuchModell: ObservableObject {
  @Published private(set) var ergebnis: HLSuche?
  @Published private(set) var laedt = false
  @Published private(set) var fehler: String?
  /// Der Abschnitt kommt oder geht: SearchVC baut die Tabelle neu auf.
  var geaendert: (() -> ())?
  private(set) var text = ""
  private var aufgabe: Task<(), Never>?

  var sichtbar: Bool { laedt || fehler != nil || ergebnis?.hatInhalt == true }

  /// Mit Pause, weil die Suche bei jedem Tastendruck kommt. Kurz für Namen, lang ab drei Wörtern:
  /// dann fragt der Dienst Claude (kostet etwas), also erst, wenn die Eingabe steht.
  static func pause(fuer q: String) -> Duration {
    q.split(separator: " ").count >= 3 ? .milliseconds(1250) : .milliseconds(400)
  }

  func suchen(_ eingabe: String) {
    let q = eingabe.trimmingCharacters(in: .whitespaces)
    guard q != text else { return }                  // auch beim Zurückkehren von einer Künstlerseite
    aufgabe?.cancel()
    text = q
    fehler = nil
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
    // Genre/Stimmung erkannt: diese Abschnitte zuerst, die Titelsuche danach
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
        ForEach(a.songs.prefix(10).indices, id: \.self) { HLSongZeile(songs: a.songs, i: $0) }
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
        ForEach(songs.indices, id: \.self) { HLSongZeile(songs: songs, i: $0) }
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
      HLStoebernView(genres: liste) { [weak self] k in self?.oeffnen(.stoebern(titel: k.titel, suche: k.suche)) }
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
  /// Suchwort für das Hintergrundbild (Titelbild einer passenden Deezer-Playlist), Englisch trifft besser.
  let bild: String

  /// Stimmungen, die der Medienwunsch-Dienst erkennt (entdecken.py, STIMMUNG; er schreibt klein). Höchstens
  /// zwei Wörter: ab drei Wörtern fragt er Claude. Der Suchtext erscheint in der Überschrift («Klingt nach …»).
  static let stimmungen: [HLKachel] = [
    HLKachel(titel: "Entspannt", suche: "Entspannt", bild: "chill"),
    HLKachel(titel: "Gute Laune", suche: "Gute Laune", bild: "good vibes"),
    HLKachel(titel: "Party", suche: "Party", bild: "party"),
    HLKachel(titel: "Zum Joggen", suche: "Zum Joggen", bild: "running"),
    HLKachel(titel: "Konzentration", suche: "Konzentration", bild: "focus"),
    HLKachel(titel: "Melancholisch", suche: "Melancholisch", bild: "melancholic"),
    HLKachel(titel: "Romantisch", suche: "Romantisch", bild: "love songs"),
    HLKachel(titel: "Autofahren", suche: "Autofahren", bild: "road trip"),
  ]

  /// Die grössten Genres der Bibliothek (ohne Hörspiele), höchstens acht.
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
  let waehlen: (HLKachel) -> ()
  @ObservedObject private var bilder = HLKachelBilder.shared

  var body: some View {
    VStack(alignment: .leading, spacing: 20) {
      gruppe("Stimmungen", HLKachel.stimmungen, farbeAb: 0)
      if !genres.isEmpty { gruppe("Genres in deiner Bibliothek", genres, farbeAb: 4) }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.vertical, 8)
    .task { await bilder.laden(HLKachel.stimmungen + genres) }
  }

  private func gruppe(_ titel: String, _ liste: [HLKachel], farbeAb: Int) -> some View {
    VStack(alignment: .leading, spacing: 10) {
      Text(titel).font(.title3.bold())
      LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
        ForEach(Array(liste.enumerated()), id: \.element) { i, k in
          Button { waehlen(k) } label: {
            HLKachelBild(url: bilder.urls[k.bild], farbe: HLKachel.farben[(farbeAb + i) % HLKachel.farben.count])
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
  @State private var bild: UIImage?

  var body: some View {
    Color.clear
      .background(farbe.gradient)
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

/// Seite zu einer Kachel: nur die erkannte Stimmung bzw. das Genre (aus der Bibliothek und neu zum Reinhören),
/// ohne die Namens-Treffer der normalen Suche («Party» fände sonst «Knife Party»).
struct HLStoebernSeite: View {
  let titel: String
  let suche: String

  var body: some View {
    HLLaden(laden: { try await HLAPI.shared.suche(suche) }) { d in
      let abschnitte = d.abschnitte ?? []
      if abschnitte.isEmpty {
        ContentUnavailableView("Nichts gefunden", systemImage: "music.note",
                               description: Text("Zu «\(titel)» gibt es gerade keine passenden Songs."))
      } else {
        List {
          ForEach(abschnitte, id: \.self) { a in
            Section {
              ForEach(a.songs.indices, id: \.self) { HLSongZeile(songs: a.songs, i: $0) }
            } header: {
              HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 1) {
                  Text(a.titel)
                  if let u = a.untertitel { Text(u).font(.caption).textCase(nil) }
                }
                Spacer()
                Button { HLPlayer.shared.spielen(a.songs, ab: 0) } label: {
                  Label("Alle", systemImage: "play.fill").font(.caption.weight(.semibold))
                }
                .buttonStyle(HLKapsel(haupt: true))
              }
            }
          }
        }
      }
    }
    .navigationTitle(titel)
  }
}
