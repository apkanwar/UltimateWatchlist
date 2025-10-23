//
//  OMDbService.swift
//  UltimateWatchlist
//
//  Created by Codex on 2025-10-13.
//

import Foundation

enum OMDbServiceError: Error, LocalizedError {
    case invalidURL
    case missingAPIKey
    case requestFailed(statusCode: Int)
    case responseError(String)
    case decodingFailed
    case networkFailure(Error)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Failed to build a valid request for the movie service."
        case .missingAPIKey:
            return "Missing OMDb API key. Set OMDB_API_KEY or add OMDbAPIKey to Info.plist."
        case .requestFailed(let statusCode):
            if statusCode == -1 {
                return "The movie service returned an unexpected response."
            }
            return "The movie service returned an error (code \(statusCode))."
        case .responseError(let message):
            return message
        case .decodingFailed:
            return "Received an unexpected response from the movie service."
        case .networkFailure(let error):
            return error.localizedDescription
        }
    }
}

/// Handles networking against the OMDb (Open Movie Database) API.
final class OMDbService {
    static let shared = OMDbService()

    private let baseURL = URL(string: "https://www.omdbapi.com/")!
    private let session: URLSession
    private let apiKey: String
    private let curatedPopularIDs: [String] = [
        "tt0133093", // The Matrix
        "tt0110912", // Pulp Fiction
        "tt0111161", // The Shawshank Redemption
        "tt0068646", // The Godfather
        "tt0109830", // Forrest Gump
        "tt0120737", // The Lord of the Rings: The Fellowship of the Ring
        "tt0167260", // The Lord of the Rings: The Return of the King
        "tt0120815", // Saving Private Ryan
        "tt0080684", // Star Wars: Episode V - The Empire Strikes Back
        "tt0137523", // Fight Club
        "tt1375666", // Inception
        "tt0088763", // Back to the Future
        "tt0110357", // The Lion King
        "tt0102926", // The Silence of the Lambs
        "tt0816692", // Interstellar
        "tt1853728", // Django Unchained
        "tt4154796", // Avengers: Endgame
        "tt4633694", // Spider-Man: Into the Spider-Verse
        "tt7286456", // Joker
        "tt4154756"  // Avengers: Infinity War
    ]
    private let fallbackSearchQueries = [
        "top rated",
        "award winning",
        "box office",
        "classic",
        "blockbuster"
    ]

    init(session: URLSession = .shared, apiKey: String = AppConfiguration.omdbAPIKey) {
        self.session = session
        self.apiKey = apiKey
    }

    func fetchPopularMovies(limit: Int = 20) async throws -> [Anime] {
        guard !apiKey.isEmpty else { throw OMDbServiceError.missingAPIKey }
        let primary = try await fetchMovies(for: curatedPopularIDs, limit: limit)
        if primary.count >= limit {
            return Array(primary.prefix(limit))
        }

        var collected = primary
        var seen = Set(primary.map(\.providerID))

        for keyword in fallbackSearchQueries where collected.count < limit {
            let results = try await searchMovies(query: keyword, limit: limit * 2)
            for movie in results where !seen.contains(movie.providerID) {
                collected.append(movie)
                seen.insert(movie.providerID)
                if collected.count >= limit { break }
            }
        }

        return Array(collected.prefix(limit))
    }

    func fetchRecommendations(for genres: [AnimeGenre], limit: Int = 20) async throws -> [Anime] {
        guard !apiKey.isEmpty else { throw OMDbServiceError.missingAPIKey }
        let expandedLimit = max(limit * 2, 30)
        let popular = try await fetchPopularMovies(limit: expandedLimit)

        guard !genres.isEmpty else {
            return Array(popular.prefix(limit))
        }

        let preferred = Set(genres.map { $0.name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current) })
        let filtered = popular.filter { movie in
            let movieGenres = movie.genres.map {
                $0.name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            }
            return !preferred.isDisjoint(with: movieGenres)
        }

        if !filtered.isEmpty {
            return Array(filtered.prefix(limit))
        }

        // If no matches, fall back to searching with the preferred genre terms.
        var collected: [Anime] = []
        var seen = Set(popular.map(\.providerID))
        for genre in preferred where collected.count < limit {
            let results = try await searchMovies(query: genre, limit: limit)
            for movie in results where !seen.contains(movie.providerID) {
                collected.append(movie)
                seen.insert(movie.providerID)
                if collected.count >= limit { break }
            }
        }

        if !collected.isEmpty {
            return Array(collected.prefix(limit))
        }

