//
//  HLTab.swift
//  HomeLabMusic
//
//  «Entdecken»: Tab in der Tab-Leiste (TabBarVC), auf dem Mac Eintrag in der Seitenleiste (SideBarVC).
//
//  This program is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//

import AmperfyKit
import SwiftUI
import UIKit

@MainActor
enum HLTab {
  private static var eingerichtet = false

  /// Einmal pro App-Start: Konto, Player-Haken, Cover, Benachrichtigungen.
  static func einrichten(account: Account) {
    HLAPI.shared.account = account
    guard !eingerichtet else { return }
    eingerichtet = true
    HLPlayer.shared.aufraeumenBeimStart()
    HLCover.einrichten()
    HLBenachrichtigung.starten()
    HLPlayer.hakenEinrichten()
    HLBibliothek.shared.einrichten()
    HLSpeicher.einrichten()
  }

  /// iPhone/iPad: Tab in der Tab-Leiste.
  static func erstellen(account: Account) -> UITab {
    einrichten(account: account)
    return UITab(
      title: "Entdecken",
      image: UIImage(systemName: "sparkles"),
      identifier: "Tabs.Entdecken"
    ) { _ in
      ansicht()
    }
  }

  /// Mac: Eintrag in der Seitenleiste (SideBarVC / TabNavigatorItem.entdecken).
  static func ansicht() -> UIViewController {
    UIHostingController(rootView: HLEntdeckenView())
  }

  /// Künstler, Album oder Mix aus der Suche, dem Mini-Player oder einer Amperfy-Seite: Seite im UIKit-Stapel
  /// statt im NavigationStack des Tabs. Weitere Ziele kommen auf denselben Stapel.
  static func zielAnsicht(_ ziel: HLZiel) -> UIViewController {
    if case let .bibliothek(name) = ziel {
      return bibliotheksSeite(kuenstler: name) ?? UIHostingController(rootView: Text("Nicht in der Bibliothek"))
    }
    let box = HLSchwach()
    let oeffnen: @MainActor (HLZiel) -> () = { weiter in
      box.vc?.navigationController?.pushViewController(zielAnsicht(weiter), animated: true)
    }
    let ansicht = HLZielView(ziel: ziel)
      .environment(\.hlOeffnen, oeffnen)
      .modifier(HLSpielRahmen())
    let host = UIHostingController(rootView: ansicht)
    host.navigationItem.largeTitleDisplayMode = .never
    box.vc = host
    return host
  }

  /// Amperfys Künstlerseite zu einem Namen aus Entdecken (gleicher Name, Gross/klein und Akzente egal).
  static func bibliotheksSeite(kuenstler name: String) -> UIViewController? {
    guard let account = HLAPI.shared.account else { return nil }
    let bib = (UIApplication.shared.delegate as! AppDelegate).storage.main.library
    let gesucht = HLDeezer.norm(name)
    let treffer = bib.searchArtists(for: account, searchText: name, onlyCached: false, displayFilter: .all)
      .first { HLDeezer.norm($0.name) == gesucht }
    guard let treffer else { return nil }
    return AppStoryboard.Main.segueToArtistDetail(account: account, artist: treffer)
  }

  /// Aus dem SwiftUI-Tab heraus: Amperfy zeigt die Seite im Tab «Library».
  static func bibliothekOeffnen(kuenstler name: String) {
    guard let vc = bibliotheksSeite(kuenstler: name) else {
      HLPlayer.shared.zeigeHinweis("Nicht in deiner Bibliothek gefunden.")
      return
    }
    AppDelegate.mainWindowHostVC?.pushNavLibrary(vc: vc)
  }

  /// Ziel aus dem Mini-Player: im Tab, der gerade offen ist (Entdecken: eigener Stapel, sonst Amperfys
  /// UINavigationController). Auf dem Mac (Seitenleiste) wie Amperfys eigene Sprünge über «Library».
  static func ausMiniPlayerOeffnen(_ ziel: HLZiel) {
    if let leiste = AppDelegate.mainWindowHostVC as? UITabBarController {
      if leiste.selectedTab?.identifier == "Tabs.Entdecken" {
        HLNavigation.shared.oeffnen(ziel)
        return
      }
      let gewaehlt = leiste.selectedViewController
      if let nav = gewaehlt as? UINavigationController ?? gewaehlt?.navigationController {
        nav.pushViewController(zielAnsicht(ziel), animated: true)
        return
      }
    }
    AppDelegate.mainWindowHostVC?.pushNavLibrary(vc: zielAnsicht(ziel))
  }
}

/// Schwacher Verweis auf eine Seite, die beim Erstellen ihres eigenen Öffnen-Befehls noch nicht existiert.
@MainActor
final class HLSchwach {
  weak var vc: UIViewController?
}
