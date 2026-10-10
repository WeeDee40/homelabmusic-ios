//
//  HLBibliothek.swift
//  HomeLabMusic
//
//  Navidrome-Bibliotheken unterscheiden («Meine Musik» / «Kinder»), wie in NaviBeat.
//  Amperfy kennt nur eine gemeinsame Bibliothek. Wir holen pro Navidrome-Bibliothek die Album- und
//  Künstler-IDs (Subsonic getAlbumList2 / getArtists mit musicFolderId) und filtern damit Amperfys
//  Listen (Haken `hlBibliotheksFilter` in AmperfyKit). Umschalten baut die Oberfläche neu auf,
//  genau wie Amperfys eigener Kontowechsel. Im Kinder-Modus ist die App orange eingefärbt.
//
//  This program is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//

import AmperfyKit
import CoreData
import UIKit

@MainActor
final class HLBibliothek {
  static let shared = HLBibliothek()

  struct Bib: Codable, Equatable {
    let id: String
    let name: String
    var alben: [String]
    var kuenstler: [String]

    var istKinder: Bool { name.localizedCaseInsensitiveContains("kind") }
  }

  static let kinderFarbe = UIColor.systemOrange
  private static let auswahlSchluessel = "homelabmusic.bibliothek"

  private(set) var bibliotheken: [Bib] = []
  private var aktualisiert = false
  private var themaGesetzt = false
  private var knoepfe = [WeakNavItem]()

  private struct WeakNavItem { weak var item: UINavigationItem? }

  private var datei: URL {
    FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("hl-bibliotheken.json")
  }

  /// Die grösste Bibliothek ist «Meine Musik».
  private var haupt: Bib? { bibliotheken.max { $0.alben.count < $1.alben.count } }

  /// Gewählte Bibliothek; ohne Wahl «Meine Musik». Nil, wenn es nur eine Bibliothek gibt.
  var gewaehlt: Bib? {
    guard bibliotheken.count > 1 else { return nil }
    let id = UserDefaults.standard.string(forKey: Self.auswahlSchluessel)
    return bibliotheken.first { $0.id == id } ?? haupt
  }

  var istKinderModus: Bool { gewaehlt?.istKinder ?? false }

  func anzeigename(_ bib: Bib) -> String {
    if bib.istKinder { return "Kinder" }
    if bib.id == haupt?.id { return "Meine Musik" }
    return bib.name
  }

  func symbol(_ bib: Bib) -> String {
    if bib.istKinder { return "figure.and.child.holdinghands" }
    if bib.id == haupt?.id { return "person.fill" }
    return "books.vertical"
  }

  // MARK: Start und Laden

  func einrichten() {
    if let daten = try? Data(contentsOf: datei),
       let gespeichert = try? JSONDecoder().decode([Bib].self, from: daten) {
      bibliotheken = gespeichert
    }
    hlBibliotheksFilter = { entitaet in HLBibliothek.filter[entitaet] }
    filterBerechnen()
    guard !aktualisiert else { return }
    aktualisiert = true
    Task { await aktualisieren() }
  }

  /// Album- und Künstler-IDs je Bibliothek von Navidrome holen.
  func aktualisieren() async {
    guard let antwort = await HLAPI.shared.subsonic("getMusicFolders"),
          let ordner = (antwort["musicFolders"] as? [String: Any])?["musicFolder"] as? [[String: Any]]
    else { return }
    var neu = [Bib]()
    for o in ordner {
      guard let id = (o["id"] as? Int).map(String.init) ?? o["id"] as? String else { continue }
      let name = o["name"] as? String ?? id
      guard let (alben, kuenstler) = await albenUndKuenstler(id) else { return }
      neu.append(Bib(id: id, name: name, alben: alben, kuenstler: kuenstler))
    }
    guard neu != bibliotheken else { return }
    let vorher = bibliotheken.map(\.id)
    let ersteLadung = bibliotheken.isEmpty
    bibliotheken = neu
    if let daten = try? JSONEncoder().encode(neu) { try? daten.write(to: datei) }
    filterBerechnen()
    if ersteLadung, neu.count > 1, let info = appDelegate.storage.settings.accounts.active {
      appDelegate.switchAccount(accountInfo: info) // erster Start: Listen gleich gefiltert neu laden
    } else if vorher != neu.map(\.id) {
      knoepfeAktualisieren()
    }
  }

  /// Album-IDs und Künstler-IDs (Album-Künstler) einer Bibliothek. Künstler werden aus den Alben
  /// abgeleitet: Navidromes getArtists führt nach dem Verschieben von Ordnern teils alte Zuordnungen.
  private func albenUndKuenstler(_ ordner: String) async -> ([String], [String])? {
    var alben = [String]()
    var kuenstler = Set<String>()
    var offset = 0
    while true {
      guard let antwort = await HLAPI.shared.subsonic("getAlbumList2", [
        "type": "alphabeticalByName", "size": "500", "offset": String(offset), "musicFolderId": ordner,
      ]) else { return nil }
      let liste = (antwort["albumList2"] as? [String: Any])?["album"] as? [[String: Any]] ?? []
      for album in liste {
        if let id = album["id"] as? String { alben.append(id) }
        if let id = album["artistId"] as? String { kuenstler.insert(id) }
        for k in album["artists"] as? [[String: Any]] ?? [] { if let id = k["id"] as? String { kuenstler.insert(id) } }
      }
      if liste.count < 500 { return (alben, Array(kuenstler)) }
      offset += 500
    }
  }

