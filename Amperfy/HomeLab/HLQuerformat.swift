//
//  HLQuerformat.swift
//  HomeLabMusic
//
//  Querformat nur für den Player (PLAN-musik-erlebnis.md, Etappe F). Das iPhone bleibt überall im Hochformat;
//  solange der Player offen ist, darf es sich drehen. Im Querformat zeigt der Player links gross das Cover und
//  rechts Titel, Künstler, Album und Amperfys eigene Steuerung (Zeitleiste, Knöpfe). Die Steuerung wird dafür
//  nur umgehängt, nicht verdoppelt: Amperfy frischt sie weiter selbst auf. Der Knopf «Songtext» zeigt links statt
//  des Covers Amperfys Songtext-Ansicht (LyricsVC, mitlaufend bei Zeitmarken; Etappe L).
//
//  This program is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//

import AmperfyKit
import UIKit

@MainActor
enum HLQuerformat {
  private static var playerOffen = false

  /// Für AppDelegate.application(_:supportedInterfaceOrientationsFor:).
  static var maske: UIInterfaceOrientationMask {
    guard UIDevice.current.userInterfaceIdiom == .phone else { return .all }
    return playerOffen ? .allButUpsideDown : .portrait
  }

  static func player(offen: Bool, _ vc: UIViewController) {
    guard UIDevice.current.userInterfaceIdiom == .phone, playerOffen != offen else { return }
    playerOffen = offen
    let szene = vc.view.window?.windowScene
    for x in [vc, vc.presentingViewController, vc.view.window?.rootViewController] {
      x?.setNeedsUpdateOfSupportedInterfaceOrientations()
    }
    UIDevice.current.beginGeneratingDeviceOrientationNotifications()
    guard let szene else { return }
    if !offen, szene.interfaceOrientation.isLandscape {
      szene.requestGeometryUpdate(.iOS(interfaceOrientations: .portrait)) { _ in }
    } else if offen, UIDevice.current.orientation.isLandscape {
      // Gerät liegt schon quer: sofort drehen, nicht erst bei der nächsten Bewegung
      // (Gerät «links» = Oberfläche «rechts»)
      let ziel: UIInterfaceOrientationMask = UIDevice.current.orientation == .landscapeLeft
        ? .landscapeRight : .landscapeLeft
      szene.requestGeometryUpdate(.iOS(interfaceOrientations: ziel)) { _ in }
    }
  }
}

@MainActor
final class HLQuerformatEinbau {
  private weak var vc: PopupPlayerVC?
  private let huelle = UIView()
  private let cover = LibraryEntityImage(frame: .zero)
  private let titel = UILabel()
  private let kuenstler = UILabel()
  private let album = UILabel()
  private let steuerPlatz = UIView()
  private let schliessen = UIButton(type: .system)
  private let songtextKnopf = UIButton(type: .system)
  private var songtext: LyricsVC?
  private var songtextAn = false
  private var versteckt: [UIView: Bool] = [:]
  private(set) var aktiv = false

  init(vc: PopupPlayerVC) {
    self.vc = vc
    huelle.isHidden = true
    huelle.backgroundColor = .clear
    cover.layer.cornerRadius = 12
    cover.clipsToBounds = true
    titel.font = .systemFont(ofSize: 24, weight: .bold)
    titel.adjustsFontSizeToFitWidth = true
    titel.minimumScaleFactor = 0.7
    kuenstler.font = .systemFont(ofSize: 19, weight: .regular)
    album.font = .systemFont(ofSize: 15)
    album.textColor = .secondaryLabel
    for l in [titel, kuenstler, album] {
      l.textColor = l === album ? .secondaryLabel : .label
      l.lineBreakMode = .byTruncatingTail
    }
    schliessen.setImage(UIImage(systemName: "chevron.down"), for: .normal)
    schliessen.tintColor = .label
    schliessen.accessibilityLabel = "Player schliessen"
    schliessen.addAction(UIAction { [weak vc] _ in vc?.dismiss(animated: true) }, for: .touchUpInside)
    songtextKnopf.tintColor = .label
    songtextKnopf.accessibilityLabel = "Songtext"
    songtextKnopf.addAction(UIAction { [weak self] _ in self?.songtextUmschalten() }, for: .touchUpInside)
    knopfBild()
    for v in [cover, titel, kuenstler, album, steuerPlatz, schliessen, songtextKnopf] as [UIView] {
      huelle.addSubview(v)
    }
    vc.view.addSubview(huelle)
  }

