//
//  HLListenFilter.swift
//  HomeLabMusic
//
//  Die eine Stelle, die entscheidet, was Amperfys Listen zeigen (Haken `hlListenFilter` /
//  `hlListenSortierung` in AmperfyKit, BasicFetchedResultsController.swift):
//
//  1. Bibliothek (HLBibliothek): Musik oder Kinder, dazu fremde Playlists und die Mediathek-Playlist ausblenden.
//  2. Mediathek (HLMediathek): im Modus «Mediathek» nur, was der Person gehört –
//     Songs, Alben und Künstler mit mindestens einem eigenen Song, Genres mit eigenen Songs.
//     Ausgenommen: Suche (findet alles), Favoriten, «Zuletzt gehört», Verzeichnisse und die Detailseiten von
//     Album und Künstler (zeigen alles, Eigenes markiert, Rest mit «+»).
//     «Newest Albums» heisst dort: zuletzt in die Mediathek gekommen (Album.hlMediathekSeit absteigend).
//     Solange es für das Konto noch keine Mediathek gibt, zeigt der Modus alles (wie bisher).
//
//  This program is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//

import AmperfyKit
import CoreData
import Foundation

enum HLListenFilter {
  /// Mediathek-Filter aktiv (Modus Mediathek und die Mediathek des Kontos ist bekannt). Wird auf dem Main-Thread
  /// gesetzt und aus beliebigen Kontexten gelesen (wie HLBibliothek.filter).
  nonisolated(unsafe) static var mediathekAktiv = false

  static func einrichten() {
    hlListenFilter = { entitaet, basis, suche in praedikat(entitaet: entitaet, basis: basis, suche: suche) }
    hlListenSortierung = { entitaet, basis in sortierung(entitaet: entitaet, basis: basis) }
  }

  /// Nach jeder Änderung an Bibliothekswahl oder Mediathek: Listen bauen ihre Anfragen beim nächsten Laden neu.
  static func neuBerechnet() {
    hlFilterStand += 1
  }

  // MARK: Prädikat

  static func praedikat(entitaet: String, basis: NSPredicate?, suche: Bool) -> NSPredicate? {
    var teile = [NSPredicate]()
    var basis = basis
    if let bib = HLBibliothek.filter[entitaet] { teile.append(bib) }
    if mediathekAktiv, !suche, let m = mediathek(entitaet: entitaet, basis: basis) {
      teile.append(m)
      // «Newest Albums»: nicht die 50 neuesten des Servers, sondern alle eigenen (Sortierung siehe unten)
      if entitaet == "Album", let b = basis { basis = ohne(schluessel: "newestIndex", in: b) }
    }
    guard !teile.isEmpty else { return nil }
    return NSCompoundPredicate(andPredicateWithSubpredicates: [basis].compactMap { $0 } + teile)
  }

  /// Mediathek-Bedingung je Entität, nil wo die Liste nicht gefiltert wird.
  private static func mediathek(entitaet: String, basis: NSPredicate?) -> NSPredicate? {
    let schluessel = basis.map(vergleiche) ?? []
    // Favoriten und «Zuletzt gehört» bleiben, wie sie sind (pro Person auf dem Server)
    if schluessel.contains(where: { $0.pfad == "isFavorite" || $0.pfad == "recentIndex" }) { return nil }
    switch entitaet {
    case "Song":
      // Detailseiten von Album und Künstler zeigen alles; Verzeichnisse sind im Modus ausgeblendet
      if schluessel.contains(where: { ["album", "artist", "directory"].contains($0.pfad) }) { return nil }
      return NSPredicate(format: "hlInMediathek == YES")
    case "Album":
      if schluessel.contains(where: { $0.pfad == "artist" }) { return nil }   // Künstler-Detail
      return NSPredicate(format: "hlMediathekSeit != nil")
    case "Artist":
      return NSPredicate(format: "hlInMediathek == YES")
    case "Genre":
      return NSPredicate(format: "SUBQUERY(songs, $s, $s.hlInMediathek == YES).@count > 0")
    default:
      return nil
    }
  }

  // MARK: Einträge der Bibliothek

  /// Einträge der Library-Liste: im Modus Mediathek ohne Verzeichnisse (Ordner zeigen immer alles).
  @MainActor
  static func sichtbar(_ eintraege: [LibraryDisplayType]) -> [LibraryDisplayType] {
    guard mediathekAktiv else { return eintraege }
    return eintraege.filter { $0 != .directories }
  }

  // MARK: Sortierung

  static func sortierung(entitaet: String, basis: [NSSortDescriptor]) -> [NSSortDescriptor]? {
    guard mediathekAktiv, entitaet == "Album", basis.first?.key == "newestIndex" else { return nil }
    return [NSSortDescriptor(key: "hlMediathekSeit", ascending: false)] + basis.dropFirst()
  }

  // MARK: Prädikate lesen

  private struct Vergleich {
    var pfad: String
  }

  /// Schlüssel aller einfachen Vergleiche in einem (zusammengesetzten) Prädikat.
  private static func vergleiche(_ p: NSPredicate) -> [Vergleich] {
    if let c = p as? NSCompoundPredicate {
      return (c.subpredicates as? [NSPredicate] ?? []).flatMap(vergleiche)
    }
    guard let v = p as? NSComparisonPredicate, v.leftExpression.expressionType == .keyPath else { return [] }
    return [Vergleich(pfad: v.leftExpression.keyPath)]
  }

  /// Prädikat ohne die Vergleiche mit diesem Schlüssel (durch «wahr» ersetzt).
  private static func ohne(schluessel: String, in p: NSPredicate) -> NSPredicate {
    if let c = p as? NSCompoundPredicate {
      let teile = (c.subpredicates as? [NSPredicate] ?? []).map { ohne(schluessel: schluessel, in: $0) }
      return NSCompoundPredicate(type: c.compoundPredicateType, subpredicates: teile)
    }
    if let v = p as? NSComparisonPredicate, v.leftExpression.expressionType == .keyPath,
       v.leftExpression.keyPath == schluessel {
      return NSPredicate(value: true)
    }
    return p
  }
}