        return Array(popular.prefix(limit))
    }

    func searchMovies(query: String, limit: Int = 20) async throws -> [Anime] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        guard !apiKey.isEmpty else { throw OMDbServiceError.missingAPIKey }

        let response: OMDbSearchResponse = try await performRequest(
            queryItems: [
                URLQueryItem(name: "s", value: trimmed),
                URLQueryItem(name: "type", value: "movie")
            ]
        )

        guard response.isSuccess else {
            if let message = response.errorMessage {
                throw OMDbServiceError.responseError(message)
            }
            return []
        }

        let ids = response.search?.map(\.imdbID) ?? []
        let movies = try await fetchMovies(for: ids, limit: limit)
        return movies
    }

    // MARK: - Private

    private func fetchMovies(for imdbIDs: [String], limit: Int) async throws -> [Anime] {
        guard !apiKey.isEmpty else { throw OMDbServiceError.missingAPIKey }
        var collected: [Anime] = []
        var seen = Set<Int>()

        for imdbID in imdbIDs {
            if collected.count >= limit { break }
            guard let movie = try await fetchMovieDetail(imdbID: imdbID) else { continue }
            if seen.insert(movie.providerID).inserted {
                collected.append(movie)
            }
        }

        return collected
    }

    private func fetchMovieDetail(imdbID: String) async throws -> Anime? {
        let response: OMDbMovieDetailResponse = try await performRequest(
            queryItems: [
                URLQueryItem(name: "i", value: imdbID),
                URLQueryItem(name: "plot", value: "full")
            ]
        )

        guard response.isSuccess else {
            if let message = response.errorMessage {
                throw OMDbServiceError.responseError(message)
            }
            return nil
        }

        return OMDbMapper.makeAnime(from: response)
    }

    private func performRequest<T: Decodable>(queryItems: [URLQueryItem]) async throws -> T {
        guard !apiKey.isEmpty else { throw OMDbServiceError.missingAPIKey }

        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        var items = queryItems
        let hasKey = items.contains { $0.name.caseInsensitiveCompare("apikey") == .orderedSame }
        if !hasKey {
            items.append(URLQueryItem(name: "apikey", value: apiKey))
        }
        components?.queryItems = items

        guard let url = components?.url else { throw OMDbServiceError.invalidURL }

        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw OMDbServiceError.requestFailed(statusCode: -1)
            }

            guard (200..<300).contains(httpResponse.statusCode) else {
                throw OMDbServiceError.requestFailed(statusCode: httpResponse.statusCode)
            }

            do {
                return try JSONDecoder().decode(T.self, from: data)
            } catch {
                throw OMDbServiceError.decodingFailed
            }
        } catch let error as OMDbServiceError {
            throw error
        } catch {
            throw OMDbServiceError.networkFailure(error)
        }
    }
}

// MARK: - DTOs

private struct OMDbSearchResponse: Decodable {
    struct SearchItem: Decodable {
        let title: String
        let year: String
        let imdbID: String
        let type: String
        let poster: String

        enum CodingKeys: String, CodingKey {
            case title = "Title"
            case year = "Year"
            case imdbID
            case type = "Type"
            case poster = "Poster"
        }
    }

    let search: [SearchItem]?
    let totalResults: String?
    let response: String
    let errorMessage: String?

    enum CodingKeys: String, CodingKey {
        case search = "Search"
        case totalResults
        case response = "Response"
        case errorMessage = "Error"
    }

    var isSuccess: Bool { response.caseInsensitiveCompare("true") == .orderedSame }
}

private struct OMDbMovieDetailResponse: Decodable {
    let response: String
    let errorMessage: String?
    let imdbID: String?
    let title: String?
    let plot: String?
    let poster: String?
    let imdbRating: String?
    let genre: String?
    let runtime: String?
    let year: String?
    let released: String?

    enum CodingKeys: String, CodingKey {
        case response = "Response"
        case errorMessage = "Error"
        case imdbID
        case title = "Title"
        case plot = "Plot"
        case poster = "Poster"
        case imdbRating
        case genre = "Genre"
        case runtime = "Runtime"
        case year = "Year"
        case released = "Released"
    }

    var isSuccess: Bool { response.caseInsensitiveCompare("true") == .orderedSame }
}

// MARK: - Mapping

private enum OMDbMapper {
    static func makeAnime(from response: OMDbMovieDetailResponse) -> Anime? {
        guard
            let imdbID = response.imdbID,
            let title = response.title,
            !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return nil
        }

        let providerID = numericProviderID(from: imdbID)
        let synopsis = cleanedPlot(from: response.plot)
        let imageURL = secureURL(from: response.poster)
        let score = Double(response.imdbRating ?? "")
        let genres = genres(from: response.genre)

        return Anime(
            providerID: providerID,
            kind: .movie,
            title: title,
            synopsis: synopsis,
            imageURL: imageURL,
            score: score,
            genres: genres,
            episodeCount: nil
        )
    }

    private static func numericProviderID(from imdbID: String) -> Int {
        let digits = imdbID.compactMap { $0.isNumber ? Int(String($0)) : nil }
        if digits.isEmpty {
            return abs(imdbID.hashValue)
        }
        var value = 0
        for digit in digits {
            value = value * 10 + digit
        }
        return value
    }

    private static func cleanedPlot(from plot: String?) -> String {
        guard let plot else { return "No synopsis available." }
        let trimmed = plot.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "No synopsis available." : trimmed
    }

    private static func secureURL(from poster: String?) -> URL? {
        guard let poster, !poster.isEmpty, poster != "N/A" else { return nil }
        if var components = URLComponents(string: poster) {
            if components.scheme == "http" {
                components.scheme = "https"
            }
            if let url = components.url {
                return url
            }
        }
        let secure = poster.replacingOccurrences(of: "http://", with: "https://")
        return URL(string: secure)
    }

    private static func genres(from raw: String?) -> [AnimeGenre] {
        guard let raw else { return [] }
        let parts = raw
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return parts.map { name in
            AnimeGenre(id: genreID(for: name), name: name)
        }
    }

    private static func genreID(for name: String) -> Int {
        let base = 20_000_000
        let lowered = name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        guard !lowered.isEmpty else { return base }
        var hash = 0
        for scalar in lowered.unicodeScalars {
            hash = (hash &* 31 &+ Int(scalar.value)) & 0x7FFF_FFFF
        }
        return base + hash
    }

}
