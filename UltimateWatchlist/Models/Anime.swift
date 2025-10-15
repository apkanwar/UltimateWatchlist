//
//  Anime.swift
//  UltimateWatchlist
//
//  Created by Codex on 2025-10-13.
//

import Foundation

/// Core anime model used throughout the app.
struct Anime: Identifiable, Hashable, Codable {
    let id: Int
    let title: String
    let synopsis: String
    let imageURL: URL?
    let score: Double?
    let genres: [AnimeGenre]
    let episodeCount: Int?

    init(
        id: Int,
        title: String,
        synopsis: String,
        imageURL: URL?,
        score: Double?,
        genres: [AnimeGenre],
        episodeCount: Int?
    ) {
        self.id = id
        self.title = title
        self.synopsis = synopsis
        self.imageURL = imageURL
        self.score = score
        self.genres = genres
        self.episodeCount = episodeCount
    }
}

/// Simplified genre representation matching MyAnimeList/Jikan identifiers.
struct AnimeGenre: Identifiable, Hashable, Codable {
    let id: Int
    let name: String
}
