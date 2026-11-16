//
//  HomeSection.swift
//  AmperfyKit
//
//  Created by Maximilian Bauer on 26.11.25.
//  Copyright (c) 2025 Maximilian Bauer. All rights reserved.
//
//  This program is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  This program is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License
//  along with this program.  If not, see <http://www.gnu.org/licenses/>.
//

import Foundation

public enum HomeSection: Int, Sendable, CaseIterable, Codable {
  // add new section always at the end to keep the Int consitent
  case lastTimePlayedPlaylists
  case recentlyPlayedAlbums
  case newestAlbums
  case randomAlbums
  case newestPodcastEpisodes
  case podcasts
  case radios
  case randomArtists
  case randomGenres
  case randomSongs

  static let defaultValue: [HomeSection] = [
    .randomAlbums,
    .recentlyPlayedAlbums,
    .lastTimePlayedPlaylists,
    .newestAlbums,
  ]

  public var title: String {
    switch self {
    case .recentlyPlayedAlbums: return String(localized: "Recently Played Albums")
    case .newestAlbums: return String(localized: "Newest Albums")
    case .randomAlbums: return String(localized: "Random Albums")
    case .lastTimePlayedPlaylists: return String(localized: "Recently Played Playlists")
    case .newestPodcastEpisodes: return String(localized: "Newest Podcast Episodes")
    case .podcasts: return String(localized: "Podcasts")
    case .radios: return String(localized: "Radios")
    case .randomArtists: return String(localized: "Random Artists")
    case .randomGenres: return String(localized: "Random Genres")
    case .randomSongs: return String(localized: "Random Songs")
    }
  }

  public static func create(fromTitle: String) -> HomeSection? {
    allCases.first(where: { $0.title == fromTitle })
  }

  public var isRandomSection: Bool {
    switch self {
    case .recentlyPlayedAlbums: return false
    case .newestAlbums: return false
    case .randomAlbums: return true
    case .lastTimePlayedPlaylists: return false
    case .newestPodcastEpisodes: return false
    case .podcasts: return false
    case .radios: return false
    case .randomArtists: return true
    case .randomGenres: return true
    case .randomSongs: return true
    }
  }
}
