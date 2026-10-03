//
//  HLCover.swift
//  HomeLabMusic
//
//  Playlist-Cover von Navidrome statt Amperfys Mosaik aus den ersten vier Songs: Navidrome liefert das
//  hochgeladene Bild (z. B. die Wochenmix-Cover) und sonst ein eigenes Mosaik. Zwischengespeichert
//  für die Laufzeit der App.
//
//  This program is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//

import AmperfyKit
import UIKit

@MainActor
enum HLCover {
  private static let speicher = NSCache<NSString, UIImage>()
  private static var fehlgeschlagen = Set<String>()

  static func einrichten() {
    EntityImageView.playlistCover = { id in await bild(id) }
  }

  private static func bild(_ id: String) async -> UIImage? {
    if let b = speicher.object(forKey: id as NSString) { return b }
    guard !id.isEmpty, !fehlgeschlagen.contains(id),
          let url = HLAPI.shared.subsonicURL("getCoverArt", ["id": "pl-\(id)", "size": "600"]) else { return nil }
    guard let (daten, antwort) = try? await URLSession.shared.data(from: url),
          (antwort as? HTTPURLResponse)?.statusCode == 200,
          (antwort as? HTTPURLResponse)?.mimeType?.hasPrefix("image") == true,
          let b = UIImage(data: daten) else {
      fehlgeschlagen.insert(id)                        // nicht bei jeder Anzeige erneut versuchen
      return nil
    }
    speicher.setObject(b, forKey: id as NSString)
    return b
  }
}
