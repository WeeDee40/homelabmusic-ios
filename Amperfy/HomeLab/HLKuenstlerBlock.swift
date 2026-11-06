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
        let id = d.kuenstler.id
        let istGefolgt = modell.folgt ?? false
        ViewThatFits(in: .horizontal) {
          knoepfe(d, istGefolgt, kurz: false)
          knoepfe(d, istGefolgt, kurz: true)
        }
        let neu = d.top.filter { HLPlayer.shared.status($0) != "bibliothek" }
        if !neu.isEmpty {
          Text("Beliebt, noch nicht bei dir").font(.headline)
          HLSongBand(songs: Array(neu.prefix(10)))
        }
        Button { oeffnen(.kuenstler(id)) } label: {
          Label("Diskografie und ähnliche Künstler", systemImage: "sparkles").font(.subheadline.weight(.semibold))
        }
        .buttonStyle(.plain).foregroundStyle(Color.accentColor)
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
