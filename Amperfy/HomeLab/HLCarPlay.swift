//
//  HLCarPlay.swift
//  HomeLabMusic
//
//  Bilder in CarPlay: Amperfy zeigt dort für Playlists und Radios nur Platzhalter.
//  Die CarPlay-Listen rufen nach dem Anlegen eines Eintrags `nachladen` auf; das Bild
//  wird dann nachträglich gesetzt (Playlist-Cover von Navidrome, Senderbild von Navidrome).
//

import AmperfyKit
import CarPlay
import UIKit

@MainActor
enum HLCarPlay {
  /// Lädt das Bild für Playlist oder Radio und übergibt es an `setzen` (nur, wenn es eines gibt).
  static func nachladen(
    _ eintrag: Any,
    traits: UITraitCollection,
    setzen: @escaping @MainActor (UIImage) -> ()
  ) {
    let quelle: (() async -> UIImage?)?
    if let playlist = eintrag as? Playlist, let cover = EntityImageView.playlistCover {
      let id = playlist.id
      quelle = { await cover(id) }
    } else if let radio = eintrag as? Radio, !radio.id.hasPrefix(HLPlayer.radioPraefix) {
      let id = radio.id
      quelle = { await HLPlayer.shared.senderBild(id) }
    } else {
      quelle = nil
    }
    guard let quelle else { return }
    Task { @MainActor in
      if let bild = await quelle() { setzen(bild.carPlayImage(carTraitCollection: traits)) }
    }
  }
}
