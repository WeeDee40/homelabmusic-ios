//
//  HLKuenstlerBlock.swift
//  HomeLabMusic
//
//  Eine Künstlerseite: Amperfys Seite aus der Bibliothek (ArtistDetailVC) bekommt oben die Entdecken-Teile
//  wie bei Spotify: Mix, Folgen, beliebte Songs, die noch nicht in der Bibliothek sind, und «Mehr entdecken»
//  (Diskografie, ähnliche Künstler). Offline oder ohne Treffer bei Deezer bleibt der Block leer.
//
//  This program is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//

import AmperfyKit
import SwiftUI
import UIKit

/// Deezer-ID eines Bibliothekskünstlers. Direkt bei Deezers öffentlicher Schnittstelle (ohne Schlüssel):
/// Die Suche des Medienwunsch-Dienstes fragt ab drei Wörtern Claude und sucht nach Genre und Stimmung.
@MainActor
enum HLDeezer {
  private static var ids = [String: Int]()

  static func norm(_ name: String) -> String {
    name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
      .trimmingCharacters(in: .whitespaces)
  }

  /// Nur bei gleichem Namen (Gross/klein und Akzente egal), sonst nil: lieber kein Block als ein falscher Künstler.
  static func kuenstlerId(name: String) async -> Int? {
    let gesucht = norm(name)
    if let id = ids[gesucht] { return id }
    var teile = URLComponents(string: "https://api.deezer.com/search/artist")!
    teile.queryItems = [URLQueryItem(name: "q", value: name), URLQueryItem(name: "limit", value: "10")]
    struct Antwort: Decodable {
      struct Eintrag: Decodable { let id: Int; let name: String }
      let data: [Eintrag]?
    }
    guard let url = teile.url,
          let (daten, _) = try? await URLSession.shared.data(from: url),
          let antwort = try? JSONDecoder().decode(Antwort.self, from: daten),
          let treffer = antwort.data?.first(where: { norm($0.name) == gesucht })
    else { return nil }
    ids[gesucht] = treffer.id
    return treffer.id
  }
}

@MainActor
final class HLKuenstlerModell: ObservableObject {
  @Published private(set) var seite: HLKuenstlerSeite?
  @Published var folgt: Bool?
  /// Inhalt da: ArtistDetailVC passt die Zeilenhöhe an.
  var geaendert: (() -> ())?
  private var geladen = false

  func laden(name: String) async {
    guard !geladen else { return }
    geladen = true
    guard let id = await HLDeezer.kuenstlerId(name: name),
          let d = try? await HLAPI.shared.kuenstler(id) else { return }
    seite = d
    folgt = d.kuenstler.folgt
    geaendert?()
  }
}

struct HLKuenstlerBlock: View {
  let name: String
  @ObservedObject var modell: HLKuenstlerModell
  @State private var folgtLaeuft = false
  @Environment(\.hlOeffnen) private var oeffnen

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      if let d = modell.seite {
        let istGefolgt = modell.folgt ?? false
        ViewThatFits(in: .horizontal) {
          knoepfe(d, istGefolgt, kurz: false)
          knoepfe(d, istGefolgt, kurz: true)
        }
        if !d.top.isEmpty {
          Text("Top-Songs").font(.headline)
          HLSongRaster(songs: Array(d.top.prefix(12)))
        }
        // Diskografie direkt auf der Seite (Zeichen: ✓ Mediathek, ◐ Server, ohne = fehlt)
        let alben = d.alben.filter { $0.typ == "album" }
        let kurz = d.alben.filter { $0.typ != "album" }
        if !alben.isEmpty {
          Text("Alben").font(.headline)
          HLAlbumBand(alben: alben, kuenstler: d.kuenstler.name)
        }
        if !kurz.isEmpty {
          Text("Singles und EPs").font(.headline)
          HLAlbumBand(alben: kurz, kuenstler: d.kuenstler.name)
        }
        if !d.aehnlich.isEmpty {
          Text("Ähnliche Künstler").font(.headline)
          HLKuenstlerBand(liste: d.aehnlich)
        }
        if HLMediathekUI.stufenAktiv {
          Text("Auf dem Server").font(.headline).padding(.top, 6)   // darunter Amperfys Liste der Bibliothek
        }
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.vertical, modell.seite == nil ? 0 : 10)   // vor dem Laden keine leere Lücke
    .task { await modell.laden(name: name) }
  }

  @ViewBuilder private func knoepfe(_ d: HLKuenstlerSeite, _ istGefolgt: Bool, kurz: Bool) -> some View {
    HStack {
      Button { oeffnen(.sender(art: "kuenstler", id: "\(d.kuenstler.id)")) } label: {
        Label("Mix", systemImage: "dot.radiowaves.left.and.right")
      }
      .buttonStyle(HLKapsel(haupt: true))
      Button {
        folgtLaeuft = true
        Task {
          if let r = try? await HLAPI.shared.folgen(kuenstlerId: d.kuenstler.id, name: d.kuenstler.name, folgen: !istGefolgt) {
            modell.folgt = r.folgt ?? !istGefolgt
            HLPlayer.shared.zeigeHinweis(r.meldung ?? "")
          }
          folgtLaeuft = false
        }
      } label: {
        if kurz { Image(systemName: istGefolgt ? "checkmark" : "person.badge.plus") } else {
          Label(istGefolgt ? "Gefolgt" : "Folgen", systemImage: istGefolgt ? "checkmark" : "plus")
        }
      }
      .buttonStyle(HLKapsel())
      .disabled(folgtLaeuft)
    }
  }
}

