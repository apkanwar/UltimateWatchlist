//
//  Anime.swift
//  UltimateWatchlist
//
//  Created by Codex on 2025-10-13.
//

import Foundation

enum MediaKind: String, Codable, CaseIterable, Identifiable {
    case anime
    case tvShow
    case movie

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .anime: return "Anime"
        case .tvShow: return "TV Show"
        case .movie: return "Movie"
        }
    }

    var idOffset: Int {
        switch self {
        case .anime: return 0
        case .tvShow: return 1_000_000_000
        case .movie: return 2_000_000_000
        }
    }

    func namespace(providerID: Int) -> Int {
        idOffset + providerID
    }

    func providerID(from namespacedID: Int) -> Int {
        let value = namespacedID - idOffset
        return value >= 0 ? value : namespacedID
    }
}

/// Core media model used throughout the app (anime, TV show, or movie).
struct Anime: Identifiable, Hashable, Codable {
    let id: Int
    let providerID: Int
    let kind: MediaKind
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
        episodeCount: Int?,
        kind: MediaKind = .anime,
        providerID: Int? = nil
    ) {
        self.kind = kind
        self.providerID = providerID ?? id
        self.id = kind.namespace(providerID: self.providerID)
        self.title = title
        self.synopsis = synopsis
        self.imageURL = imageURL
        self.score = score
        self.genres = genres
        self.episodeCount = episodeCount
    }

    init(
        providerID: Int,
        kind: MediaKind,
        title: String,
        synopsis: String,
        imageURL: URL?,
        score: Double?,
        genres: [AnimeGenre],
        episodeCount: Int?
    ) {
        self.init(
            id: providerID,
            title: title,
            synopsis: synopsis,
            imageURL: imageURL,
            score: score,
            genres: genres,
            episodeCount: episodeCount,
            kind: kind,
            providerID: providerID
        )
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case providerID
        case kind
        case title
        case synopsis
        case imageURL
        case score
        case genres
        case episodeCount
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let rawKind = try container.decodeIfPresent(MediaKind.self, forKey: .kind) ?? .anime
        let decodedProviderID = try container.decodeIfPresent(Int.self, forKey: .providerID)
        let decodedID = try container.decode(Int.self, forKey: .id)

        kind = rawKind
        providerID = decodedProviderID ?? rawKind.providerID(from: decodedID)
        id = rawKind.namespace(providerID: providerID)
        title = try container.decode(String.self, forKey: .title)
        synopsis = try container.decode(String.self, forKey: .synopsis)
        if let string = try container.decodeIfPresent(String.self, forKey: .imageURL) {
            imageURL = URL(string: string)
        } else {
            imageURL = nil
        }
        score = try container.decodeIfPresent(Double.self, forKey: .score)
        genres = try container.decodeIfPresent([AnimeGenre].self, forKey: .genres) ?? []
        episodeCount = try container.decodeIfPresent(Int.self, forKey: .episodeCount)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(providerID, forKey: .providerID)
        try container.encode(kind, forKey: .kind)
        try container.encode(title, forKey: .title)
        try container.encode(synopsis, forKey: .synopsis)
        try container.encodeIfPresent(imageURL?.absoluteString, forKey: .imageURL)
        try container.encodeIfPresent(score, forKey: .score)
        try container.encode(genres, forKey: .genres)
        try container.encodeIfPresent(episodeCount, forKey: .episodeCount)
    }
}

/// Simplified genre representation matching provider identifiers.
struct AnimeGenre: Identifiable, Hashable, Codable {
    let id: Int
    let name: String
}
