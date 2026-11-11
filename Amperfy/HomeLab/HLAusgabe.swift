//
//  HLAusgabe.swift
//  HomeLabMusic
//
//  Zeigt am AirPlay-Knopf des Players, worüber die Musik gerade läuft: Statt des immer gleichen
//  AirPlay-Zeichens steht dort das Symbol des Geräts (AirPods, Kopfhörer, HomePod, Auto …), und es
//  hat die Akzentfarbe, solange nicht der eingebaute Lautsprecher spielt. So sieht man vor dem
//  Abspielen, ob die Kopfhörer wirklich verbunden sind.
//
//  Amperfy kennt nur das feste Zeichen; hier wird der Knopf nach jeder Änderung der Ausgabe
//  (AVAudioSession.routeChangeNotification) neu bebildert. Eingehängt in PlayerControlView
//  (grosser Player) und MiniPlayerView (Leiste auf iPad).
//
//  This program is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//

import AVFAudio
import UIKit

@MainActor
final class HLAusgabe {
  static let shared = HLAusgabe()

  /// Was der Knopf zeigen soll.
  struct Anzeige: Equatable {
    var symbole: [String]   // erster vorhandener SF-Symbol-Name gewinnt
    var name: String?       // Gerätename für VoiceOver, nil beim eingebauten Lautsprecher
    var extern: Bool        // true: Akzentfarbe
  }

  private let knoepfe = NSHashTable<UIButton>.weakObjects()
  private var beobachtet = false

  /// Knopf anmelden; er zeigt ab jetzt das aktuelle Ausgabegerät.
  func beobachten(_ knopf: UIButton) {
    #if targetEnvironment(macCatalyst)
      return   // am Mac wählt man die Ausgabe im System, dort bleibt das AirPlay-Zeichen
    #else
      knoepfe.add(knopf)
      if !beobachtet {
        beobachtet = true
        let nc = NotificationCenter.default
        for name in [AVAudioSession.routeChangeNotification, UIApplication.didBecomeActiveNotification] {
          nc.addObserver(forName: name, object: nil, queue: .main) { _ in
            Task { @MainActor in HLAusgabe.shared.aktualisieren() }
          }
        }
      }
      zeigen(aktuell(), auf: knopf)
    #endif
  }

  func aktualisieren() {
    let anzeige = aktuell()
    for knopf in knoepfe.allObjects { zeigen(anzeige, auf: knopf) }
  }

  private func aktuell() -> Anzeige {
    #if DEBUG
      // Zum Ansehen im Simulator: -homelabmusic.ausgabeTest "BluetoothA2DPOutput|AirPods Pro von Patrick"
      if let test = UserDefaults.standard.string(forKey: "homelabmusic.ausgabeTest") {
        let teile = test.split(separator: "|", maxSplits: 1).map(String.init)
        return Self.anzeige(art: AVAudioSession.Port(rawValue: teile[0]), name: teile.count > 1 ? teile[1] : "", anzahl: 1)
      }
    #endif
    let ausgaben = AVAudioSession.sharedInstance().currentRoute.outputs
    guard let erste = ausgaben.first else { return Self.standard }
    return Self.anzeige(art: erste.portType, name: erste.portName, anzahl: ausgaben.count)
  }

  static let standard = Anzeige(symbole: ["airplayaudio"], name: nil, extern: false)

