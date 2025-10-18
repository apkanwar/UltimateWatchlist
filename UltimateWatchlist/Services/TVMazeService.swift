//
//  TVMazeService.swift
//  UltimateWatchlist
//
//  Created by Codex on 2025-10-13.
//

import Foundation

enum TVMazeServiceError: Error, LocalizedError {
    case invalidURL
    case missingAPIKey
    case requestFailed(statusCode: Int)
    case decodingFailed
    case rateLimited
    case networkFailure(Error)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Failed to build a valid request for the TV show service."
        case .missingAPIKey:
            return "Missing TVMaze API key. Set TVMAZE_API_KEY or add TVMazeAPIKey to Info.plist."
        case .requestFailed(let statusCode):
            if statusCode == -1 {
                return "The TV show service returned an unexpected response."
            }
            return "The TV show service returned an error (code \(statusCode))."
        case .decodingFailed:
            return "Received an unexpected response from the TV show service."
        case .rateLimited:
            return "The TV show service is temporarily rate limiting requests. Please try again shortly."
        case .networkFailure(let error):
            return error.localizedDescription
        }
    }
}

/// Handles networking against the TVMaze API.
final class TVMazeService {
    static let shared = TVMazeService()

    private let baseURL = URL(string: "https://api.tvmaze.com")!
    private let session: URLSession
    private let apiKey: String
    private let maxRetries = 3
    private let baseDelay: UInt64 = 400_000_000 // 0.4 seconds

    init(session: URLSession = .shared, apiKey: String = AppConfiguration.tvMazeAPIKey) {
        self.session = session
        self.apiKey = apiKey
    }

    func fetchPopularShows(limit: Int = 20) async throws -> [Anime] {
        let shows = try await fetchShowsPage(page: 0)
        let sorted = shows.sorted { ($0.rating?.average ?? 0) > ($1.rating?.average ?? 0) }
        return Array(sorted.prefix(limit)).map { Anime(tvMazeShow: $0) }
    }

    func searchShows(query: String, limit: Int = 20) async throws -> [Anime] {
        guard !apiKey.isEmpty else { throw TVMazeServiceError.missingAPIKey }
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let queryItems = [
            URLQueryItem(name: "q", value: trimmed),
            URLQueryItem(name: "limit", value: "\(limit)")
        ]
        let url = try makeURL(path: "search/shows", queryItems: queryItems)
        let results: [TVMazeSearchResponse] = try await performRequest(url: url)
        var seen = Set<Int>()
        var ordered: [TVMazeShowDTO] = []
        for result in results {
            let show = result.show
            if seen.insert(show.id).inserted {
                ordered.append(show)
            }
        }
        return ordered.prefix(limit).map { Anime(tvMazeShow: $0) }
    }
    
    func fetchRecommendations(for genres: [AnimeGenre], limit: Int = 20) async throws -> [Anime] {
        let shows = try await fetchShowsPage(page: 0)
        let sorted = shows.sorted { ($0.rating?.average ?? 0) > ($1.rating?.average ?? 0) }
        let preferredNames = Set(genres.map { $0.name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current) })
        let filtered = sorted.filter { show in
            guard !preferredNames.isEmpty else { return true }
            let showGenres = show.genres.map {
                $0.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            }
            return !preferredNames.isDisjoint(with: showGenres)
        }
        let selection = filtered.isEmpty ? sorted : filtered
        return Array(selection.prefix(limit)).map { Anime(tvMazeShow: $0) }
    }

    // MARK: - Helpers

    private func fetchShowsPage(page: Int) async throws -> [TVMazeShowDTO] {
        guard !apiKey.isEmpty else { throw TVMazeServiceError.missingAPIKey }
        let url = try makeURL(path: "shows", queryItems: [URLQueryItem(name: "page", value: "\(page)")])
        return try await performRequest(url: url)
    }

    private func makeURL(path: String, queryItems: [URLQueryItem] = []) throws -> URL {
        guard !path.isEmpty else { throw TVMazeServiceError.invalidURL }
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        components?.path = "/" + path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if !queryItems.isEmpty {
            components?.queryItems = queryItems
        }
        guard let url = components?.url else { throw TVMazeServiceError.invalidURL }
        return url
    }

    private func performRequest<T: Decodable>(url: URL) async throws -> T {
        var lastError: TVMazeServiceError?

        for attempt in 0..<maxRetries {
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.timeoutInterval = 30
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            if !apiKey.isEmpty {
                request.setValue(apiKey, forHTTPHeaderField: "X-API-Key")
                request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            }

            do {
                let (data, response) = try await session.data(for: request)

                guard let httpResponse = response as? HTTPURLResponse else {
                    throw TVMazeServiceError.requestFailed(statusCode: -1)
                }

                switch httpResponse.statusCode {
                case 200..<300:
                    do {
                        return try JSONDecoder().decode(T.self, from: data)
                    } catch {
                        throw TVMazeServiceError.decodingFailed
                    }
                case 401, 403:
                    throw TVMazeServiceError.requestFailed(statusCode: httpResponse.statusCode)
                case 429:
                    lastError = .rateLimited
                    if attempt < maxRetries - 1 {
                        let delay = retryAfterDelay(from: httpResponse) ?? defaultRetryDelay(forAttempt: attempt)
                        try? await Task.sleep(nanoseconds: delay)
                        continue
                    }
                case 500..<600:
                    lastError = .requestFailed(statusCode: httpResponse.statusCode)
                    if attempt < maxRetries - 1 {
                        let delay = defaultRetryDelay(forAttempt: attempt)
                        try? await Task.sleep(nanoseconds: delay)
                        continue
                    }
                default:
                    throw TVMazeServiceError.requestFailed(statusCode: httpResponse.statusCode)
                }
            } catch let error as TVMazeServiceError {
                lastError = error
            } catch {
                lastError = .networkFailure(error)
            }

            if attempt < maxRetries - 1 {
                let delay = defaultRetryDelay(forAttempt: attempt)
                try? await Task.sleep(nanoseconds: delay)
            }
        }

        throw lastError ?? TVMazeServiceError.requestFailed(statusCode: -1)
    }

    private func retryAfterDelay(from response: HTTPURLResponse) -> UInt64? {
        if let retryAfter = response.value(forHTTPHeaderField: "Retry-After"),
           let seconds = Double(retryAfter) {
            return UInt64(seconds * 1_000_000_000)
        }
        return nil
    }

    private func defaultRetryDelay(forAttempt attempt: Int) -> UInt64 {
        let multiplier = pow(2.0, Double(attempt))
        return UInt64(Double(baseDelay) * multiplier)
    }
}