/// Alles, was ArtistDetailVC braucht: eine Zeile im obersten (sonst leeren) Abschnitt.
@MainActor
final class HLKuenstlerEinbau {
  private let modell = HLKuenstlerModell()
  private let name: String
  private weak var vc: UITableViewController?

  init(name: String, vc: UITableViewController) {
    self.name = name
    self.vc = vc
    modell.geaendert = { [weak vc] in
      vc?.tableView.performBatchUpdates(nil)            // Zeilenhöhe neu, ohne die Tabelle neu zu laden
    }
    HLSpielLeiste.einbauen(in: vc)                      // Hinweise («Gewünscht», «Gefolgt»)
  }

  /// Offline gibt es nichts zu entdecken.
  var zeilen: Int {
    (UIApplication.shared.delegate as! AppDelegate).storage.settings.user.isOfflineMode ? 0 : 1
  }

  func zelle() -> UITableViewCell {
    let zelle = UITableViewCell()
    zelle.selectionStyle = .none
    zelle.backgroundColor = .clear
    let oeffnen: @MainActor (HLZiel) -> () = { [weak self] ziel in
      self?.vc?.navigationController?.pushViewController(HLTab.zielAnsicht(ziel), animated: true)
    }
    zelle.contentConfiguration = UIHostingConfiguration {
      HLKuenstlerBlock(name: self.name, modell: self.modell).environment(\.hlOeffnen, oeffnen)
    }
    .margins(.vertical, 0)
    return zelle
  }
}

// MARK: - Albumseite der Bibliothek

@MainActor
final class HLAlbumModell: ObservableObject {
  @Published private(set) var abgleich: HLAlbumAbgleich?
  @Published var mediathekStand = 0                     // nach «Alle zur Mediathek» neu zählen
  var geaendert: (() -> ())?
  private var geladen = false

  func laden(album: Album) async {
    guard !geladen else { return }
    geladen = true
    guard let d = try? await HLAPI.shared.albumAbgleich(album.id) else { return }
    abgleich = d
    geaendert?()
  }
}