  /// Symbol je Art der Ausgabe; bei Bluetooth und AirPlay entscheidet der Gerätename.
  static func anzeige(art: AVAudioSession.Port, name: String, anzahl: Int) -> Anzeige {
    let n = name.lowercased()
    func hat(_ woerter: String...) -> Bool { woerter.contains { n.contains($0) } }
    // ganze Wörter, damit «Audio» nicht als Audi und «Oscar» nicht als Car gilt
    let ganze = Set(n.split { !$0.isLetter && !$0.isNumber }.map(String.init))
    func wort(_ woerter: String...) -> Bool { woerter.contains { ganze.contains($0) } }
    let symbole: [String]
    switch art {
    case .builtInSpeaker, .builtInReceiver:
      return standard
    case .headphones:
      symbole = ["headphones"]
    case .bluetoothA2DP, .bluetoothLE, .bluetoothHFP:
      if hat("airpods max") { symbole = ["airpods.max", "airpodsmax", "headphones"] }
      else if hat("airpods pro") { symbole = ["airpods.pro", "airpodspro", "airpods"] }
      else if hat("airpods") { symbole = ["airpods.gen3", "airpods"] }
      else if hat("powerbeats", "beats flex", "beats fit", "studio buds", "solo buds", "beatsx") {
        symbole = ["beats.earphones", "earbuds", "headphones"]
      } else if hat("beats") { symbole = ["beats.headphones", "headphones"] }
      else if hat("buds", "earbuds", "earfun", "freebuds", "linkbuds", "wf-") { symbole = ["earbuds", "headphones"] }
      else if hat("speaker", "lautsprecher", "boom", "soundlink", "flip", "charge", "xtreme", "sonos", "roam",
                  "soundbar", "box", "stanmore", "emberton", "echo") { symbole = ["hifispeaker"] }
      else if wort("car", "auto", "audi", "bmw", "vw", "skoda", "seat", "tesla", "mercedes", "toyota", "volvo",
                   "ford", "renault", "peugeot", "opel", "mazda", "hyundai", "kia", "cupra", "uconnect", "mmi",
                   "carplay") { symbole = ["car"] }
      else if hat("hearing", "hörger") { symbole = ["hearingdevice.ear", "headphones"] }
      else { symbole = ["headphones"] }   // unbekanntes Bluetooth-Gerät: meistens Kopfhörer
    case .airPlay:
      if anzahl > 1 { symbole = ["hifispeaker.2", "hifispeaker"] }
      else if hat("homepod mini") { symbole = ["homepodmini", "homepod"] }
      else if hat("homepod") { symbole = ["homepod", "hifispeaker"] }
      else if hat("apple tv", "appletv", "wohnzimmer tv") { symbole = ["appletv", "tv"] }
      else if hat("tv", "fernseh") { symbole = ["tv"] }
      else { symbole = ["hifispeaker"] }
    case .carAudio:
      symbole = ["car"]
    case .HDMI, .displayPort, .AVB:
      symbole = ["tv"]
    case .usbAudio, .lineOut, .thunderbolt, .fireWire, .PCI, .virtual:
      symbole = ["cable.connector", "hifispeaker"]
    default:
      symbole = ["hifispeaker"]
    }
    return Anzeige(symbole: symbole + ["airplayaudio"], name: name.isEmpty ? nil : name, extern: true)
  }

  private func zeigen(_ anzeige: Anzeige, auf knopf: UIButton) {
    guard let bild = anzeige.symbole.lazy.compactMap({ UIImage(systemName: $0) }).first else { return }
    // Grösse des bisherigen Zeichens behalten (XIB: Skalierung «medium», Mini-Player: feste Punktgrösse)
    if var config = knopf.configuration {
      let alt = config.image?.symbolConfiguration ?? UIImage.SymbolConfiguration(scale: .medium)
      config.image = bild.withConfiguration(alt)
      knopf.configuration = config
    } else {
      let alt = knopf.image(for: .normal)?.symbolConfiguration ?? UIImage.SymbolConfiguration(scale: .medium)
      knopf.setImage(bild.withConfiguration(alt), for: .normal)
    }
    // nil = Akzentfarbe der App erben; der eingebaute Lautsprecher bleibt unauffällig wie die Nachbarknöpfe
    knopf.tintColor = anzeige.extern ? nil : .label
    knopf.accessibilityLabel = "Ausgabe wählen"
    knopf.accessibilityValue = anzeige.name ?? "iPhone"
  }
}
