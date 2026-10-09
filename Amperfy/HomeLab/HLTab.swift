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
}
