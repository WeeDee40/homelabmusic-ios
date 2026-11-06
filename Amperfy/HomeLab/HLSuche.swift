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
  let symbol: String

  /// Stimmungen, die der Medienwunsch-Dienst erkennt (entdecken.py, STIMMUNG; er schreibt klein). Höchstens
  /// zwei Wörter: ab drei Wörtern fragt er Claude. Der Suchtext erscheint in der Überschrift («Klingt nach …»).
  static let stimmungen: [HLKachel] = [
    HLKachel(titel: "Entspannt", suche: "Entspannt", symbol: "leaf.fill"),
    HLKachel(titel: "Gute Laune", suche: "Gute Laune", symbol: "sun.max.fill"),
    HLKachel(titel: "Party", suche: "Party", symbol: "party.popper.fill"),
    HLKachel(titel: "Zum Joggen", suche: "Zum Joggen", symbol: "figure.run"),
    HLKachel(titel: "Konzentration", suche: "Konzentration", symbol: "brain.head.profile"),
    HLKachel(titel: "Melancholisch", suche: "Melancholisch", symbol: "cloud.rain.fill"),
    HLKachel(titel: "Romantisch", suche: "Romantisch", symbol: "heart.fill"),
    HLKachel(titel: "Autofahren", suche: "Autofahren", symbol: "car.fill"),
  ]

  /// Die grössten Genres der Bibliothek (ohne Hörspiele), höchstens acht.
  @MainActor static func genres(account: Account) -> [HLKachel] {
    let weg = ["hörspiel", "hörbuch", "audio drama", "audiobook", "podcast", "kinder", "children", "unknown"]
    return (UIApplication.shared.delegate as! AppDelegate).storage.main.library.getGenres(for: account)
      .filter { g in g.songCount >= 10 && !weg.contains { g.name.lowercased().contains($0) } }
      .sorted { $0.songCount > $1.songCount }
      .prefix(8)
      .map { HLKachel(titel: $0.name, suche: $0.name, symbol: "music.note") }
  }

  /// Farben der Reihe nach, damit nebeneinander keine gleichen stehen.
  static let farben: [Color] = [.indigo, .teal, .pink, .orange, .purple, .blue, .green, .red, .mint, .brown]
}

struct HLStoebernView: View {
  let genres: [HLKachel]
  let waehlen: (HLKachel) -> ()

  var body: some View {
    VStack(alignment: .leading, spacing: 20) {
      gruppe("Stimmungen", HLKachel.stimmungen, farbeAb: 0)
      if !genres.isEmpty { gruppe("Genres in deiner Bibliothek", genres, farbeAb: 4) }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.vertical, 8)
  }

  private func gruppe(_ titel: String, _ liste: [HLKachel], farbeAb: Int) -> some View {
    VStack(alignment: .leading, spacing: 10) {
      Text(titel).font(.title3.bold())
      LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
        ForEach(Array(liste.enumerated()), id: \.element) { i, k in
          Button { waehlen(k) } label: {
            HStack(alignment: .top) {
              Text(k.titel).font(.subheadline.weight(.bold)).lineLimit(2).multilineTextAlignment(.leading)
              Spacer(minLength: 4)
              Image(systemName: k.symbol).font(.title3)
            }
            .foregroundStyle(.white)
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 64, alignment: .topLeading)
            .background(HLKachel.farben[(farbeAb + i) % HLKachel.farben.count].gradient,
                        in: RoundedRectangle(cornerRadius: 12))
          }
          .buttonStyle(.plain)
        }
      }
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
