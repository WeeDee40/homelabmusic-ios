//
//  HLShazam.swift
//  HomeLabMusic
//
//  Shazam im Entdecken-Tab: Song über das Mikrofon erkennen (ShazamKit), in der Bibliothek nachschlagen und
//  als Karte zeigen. In der Bibliothek -> ganz abspielen. Nicht vorhanden -> 30-Sekunden-Vorschau von Deezer
//  und erst auf Knopfdruck zur Bibliothek hinzufügen (SoulSync-Wunschliste).
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
    case sucht(titel: String, kuenstler: String, bild: URL?)
    case erkannt(song: HLSong, shazamBild: URL?)
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
        zustand = .sucht(titel: titel, kuenstler: kuenstler, bild: item.artworkURL)
        do {
          let song = try await HLAPI.shared.erkennen(titel: titel, kuenstler: kuenstler)
          zustand = .erkannt(song: song, shazamBild: item.artworkURL)
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
  /// Ziel im Entdecken-Tab öffnen (Sheet schliesst sich vorher).
  let oeffnen: (HLZiel) -> ()
  @StateObject private var shazam = HLShazam()
  @ObservedObject private var player = HLPlayer.shared
  @Environment(\.dismiss) private var schliessen

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(spacing: 22) { inhalt }
          .padding(24)
          .frame(maxWidth: .infinity, minHeight: 560)
      }
      .navigationTitle("Song erkennen")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Button("Fertig") { shazam.abbrechen(); schliessen() }
        }
      }
      .overlay(alignment: .bottom) {
        if let text = player.hinweis, !text.isEmpty {
          Text(text).font(.subheadline).padding(.horizontal, 16).padding(.vertical, 10)
            .background(.thinMaterial, in: Capsule()).padding(.bottom, 24)
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
    case let .sucht(titel, kuenstler, bild):
      kopf(titel, kuenstler, bild.map(\.absoluteString))
      ProgressView("Schaue in der Bibliothek nach …")
    case let .erkannt(song, shazamBild):
      erkannt(song, shazamBild)
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

  @ViewBuilder private func erkannt(_ song: HLSong, _ shazamBild: URL?) -> some View {
    kopf(song.titel ?? "", song.kuenstler ?? "", song.bildGross ?? song.bild ?? shazamBild?.absoluteString)
    HLStatusZeile(status: player.status(song))
    VStack(spacing: 10) {
      HLTrefferKnoepfe(song: song) { ziel in schliessen(); oeffnen(ziel) }
      knopf("Nächsten Song erkennen", "shazam.logo", haupt: false) { shazam.starten() }
    }
  }

  private func kopf(_ titel: String, _ kuenstler: String, _ bild: String?) -> some View {
    VStack(spacing: 10) {
      HLBild(pfad: bild, groesse: 200)
      Text(titel).font(.title2.bold()).multilineTextAlignment(.center)
      Text(kuenstler).foregroundStyle(.secondary).multilineTextAlignment(.center)
    }
  }

  private func knopf(_ text: String, _ bild: String, haupt: Bool = true, _ aktion: @escaping () -> ()) -> some View {
    Button(action: aktion) { Label(text, systemImage: bild).frame(maxWidth: .infinity) }
      .buttonStyle(HLKapsel(haupt: haupt))
  }
}

// MARK: - Gemeinsame Bausteine für erkannte Songs (Shazam, Radio)

struct HLStatusZeile: View {
  let status: String
  var klein = false

  var body: some View {
    let (text, bild, farbe): (String, String, Color) = switch status {
    case "bibliothek": ("In deiner Bibliothek", "checkmark.circle.fill", .green)
    case "angefragt": ("Hinzugefügt, kommt in ein paar Minuten", "hourglass", .orange)
    default: ("Nicht in deiner Bibliothek", "circle.dashed", .secondary)
    }
    Label(text, systemImage: bild).font((klein ? Font.caption : .subheadline).weight(.semibold)).foregroundStyle(farbe)
      .padding(.horizontal, klein ? 10 : 14).padding(.vertical, klein ? 5 : 8).background(farbe.opacity(0.12), in: Capsule())
  }
}

/// Knöpfe je nach Status: Bibliothek -> ganz abspielen; sonst 30-s-Vorschau und «hinzufügen»; dazu der Künstler.
struct HLTrefferKnoepfe: View {
  let song: HLSong
  var kompakt = false
  let oeffnen: (HLZiel) -> ()
  @ObservedObject private var player = HLPlayer.shared

  var body: some View {
    let status = player.status(song)
    let spielt = player.aktuell?.schluessel == song.schluessel && player.spielt
    let layout = kompakt ? AnyLayout(HStackLayout(spacing: 8)) : AnyLayout(VStackLayout(spacing: 10))
    layout {
      if status == "bibliothek" {
        knopf(spielt ? "Pause" : (kompakt ? "Abspielen" : "Aus der Bibliothek abspielen"),
              spielt ? "pause.fill" : "play.fill") { abspielen() }
      } else {
        if song.vorschau != nil {
          knopf(spielt ? "Pause" : (kompakt ? "30 s" : "30 Sekunden reinhören"), spielt ? "pause.fill" : "play.fill",
                haupt: status != "neu") { abspielen() }
        } else if !kompakt {
          Text("Keine Vorschau verfügbar.").font(.footnote).foregroundStyle(.secondary)
        }
        if status == "neu" {
          knopf(kompakt ? "Hinzufügen" : "Zur Bibliothek hinzufügen", "plus") {
            if song.deezerId != nil { player.wuenschen(song) } else { player.wuenschenOhneDeezer(song) }
          }
        }
      }
      if let k = song.kuenstlerId {
        knopf(kompakt ? "Künstler" : "Künstler entdecken", "person.wave.2", haupt: false) { oeffnen(.kuenstler(k)) }
      }
    }
  }

  private func abspielen() {
    if player.aktuell?.schluessel == song.schluessel { player.umschalten() } else { player.spielen([song], ab: 0) }
  }

  private func knopf(_ text: String, _ bild: String, haupt: Bool = true, _ aktion: @escaping () -> ()) -> some View {
    Button(action: aktion) {
      Label(text, systemImage: bild).frame(maxWidth: kompakt ? nil : .infinity)
    }
    .buttonStyle(HLKapsel(haupt: haupt))
  }
}
