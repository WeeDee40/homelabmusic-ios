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

  /// Mit Pause, weil die Suche bei jedem Tastendruck kommt: ab drei Wörtern fragt der Dienst Claude (kostet etwas).
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
      try? await Task.sleep(for: .milliseconds(1250))
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
  @ObservedObject private var player = HLPlayer.shared

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
    .padding(.bottom, player.aktuell != nil ? 84 : 0)  // Platz für die Leiste zum laufenden Song
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

/// Alles, was SearchVC vom Abschnitt «Entdecken» braucht.
@MainActor
final class HLSuchEinbau {
  let modell = HLSuchModell()

  private weak var vc: UIViewController?

  /// Künstler, Album oder Mix im Navigationsstapel der Suche öffnen.
  private var oeffnen: @MainActor (HLZiel) -> () {
    { [weak self] ziel in
      guard let nav = self?.vc?.navigationController else { return }
      nav.pushViewController(HLTab.zielAnsicht(ziel, navigation: nav), animated: true)
    }
  }

  func zelle() -> UITableViewCell {
    let zelle = UITableViewCell()
    zelle.selectionStyle = .none
    zelle.backgroundColor = .clear
    zelle.contentConfiguration = UIHostingConfiguration {
      HLSuchTreffer(modell: modell).environment(\.hlOeffnen, oeffnen)
    }
    return zelle
  }

  /// Leiste zum laufenden Song und Hinweise («Gewünscht»): steht über der Tabelle und scrollt nicht mit.
  func leisteEinbauen(in vc: UIViewController) {
    self.vc = vc
    let host = UIHostingController(rootView: HLSpielLeiste(oeffnen: oeffnen))
    host.sizingOptions = .intrinsicContentSize
    host.safeAreaRegions = []
    host.view.backgroundColor = .clear
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