// MARK: - DTOs & Mapping

private struct TVMazeShowDTO: Decodable {
    struct RatingDTO: Decodable {
        let average: Double?
    }

    struct ImageDTO: Decodable {
        let medium: String?
        let original: String?
    }

    let id: Int
    let name: String
    let summary: String?
    let genres: [String]
    let rating: RatingDTO?
    let image: ImageDTO?
    let averageRuntime: Int?
    let runtime: Int?
    let episodeOrder: Int?
}

private struct TVMazeSearchResponse: Decodable {
    let score: Double?
    let show: TVMazeShowDTO
}

private extension Anime {
    init(tvMazeShow show: TVMazeShowDTO) {
        let genres = show.genres.map { AnimeGenre(id: TVMazeMapper.genreID(for: $0), name: $0) }
        self.init(
            providerID: show.id,
            kind: .tvShow,
            title: show.name,
            synopsis: TVMazeMapper.cleanedSynopsis(from: show.summary),
            imageURL: TVMazeMapper.secureURL(from: show.image?.original ?? show.image?.medium),
            score: show.rating?.average,
            genres: genres,
            episodeCount: show.episodeOrder
        )
    }
}

private enum TVMazeMapper {
    static func genreID(for name: String) -> Int {
        let base = 10_000_000
        let lowercased = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !lowercased.isEmpty else { return base }
        var hash = 0
        for scalar in lowercased.unicodeScalars {
            hash = (hash &* 31 &+ Int(scalar.value)) & 0x7FFF_FFFF
        }
        return base + hash
    }

    static func cleanedSynopsis(from summary: String?) -> String {
        guard let summary, !summary.isEmpty else { return "No synopsis available." }
        let normalizedBreaks = summary.replacingOccurrences(
            of: "(?i)<br\\s*/?>",
            with: "\n",
            options: .regularExpression
        )
        let stripped = normalizedBreaks.replacingOccurrences(
            of: "<[^>]+>",
            with: " ",
            options: .regularExpression
        )
        let decoded = decodeHTMLEntities(in: stripped)
        let collapsedWhitespace = decoded.replacingOccurrences(
            of: "\\s+",
            with: " ",
            options: .regularExpression
        )
        let trimmed = collapsedWhitespace.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "No synopsis available." : trimmed
    }

    static func secureURL(from string: String?) -> URL? {
        guard let string, !string.isEmpty else { return nil }
        if var components = URLComponents(string: string) {
            if components.scheme == "http" {
                components.scheme = "https"
            }
            if let url = components.url {
                return url
            }
        }
        let secureString = string.replacingOccurrences(of: "http://", with: "https://")
        return URL(string: secureString)
    }

    private static func decodeHTMLEntities(in string: String) -> String {
        guard !string.isEmpty else { return string }
        var result = string
        let entities: [(String, String)] = [
            ("&amp;", "&"),
            ("&lt;", "<"),
            ("&gt;", ">"),
            ("&quot;", "\""),
            ("&#39;", "'"),
            ("&#039;", "'")
        ]
        for (entity, character) in entities {
            result = result.replacingOccurrences(of: entity, with: character)
        }
        return result
    }
}
