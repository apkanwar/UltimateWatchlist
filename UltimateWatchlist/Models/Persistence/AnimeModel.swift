import Foundation
import SwiftData

@Model
final class AnimeModel: Identifiable {
    @Attribute(.unique) var id: Int
    var providerID: Int = 0
    var kindRaw: String = MediaKind.anime.rawValue
    var title: String
    var synopsis: String
    var imageURLString: String?
    var score: Double?
    var episodeCount: Int?
    @Relationship(deleteRule: .cascade) var genres: [AnimeGenreModel] = []

    init(
        id: Int,
        providerID: Int,
        kind: MediaKind,
        title: String,
        synopsis: String,
        imageURLString: String?,
        score: Double?,
        episodeCount: Int?,
        genres: [AnimeGenreModel] = []
    ) {
        self.id = id
        self.providerID = providerID
        self.kindRaw = kind.rawValue
        self.title = title
        self.synopsis = synopsis
        self.imageURLString = imageURLString
        self.score = score
        self.episodeCount = episodeCount
        self.genres = genres
    }
}

extension AnimeModel {
    var kind: MediaKind {
        get { MediaKind(rawValue: kindRaw) ?? .anime }
        set { kindRaw = newValue.rawValue }
    }

    var resolvedProviderID: Int {
        if providerID != 0 { return providerID }
        let fallback = kind.providerID(from: id)
        providerID = fallback
        return fallback
    }

    var imageURL: URL? {
        guard let raw = imageURLString, !raw.isEmpty else { return nil }
        if var components = URLComponents(string: raw) {
            if components.scheme == "http" {
                components.scheme = "https"
            }
            if let url = components.url {
                return url
            }
        }
        let secure = raw.replacingOccurrences(of: "http://", with: "https://")
        return URL(string: secure)
    }
}

extension AnimeModel {
    convenience init(from dto: Anime, genres: [AnimeGenreModel]) {
        self.init(
            id: dto.id,
            providerID: dto.providerID,
            kind: dto.kind,
            title: dto.title,
            synopsis: dto.synopsis,
            imageURLString: dto.imageURL?.absoluteString,
            score: dto.score,
            episodeCount: dto.episodeCount,
            genres: genres
        )
    }
}