  /// Aus viewDidLayoutSubviews: wechselt bei Drehung und legt die Ansicht an die neue Grösse an.
  func anpassen() {
    guard let vc else { return }
    let b = vc.view.bounds
    let quer = UIDevice.current.userInterfaceIdiom == .phone && b.width > b.height
    if quer != aktiv {
      aktiv = quer
      wechseln(vc)
    }
    guard aktiv else { return }
    huelle.frame = b
    vc.view.bringSubviewToFront(huelle)
    let s = b.inset(by: vc.view.safeAreaInsets).insetBy(dx: 16, dy: 12)
    let seite = min(s.height, s.width * 0.45)
    cover.frame = CGRect(x: s.minX, y: s.midY - seite / 2, width: seite, height: seite)
    schliessen.frame = CGRect(x: b.maxX - vc.view.safeAreaInsets.right - 52, y: s.minY - 4, width: 44, height: 44)
    songtextKnopf.frame = schliessen.frame.offsetBy(dx: -48, dy: 0)
    cover.isHidden = songtextAn
    songtext?.view.isHidden = !songtextAn
    if songtextAn, let l = songtext {
      l.view.frame = CGRect(x: s.minX, y: s.minY, width: s.width * 0.45, height: s.height)
    }
    let x = (songtextAn ? s.minX + s.width * 0.45 : cover.frame.maxX) + 28
    let w = s.maxX - x
    let steuerHoehe = min(PlayerControlView.frameHeight, s.height - 90)
    let gesamt = 34 + 26 + 22 + 10 + steuerHoehe
    var y = s.midY - gesamt / 2
    titel.frame = CGRect(x: x, y: y, width: w - 92, height: 34); y += 34
    kuenstler.frame = CGRect(x: x, y: y, width: w, height: 26); y += 26
    album.frame = CGRect(x: x, y: y, width: w, height: 22); y += 22 + 10
    steuerPlatz.frame = CGRect(x: x - 8, y: y, width: w + 16, height: steuerHoehe)
    vc.controlView?.frame = steuerPlatz.bounds
  }

  private func knopfBild() {
    songtextKnopf.setImage(UIImage(systemName: songtextAn ? "quote.bubble.fill" : "quote.bubble"), for: .normal)
  }

  /// Songtext statt Cover (und zurück). Die Ansicht entsteht beim ersten Mal und bleibt danach bestehen.
  private func songtextUmschalten() {
    guard let vc else { return }
    songtextAn.toggle()
    knopfBild()
    if songtextAn, songtext == nil {
      let l = LyricsVC()
      vc.addChild(l)
      huelle.addSubview(l.view)
      l.didMove(toParent: vc)
      songtext = l
    }
    if songtextAn { songtext?.refreshLyrics() }
    anpassen()
  }

  /// Aus refreshCurrentlyPlayingInfoView / refreshCurrentlyPlayingArtworks.
  func auffrischen() {
    guard aktiv, let vc else { return }
    if songtextAn { songtext?.refreshLyrics() }
    vc.playerHandler?.refreshCurrentlyPlayingInfo(
      artworkImage: cover, titleLabel: titel, artistLabel: kuenstler, albumLabel: album
    )
  }

  private func wechseln(_ vc: PopupPlayerVC) {
    let amperfy: [UIView] = [vc.tableView, vc.largePlayerPlaceholderView, vc.controlPlaceholderView]
    if aktiv {
      for v in amperfy {
        versteckt[v] = v.isHidden
        v.isHidden = true
      }
      if let c = vc.controlView {
        c.removeFromSuperview()
        steuerPlatz.addSubview(c)
      }
      huelle.isHidden = false
      auffrischen()
    } else {
      huelle.isHidden = true
      for v in amperfy {
        v.isHidden = versteckt[v] ?? false
      }
      if let c = vc.controlView {
        c.removeFromSuperview()
        vc.controlPlaceholderView.addSubview(c)
        c.frame = CGRect(origin: .zero, size: vc.controlPlaceholderView.bounds.size)
      }
      vc.refresh()
    }
    vc.controlView?.refreshView()
  }
}