/// Unter Amperfys Songliste: wie viel vom Album in deiner Mediathek ist, alles holen, Fehlendes wünschen,
/// darunter die Songs, die auf dem Server fehlen (zum Reinhören und Wünschen).
struct HLAlbumBlock: View {
  let album: Album
  @ObservedObject var modell: HLAlbumModell
  @ObservedObject private var player = HLPlayer.shared
  @State private var gewuenscht = false
  @State private var rueckfrage = false

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      let fehlt = modell.abgleich?.fehlt ?? []
      let _ = modell.mediathekStand
      let offen = HLMediathekUI.stufenAktiv ? HLMediathekUI.nichtInMediathek(album: album) : []
      let lokal = album.playables.count                 // nur Songs, die wirklich an diesem Album hängen
      let gesamt = max(modell.abgleich?.anzahl ?? 0, lokal)
      let eigene = lokal - offen.count
      let wuenschbar = fehlt.filter { player.stufe($0) == .neu && $0.deezerId != nil }
      let anderswo = fehlt.filter { player.stufe($0) == .server }
      if HLMediathekUI.stufenAktiv, gesamt > 0 {
        Text("\(eigene) von \(gesamt) Songs in deiner Mediathek").font(.subheadline).foregroundStyle(.secondary)
      }
      HStack {
        if !offen.isEmpty || !anderswo.isEmpty {
          Button {
            Task {
              do {
                try await HLMediathek.shared.hinzufuegen(songIds: offen)
                player.zurMediathek(anderswo)
                modell.mediathekStand += 1
                modell.geaendert?()
                player.zeigeHinweis("\(offen.count + anderswo.count) Songs zur Mediathek hinzugefügt.")
              } catch {
                player.zeigeHinweis(error.localizedDescription)
              }
            }
          } label: { Label("\(offen.count + anderswo.count) zur Mediathek", systemImage: "plus") }
            .buttonStyle(HLKapsel(haupt: true))
        }
        if !wuenschbar.isEmpty {
          Button { rueckfrage = true } label: {
            Label(gewuenscht ? "Gewünscht" : "Rest wünschen (\(wuenschbar.count))",
                  systemImage: gewuenscht ? "hourglass" : "arrow.down.circle")
          }
          .buttonStyle(HLKapsel())
          .disabled(gewuenscht)
        }
      }
      if !fehlt.isEmpty {
        Text("Fehlt noch auf dem Server").font(.headline).padding(.top, 4)
        ForEach(fehlt.indices, id: \.self) { HLSongZeile(songs: fehlt, i: $0, mitAlbum: false, kurzerKnopf: true) }
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.horizontal, 20)
    .padding(.vertical, 14)
    .task { await modell.laden(album: album) }
    .confirmationDialog("\(wuenschbarAnzahl) Songs wünschen?", isPresented: $rueckfrage, titleVisibility: .visible) {
      Button("\(wuenschbarAnzahl) Songs wünschen") { wuenschen() }
      Button("Abbrechen", role: .cancel) {}
    } message: {
      Text("Sie gehen an SoulSync und kommen nach und nach.")
    }
  }

  private var wuenschbarAnzahl: Int {
    (modell.abgleich?.fehlt ?? []).filter { player.stufe($0) == .neu && $0.deezerId != nil }.count
  }

  private func wuenschen() {
    let liste = (modell.abgleich?.fehlt ?? []).filter { player.stufe($0) == .neu && $0.deezerId != nil }
    gewuenscht = true
    Task {
      do {
        let r = try await HLAPI.shared.wunsch(songs: Array(liste.compactMap(\.deezerId).prefix(HLSammelKnoepfe.hoechstens)))
        player.alsAngefragtMarkieren(liste)
        player.zeigeHinweis(r.meldung ?? "Gewünscht.")
      } catch {
        gewuenscht = false
        player.zeigeHinweis(error.localizedDescription)
      }
    }
  }
}

/// Alles, was AlbumDetailVC braucht: eine Fusszeile unter der Songliste (passt ihre Höhe selbst an).
@MainActor
final class HLAlbumEinbau {
  private let modell = HLAlbumModell()
  private let host: UIHostingController<AnyView>
  private let huelle = UIView()                         // die Tabelle setzt die Lage der Hülle, SwiftUI nur den Inhalt
  private weak var vc: UITableViewController?
  private var breite: CGFloat = 0

  init?(album: Album, vc: UITableViewController) {
    guard !(UIApplication.shared.delegate as! AppDelegate).storage.settings.user.isOfflineMode else { return nil }
    self.vc = vc
    host = UIHostingController(rootView: AnyView(EmptyView()))
    let oeffnen: @MainActor (HLZiel) -> () = { [weak vc] ziel in
      vc?.navigationController?.pushViewController(HLTab.zielAnsicht(ziel), animated: true)
    }
    host.rootView = AnyView(HLAlbumBlock(album: album, modell: modell).environment(\.hlOeffnen, oeffnen))
    host.view.backgroundColor = .clear
    vc.addChild(host)
    huelle.addSubview(host.view)
    host.didMove(toParent: vc)
    huelle.clipsToBounds = true
    // Neue Daten: erst nach dem Neuzeichnen von SwiftUI messen (sonst gilt noch die alte Höhe)
    modell.geaendert = { [weak self] in
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { self?.groesseAnpassen(erzwingen: true) }
    }
    HLSpielLeiste.einbauen(in: vc)                      // Hinweise («Gewünscht», «Hinzugefügt»)
  }

  /// Aus viewDidLayoutSubviews: Fusszeile auf Breite und Inhalt bringen.
  func groesseAnpassen(erzwingen: Bool = false) {
    guard let tabelle = vc?.tableView else { return }
    let w = tabelle.bounds.width
    guard w > 0, erzwingen || w != breite else { return }
    breite = w
    let h = host.sizeThatFits(in: CGSize(width: w, height: .greatestFiniteMagnitude)).height
    huelle.frame = CGRect(x: 0, y: 0, width: w, height: h)
    host.view.frame = huelle.bounds
    tabelle.tableFooterView = huelle                    // erneut zuweisen: die Tabelle setzt sie unter die Zeilen
  }
}
