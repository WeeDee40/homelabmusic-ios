//
//  HLSplash.swift
//  HomeLabMusic
//
//  Startbild nach dem Systemstart noch kurz stehen lassen und weich ausblenden, damit man es wahrnimmt
//  (der Startbildschirm selbst ist oft nur Sekundenbruchteile sichtbar).
//
//  This program is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//

import UIKit

@MainActor
enum HLSplash {
  static let stehen: TimeInterval = 0.8
  static let ausblenden: TimeInterval = 0.4

  static func zeigen(in fenster: UIWindow?) {
    guard let fenster, let bild = UIImage(named: "HLStart") else { return }
    let ansicht = UIImageView(image: bild)
    ansicht.contentMode = .scaleAspectFill
    ansicht.clipsToBounds = true
    ansicht.frame = fenster.bounds
    ansicht.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    fenster.addSubview(ansicht)
    UIView.animate(withDuration: ausblenden, delay: stehen, options: [.curveEaseOut]) {
      ansicht.alpha = 0
      ansicht.transform = CGAffineTransform(scaleX: 1.04, y: 1.04)
    } completion: { _ in
      ansicht.removeFromSuperview()
    }
  }
}
