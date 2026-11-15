//
//  HLMiniKnopf.swift
//  HomeLabMusic
//
//  Eine Leiste für den laufenden Song: Amperfys Mini-Player bekommt bei Vorschauen einen Wunsch-Knopf
//  («+», wie Spotifys Hinzufügen) und beim langen Drücken ein Menü (Künstler ansehen, Mix ab diesem Song).
//  Vorher zeigte Entdecken eine eigene Leiste über Amperfys Mini-Player (bis Build 28).
//
//  This program is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//

import AmperfyKit
import Combine
import UIKit

@MainActor
final class HLMiniKnopf: UIButton {
  private var beobachter: AnyCancellable?
  private let menueDelegate = HLMiniMenue()
  private lazy var breite = widthAnchor.constraint(equalToConstant: 0)
  private var player: PlayerFacade { (UIApplication.shared.delegate as! AppDelegate).player }

  /// Knopf vor dem Abspielknopf einsetzen; Titel und Untertitel enden danach am Knopf statt am Abspielknopf.
  static func einbauen(in miniPlayer: UIView, vor playButton: UIView) -> HLMiniKnopf {
    let knopf = HLMiniKnopf(frame: .zero)
    knopf.translatesAutoresizingMaskIntoConstraints = false
    miniPlayer.addSubview(knopf)
    NSLayoutConstraint.activate([
      knopf.centerYAnchor.constraint(equalTo: playButton.centerYAnchor),
      knopf.heightAnchor.constraint(equalToConstant: 30),
      knopf.trailingAnchor.constraint(equalTo: playButton.leadingAnchor, constant: -6),
      knopf.breite,
    ])
    miniPlayer.addInteraction(UIContextMenuInteraction(delegate: knopf.menueDelegate))
    knopf.aktualisieren()
    return knopf
  }

  override init(frame: CGRect) {
    super.init(frame: frame)
    accessibilityLabel = "Zur Bibliothek hinzufügen"
    addAction(UIAction { [weak self] _ in
      guard let self else { return }
      _ = HLPlayer.shared.vorschauWuenschen(player.currentlyPlaying)
    }, for: .touchUpInside)
    beobachter = HLPlayer.shared.objectWillChange.sink { [weak self] _ in
      DispatchQueue.main.async { self?.aktualisieren() }   // objectWillChange kommt vor der Änderung
    }
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  /// Nur bei Vorschauen sichtbar: «+» zum Wünschen, Sanduhr wenn gewünscht, Haken wenn schon da.
  func aktualisieren() {
    guard let k = HLPlayer.shared.vorschauKnopf(player.currentlyPlaying) else {
      isHidden = true
      breite.constant = 0
      return
    }
    setImage(
      UIImage(systemName: k.bild, withConfiguration: UIImage.SymbolConfiguration(pointSize: 24)),
      for: .normal
    )
    tintColor = k.farbe
    isHidden = false
    breite.constant = 30
  }
}

// MARK: - Menü beim langen Drücken auf den Mini-Player

final class HLMiniMenue: NSObject, UIContextMenuInteractionDelegate {
  private var player: PlayerFacade { (UIApplication.shared.delegate as! AppDelegate).player }

  func contextMenuInteraction(
    _ interaction: UIContextMenuInteraction,
    configurationForMenuAtLocation location: CGPoint
  )
    -> UIContextMenuConfiguration? {
    menue()
  }

  /// Vorschauen und Songs, die über Entdecken laufen. Bibliotheks-Songs haben Amperfys Menü im Player.
  private func menue() -> UIContextMenuConfiguration? {
    guard let s = HLPlayer.shared.vorschau(player.currentlyPlaying) ?? HLPlayer.shared.aktuell
    else { return nil }
    var aktionen = [UIMenuElement]()
    if let k = s.kuenstlerId {
      aktionen.append(UIAction(title: "Künstler ansehen", image: UIImage(systemName: "person")) { _ in
        HLTab.ausMiniPlayerOeffnen(.kuenstler(k))
      })
    }
    if let a = s.albumId {
      aktionen.append(UIAction(title: "Album ansehen", image: UIImage(systemName: "square.stack")) { _ in
        HLTab.ausMiniPlayerOeffnen(.album(a))
      })
    }
    if let id = s.deezerId {
      aktionen.append(UIAction(title: "Mix ab diesem Song", image: UIImage(systemName: "dot.radiowaves.left.and.right")) { _ in
        HLTab.ausMiniPlayerOeffnen(.sender(art: "song", id: "\(id)"))
      })
    } else if let nd = s.navidromeId {
      aktionen.append(UIAction(title: "Mix ab diesem Song", image: UIImage(systemName: "dot.radiowaves.left.and.right")) { _ in
        HLTab.ausMiniPlayerOeffnen(.sender(art: "navidrome", id: nd))
      })
    }
    if let nd = s.navidromeId { aktionen.append(contentsOf: HLMediathekUI.menue(navidromeId: nd)) }
    aktionen.append(UIAction(
      title: "Nicht mein Ding",
      image: UIImage(systemName: "hand.thumbsdown"),
      attributes: .destructive
    ) { _ in HLPlayer.shared.ablehnen(s) })
    return UIContextMenuConfiguration(actionProvider: { _ in UIMenu(children: aktionen) })
  }
}
