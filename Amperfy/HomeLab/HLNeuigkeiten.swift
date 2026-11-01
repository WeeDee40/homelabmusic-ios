//
//  HLNeuigkeiten.swift
//  HomeLabMusic
//
//  «Neu in dieser Version»: einmal nach einem Update, in den Einstellungen zum Nachlesen.
//
//  This program is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//

import SwiftUI
import UIKit

/// Ein Eintrag aus NEUIGKEITEN.md, die in der App liegt und vom Upload-Skript auch an TestFlight geht.
/// Überschrift `## 2026-11-01` (zweiter Eintrag am selben Tag: `## 2026-11-01b`), darunter `### Neu`,
/// `### Anders` oder `### Behoben` und kurze Sätze mit `- `. Der neueste Eintrag steht zuoberst.
struct HLNeuigkeitenEintrag: Identifiable, Hashable, Sendable {
  struct Gruppe: Hashable, Sendable {
    var titel: String
    var punkte: [String] = []
  }

  let id: String
  var gruppen: [Gruppe] = []

  var datum: String {
    let lesen = DateFormatter()
    lesen.locale = Locale(identifier: "en_US_POSIX")
    lesen.dateFormat = "yyyy-MM-dd"
    guard let tag = lesen.date(from: String(id.prefix(10))) else { return id }
    let schreiben = DateFormatter()
    schreiben.locale = Locale(identifier: "de_CH")
    schreiben.dateFormat = "d. MMMM yyyy"
    return schreiben.string(from: tag)
  }
}

enum HLNeuigkeiten {
  private static let schluessel = "neuigkeiten.gesehen"

  static let alle: [HLNeuigkeitenEintrag] = {
    guard let url = Bundle.main.url(forResource: "NEUIGKEITEN", withExtension: "md"),
       let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
    return lesen(text)
  }()

  static func lesen(_ text: String) -> [HLNeuigkeitenEintrag] {
    var eintraege: [HLNeuigkeitenEintrag] = []
    for zeile in text.components(separatedBy: .newlines) {
      if zeile.hasPrefix("### "), !eintraege.isEmpty {
        eintraege[eintraege.count - 1].gruppen.append(.init(titel: String(zeile.dropFirst(4))))
      } else if zeile.hasPrefix("## ") {
        eintraege.append(HLNeuigkeitenEintrag(id: String(zeile.dropFirst(3)).trimmingCharacters(in: .whitespaces)))
      } else if zeile.hasPrefix("- "), let e = eintraege.indices.last, let g = eintraege[e].gruppen.indices.last {
        eintraege[e].gruppen[g].punkte.append(String(zeile.dropFirst(2)))
      }
    }
    return eintraege
  }

  /// Was seit dem letzten Öffnen neu ist. Noch nie etwas gezeigt: Neu installiert (nicht angemeldet) sieht nichts,
  /// wer von einer Version ohne dieses Fenster kommt, nur den neuesten Eintrag.
  static func ungesehene(angemeldet: Bool) -> [HLNeuigkeitenEintrag] {
    guard let gesehen = UserDefaults.standard.string(forKey: schluessel) else {
      if angemeldet { return Array(alle.prefix(1)) }
      alleGesehen()
      return []
    }
    return alle.filter { $0.id > gesehen }
  }

  @MainActor private static var geprueft = false

  /// Beim Erscheinen der Hauptansicht (WelcomePopupPresenter); auf den Start warten, damit nichts anderes dazwischenkommt.
  @MainActor
  static func zeigenFallsNeu(neuInstalliert: Bool) {
    guard !geprueft else { return }
    geprueft = true
    let liste = ungesehene(angemeldet: !neuInstalliert)
    guard !liste.isEmpty else { return }
    Task { @MainActor in
      try? await Task.sleep(for: .seconds(1))
      guard let host = AppDelegate.mainWindowHostVC as? UIViewController, host.presentedViewController == nil else { return }
      host.present(UIHostingController(rootView: HLNeuigkeitenView(eintraege: liste).onDisappear { alleGesehen() }), animated: true)
    }
  }

  static func alleGesehen() {
    if let neuester = alle.first { UserDefaults.standard.set(neuester.id, forKey: schluessel) }
  }
}

struct HLNeuigkeitenView: View {
  let eintraege: [HLNeuigkeitenEintrag]
  @Environment(\.dismiss) private var schliessen

  var body: some View {
    NavigationStack {
      List {
        ForEach(eintraege) { e in
          Section(e.datum) {
            ForEach(e.gruppen, id: \.self) { g in
              zeile(g)
            }
          }
        }
      }
      .navigationTitle("Neu in dieser Version")
      .toolbar {
        ToolbarItem(placement: .confirmationAction) { Button("Fertig") { schliessen() } }
      }
    }
    #if os(macOS)
    .frame(minWidth: 460, minHeight: 380)
    #endif
  }

  private func zeile(_ g: HLNeuigkeitenEintrag.Gruppe) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(g.titel).font(.headline)
      ForEach(g.punkte, id: \.self) { Text("• \($0)") }
    }
  }
}