  // MARK: Filter

  /// Fertige Prädikate je Entität; wird von AmperfyKit beim Laden jeder Liste gelesen.
  nonisolated(unsafe) static var filter = [String: NSPredicate]()

  private func filterBerechnen() {
    guard let wahl = gewaehlt else { Self.filter = [:]; return }
    let andere = bibliotheken.filter { $0.id != wahl.id }
    let album = praedikat(
      schluessel: "id", drin: Set(wahl.alben), andere: Set(andere.flatMap(\.alben))
    )
    let songs = praedikat(
      schluessel: "album.id", drin: Set(wahl.alben), andere: Set(andere.flatMap(\.alben))
    )
    let kuenstler = praedikat(
      schluessel: "id", drin: Set(wahl.kuenstler), andere: Set(andere.flatMap(\.kuenstler))
    )
    Self.filter = ["Album": album, "Song": songs, "Artist": kuenstler]
  }

  /// Kürzere Liste gewinnt: nur die gewählten zeigen oder die der anderen Bibliotheken ausblenden.
  /// Künstler, die in beiden Bibliotheken vorkommen, bleiben in beiden sichtbar.
  private func praedikat(schluessel: String, drin: Set<String>, andere: Set<String>) -> NSPredicate {
    let weg = andere.subtracting(drin)
    if drin.count <= weg.count {
      return NSPredicate(format: "%K IN %@", schluessel, Array(drin))
    }
    return NSPredicate(format: "NOT (%K IN %@)", schluessel, Array(weg))
  }

  // MARK: Umschalten

  func waehlen(_ bib: Bib) {
    guard bib.id != gewaehlt?.id else { return }
    UserDefaults.standard.set(bib.id, forKey: Self.auswahlSchluessel)
    filterBerechnen()
    guard let info = appDelegate.storage.settings.accounts.active else { return }
    // Amperfys eigener Kontowechsel: lädt alle Listen, die Startseite und CarPlay neu.
    appDelegate.switchAccount(accountInfo: info)
    themaGesetzt = false
    themaAnwenden()
  }

  /// Kinder-Modus: ganze App orange, damit sofort sichtbar ist, wofür man gerade stöbert.
  private func themaAnwenden() {
    guard !themaGesetzt else { return }
    themaGesetzt = true
    guard istKinderModus else { return }
    appDelegate.setAppTheme(color: Self.kinderFarbe)
    appDelegate.applyAppThemeToAlreadyLoadedViews()
  }

  // MARK: Knopf in der Navigationsleiste (Home, Bibliothek, Suche)

  func knopfEinsetzen(in navigationItem: UINavigationItem) {
    knoepfe.removeAll { $0.item == nil }
    if !knoepfe.contains(where: { $0.item === navigationItem }) { knoepfe.append(WeakNavItem(item: navigationItem)) }
    if !themaGesetzt { DispatchQueue.main.async { self.themaAnwenden() } }
    setzeKnopf(in: navigationItem)
  }

  private func knoepfeAktualisieren() {
    for k in knoepfe { if let item = k.item { setzeKnopf(in: item) } }
  }

  private func setzeKnopf(in navigationItem: UINavigationItem) {
    var links = (navigationItem.leftBarButtonItems ?? []).filter { $0.tag != Self.knopfTag }
    defer { navigationItem.leftBarButtonItems = links }
    guard let wahl = gewaehlt else { return }
    var konfig: UIButton.Configuration = wahl.istKinder ? .filled() : .tinted()
    konfig.title = anzeigename(wahl)
    konfig.image = UIImage(systemName: symbol(wahl))
    konfig.imagePadding = 6
    konfig.cornerStyle = .capsule
    konfig.indicator = .popup
    konfig.baseBackgroundColor = wahl.istKinder ? Self.kinderFarbe : nil
    konfig.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { a in
      var a = a
      a.font = UIFont.preferredFont(forTextStyle: .subheadline).withWeight(.semibold)
      return a
    }
    let button = UIButton(configuration: konfig)
    button.menu = menue()
    button.showsMenuAsPrimaryAction = true
    button.accessibilityLabel = "Bibliothek: \(anzeigename(wahl)). Antippen zum Wechseln."
    let knopf = UIBarButtonItem(customView: button)
    knopf.tag = Self.knopfTag
    if #available(iOS 26.0, *) { knopf.hidesSharedBackground = true }
    links.append(knopf)
  }

  private static let knopfTag = 4711

  private var appDelegate: AppDelegate { UIApplication.shared.delegate as! AppDelegate }

  private func menue() -> UIMenu {
    let aktionen = bibliotheken.sorted { a, b in
      (a.id == haupt?.id ? 0 : 1, a.name) < (b.id == haupt?.id ? 0 : 1, b.name)
    }.map { bib in
      UIAction(
        title: anzeigename(bib),
        subtitle: bib.istKinder ? "Hörspiele und Kinderlieder" : (bib.id == haupt?.id ? "Musik für dich, ohne Kinder" : nil),
        image: UIImage(systemName: symbol(bib)),
        state: bib.id == gewaehlt?.id ? .on : .off
      ) { [weak self] _ in self?.waehlen(bib) }
    }
    return UIMenu(title: "Was möchtest du durchstöbern?", options: .singleSelection, children: aktionen)
  }
}

private extension UIFont {
  func withWeight(_ gewicht: UIFont.Weight) -> UIFont {
    UIFont.systemFont(ofSize: pointSize, weight: gewicht)
  }
}
