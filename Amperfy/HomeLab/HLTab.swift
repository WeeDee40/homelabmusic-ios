//
//  HLTab.swift
//  HomeLabMusic
//
//  Tab «Entdecken» für die Tab-Leiste (eingebunden in TabBarVC).
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
  static func erstellen(account: Account) -> UITab {
    HLAPI.shared.account = account
    HLPlayer.shared.aufraeumenBeimStart()
    return UITab(
      title: "Entdecken",
      image: UIImage(systemName: "sparkles"),
      identifier: "Tabs.Entdecken"
    ) { _ in
      UIHostingController(rootView: HLEntdeckenView())
    }
  }
}
