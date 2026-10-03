//
//  HLShazam.swift
//  HomeLabMusic
//
//  Shazam im Entdecken-Tab: Song über das Mikrofon erkennen (ShazamKit) und wie der Kurzbefehl an den
//  Musikwunsch-Dienst geben: schon in der Bibliothek -> direkt abspielbar, sonst auf die SoulSync-Wunschliste.
//
//  This program is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//

import AmperfyKit
import ShazamKit
import SwiftUI
import UIKit

@MainActor
final class HLShazam: ObservableObject {
  enum Zustand {
    case bereit
    case hoert
    case wuenscht(titel: String, kuenstler: String, bild: URL?)
    case fertig(titel: String, kuenstler: String, bild: URL?, antwort: HLWunschAntwort)
    case nichtErkannt
    case fehler(String)
  }

  @Published private(set) var zustand = Zustand.bereit
  private var session: SHManagedSession?

  func starten() {
    (UIApplication.shared.delegate as! AppDelegate).player.pause()   // sonst hört Shazam die eigene Musik
    zustand = .hoert
    Task {
      let s = SHManagedSession()
      session = s
      let ergebnis = await s.result()
      session = nil
      switch ergebnis {
      case let .match(match):
        guard let item = match.mediaItems.first, let titel = item.title, let kuenstler = item.artist else {
          zustand = .nichtErkannt
          return
        }
        zustand = .wuenscht(titel: titel, kuenstler: kuenstler, bild: item.artworkURL)
        do {
          let antwort = try await HLAPI.shared.wunsch(titel: titel, kuenstler: kuenstler)
          zustand = .fertig(titel: titel, kuenstler: kuenstler, bild: item.artworkURL, antwort: antwort)
        } catch {
          zustand = .fehler(error.localizedDescription)
        }
      case .noMatch:
        zustand = .nichtErkannt
      case let .error(fehler, _):
        zustand = .fehler(Self.text(fehler))
      }
    }
  }

  /// ShazamKit-Fehler verständlich (Codes laut SHError).
  private static func text(_ fehler: Error) -> String {
    let e = fehler as NSError
    guard e.domain == SHError.errorDomain else { return fehler.localizedDescription }
    switch e.code {
    case 202:
      return "Die Erkennung ist gerade nicht möglich. Prüfe die Internetverbindung. Kommt der Fehler immer, ist ShazamKit für die App noch nicht freigeschaltet."
    case 100, 101:
      return "Das Mikrofon liefert keinen brauchbaren Ton. Läuft gerade ein Anruf oder eine andere Aufnahme?"
    case 200, 201:
      return "Zu wenig Musik gehört. Bitte nochmals, etwas näher an der Musik."
    default:
      return "Erkennung fehlgeschlagen (ShazamKit-Fehler \(e.code))."
    }
  }

  func abbrechen() {
    session?.cancel()
    session = nil
    zustand = .bereit
  }
}

struct HLShazamView: View {
  /// Künstler in der Entdecken-Suche öffnen (Sheet schliesst sich vorher).
  let suchen: (String) -> ()
  @StateObject private var shazam = HLShazam()
  @Environment(\.dismiss) private var schliessen

  var body: some View {
    NavigationStack {
      VStack(spacing: 24) {
        Spacer()
        inhalt
        Spacer()
      }
      .padding(24)
      .frame(maxWidth: .infinity)
      .navigationTitle("Song erkennen")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Button("Fertig") { shazam.abbrechen(); schliessen() }
        }
      }
    }
    .onAppear { shazam.starten() }
    .onDisappear { shazam.abbrechen() }
  }

  @ViewBuilder private var inhalt: some View {
    switch shazam.zustand {
    case .bereit:
      knopf("Zuhören", "shazam.logo.fill") { shazam.starten() }
    case .hoert:
      Image(systemName: "shazam.logo.fill").font(.system(size: 96)).foregroundStyle(Color.accentColor)
        .symbolEffect(.pulse, options: .repeating)
      Text("Hört zu …").font(.title3.weight(.semibold))
      Text("Halte das iPhone in Richtung Musik.").foregroundStyle(.secondary)
    case let .wuenscht(titel, kuenstler, bild):
      songKopf(titel, kuenstler, bild)
      ProgressView("Prüfe die Bibliothek …")
    case let .fertig(titel, kuenstler, bild, antwort):
      songKopf(titel, kuenstler, bild)
      Text(antwort.ueberschrift ?? "").font(.headline)
      if let m = antwort.meldung { Text(m).multilineTextAlignment(.center).foregroundStyle(.secondary) }
      VStack(spacing: 10) {
        if antwort.status == "gefunden", let id = antwort.songId {
          knopf("Abspielen", "play.fill") {
            HLPlayer.shared.spielen([HLSong(typ: "bibliothek", status: "bibliothek", deezerId: nil,
                                            titel: antwort.titel ?? titel, kuenstler: antwort.kuenstler ?? kuenstler,
                                            kuenstlerId: nil, album: antwort.album, albumId: nil,
                                            bild: "/entdecken/cover/mf-\(id)", bildGross: nil, dauer: nil,
                                            vorschau: nil, navidromeId: id, navidromeCover: nil)], ab: 0)
            schliessen()
          }
        }
        knopf("Künstler entdecken", "person.wave.2", haupt: false) { schliessen(); suchen(kuenstler) }
        knopf("Nächsten Song erkennen", "shazam.logo", haupt: false) { shazam.starten() }
      }
    case .nichtErkannt:
      Image(systemName: "questionmark.circle").font(.system(size: 72)).foregroundStyle(.secondary)
      Text("Nichts erkannt").font(.title3.weight(.semibold))
      knopf("Nochmals versuchen", "arrow.clockwise") { shazam.starten() }
    case let .fehler(text):
      Image(systemName: "exclamationmark.triangle").font(.system(size: 64)).foregroundStyle(.orange)
      Text(text).multilineTextAlignment(.center).foregroundStyle(.secondary)
      knopf("Nochmals versuchen", "arrow.clockwise") { shazam.starten() }
    }
  }

  private func songKopf(_ titel: String, _ kuenstler: String, _ bild: URL?) -> some View {
    VStack(spacing: 10) {
      AsyncImage(url: bild) { $0.resizable().scaledToFill() } placeholder: { Color.secondary.opacity(0.15) }
        .frame(width: 180, height: 180).clipShape(RoundedRectangle(cornerRadius: 16))
      Text(titel).font(.title2.bold()).multilineTextAlignment(.center)
      Text(kuenstler).foregroundStyle(.secondary)
    }
  }

  private func knopf(_ text: String, _ bild: String, haupt: Bool = true, _ aktion: @escaping () -> ()) -> some View {
    Button(action: aktion) {
      Label(text, systemImage: bild).frame(maxWidth: .infinity)
    }
    .buttonStyle(HLKapsel(haupt: haupt))
  }
}
