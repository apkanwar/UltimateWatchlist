//
//  AnimeService.swift
//  UltimateWatchlist
//
//  Created by Codex on 2025-10-13.
//

import Foundation

enum AnimeServiceError: Error, LocalizedError {
    case invalidURL
    case missingClientID
    case requestFailed(statusCode: Int)
    case decodingFailed
    case rateLimited
    case networkFailure(Error)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Failed to build a valid request."
        case .missingClientID:
            return "Missing MyAnimeList Client ID. Set MAL_CLIENT_ID env variable or add MALClientID to Info.plist."
        case .requestFailed(let statusCode):
            if statusCode == -1 {
                return "The anime service returned an unexpected response."
            }
            return "The anime service returned an error (code \(statusCode))."
        case .decodingFailed:
            return "Received an unexpected response from the anime service."
        case .rateLimited:
            return "The anime service is temporarily rate limiting requests. Please try again shortly."
        case .networkFailure(let error):
            return error.localizedDescription
        }
    }
}

/// Handles networking against the official MyAnimeList API v2.
final class AnimeService {
    static let shared = AnimeService()

    private let baseURL = URL(string: "https://api.myanimelist.net/v2")!
    private let session: URLSession
    private let clientID: String
    private let userAgent: String
    private let maxRetries = 3
    private let baseDelay: UInt64 = 400_000_000 // 0.4 seconds
    private let defaultFields = "id,title,mean,num_episodes,synopsis,genres,main_picture"

    init(session: URLSession = .shared, clientID: String = AppConfiguration.malClientID) {
        self.session = session
        self.clientID = clientID
        if let info = Bundle.main.infoDictionary,
           let appName = info["CFBundleName"] as? String,
           let version = info["CFBundleShortVersionString"] as? String {
            userAgent = "\(appName)/\(version) (UltimateLibrary)"
        } else {
            userAgent = "UltimateLibrary/1.0"
        }
    }

    func fetchTopAnime(limit: Int = 20) async throws -> [Anime] {
        let queryItems = [
            URLQueryItem(name: "ranking_type", value: "bypopularity"),
            URLQueryItem(name: "limit", value: "\(limit)"),
            URLQueryItem(name: "fields", value: defaultFields),
            URLQueryItem(name: "nsfw", value: "false")
        ]
        let url = try makeURL(path: "anime/ranking", queryItems: queryItems)
        let response: MALListResponse = try await performRequest(url: url, cacheTTL: 1_800)
        return response.data.map { Anime($0.node) }
    }

    func fetchRecommendations(for genres: [AnimeGenre], limit: Int = 20) async throws -> [Anime] {
        // Fetch a wider ranking set and filter locally based on preferred genres.
        let rankingLimit = max(limit * 3, 30)
        let queryItems = [
            URLQueryItem(name: "ranking_type", value: "all"),
            URLQueryItem(name: "limit", value: "\(min(rankingLimit, 100))"),
            URLQueryItem(name: "fields", value: defaultFields),
            URLQueryItem(name: "nsfw", value: "false")
        ]
        let url = try makeURL(path: "anime/ranking", queryItems: queryItems)
        let response: MALListResponse = try await performRequest(url: url, cacheTTL: 900)
        let preferredGenreIDs = Set(genres.map(\.id))

        let filteredNodes = response.data
            .map(\.node)
            .filter { node in
                guard !preferredGenreIDs.isEmpty else { return true }
                let nodeGenres = Set(node.genres.map(\.id))
                return !preferredGenreIDs.isDisjoint(with: nodeGenres)
            }

        let selection = filteredNodes.isEmpty ? response.data.map(\.node) : filteredNodes
        return Array(selection.prefix(limit)).map(Anime.init)
    }

    func searchAnime(query: String, limit: Int = 20) async throws -> [Anime] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let queryItems = [
            URLQueryItem(name: "q", value: trimmed),
            URLQueryItem(name: "limit", value: "\(limit)"),
            URLQueryItem(name: "fields", value: defaultFields),
            URLQueryItem(name: "nsfw", value: "false")
        ]
        let url = try makeURL(path: "anime", queryItems: queryItems)
        let response: MALListResponse = try await performRequest(url: url, cacheTTL: 600)
        return response.data.map { Anime($0.node) }
    }

    private func makeURL(path: String, queryItems: [URLQueryItem]) throws -> URL {
        guard !path.isEmpty else { throw AnimeServiceError.invalidURL }
        var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)
        components?.queryItems = queryItems
        guard let url = components?.url else { throw AnimeServiceError.invalidURL }
        return url
    }

    private func performRequest<T: Decodable>(url: URL, cacheTTL: TimeInterval? = nil) async throws -> T {
        guard !clientID.isEmpty else {
            throw AnimeServiceError.missingClientID
        }

        if let cachedData = await APICache.shared.data(for: url) {
            do {
                return try JSONDecoder().decode(T.self, from: cachedData)
            } catch {
                await APICache.shared.removeData(for: url)
            }
        }

        var lastError: AnimeServiceError?

        for attempt in 0..<maxRetries {
            var request = URLRequest(url: url)
            request.timeoutInterval = 30
            request.setValue(clientID, forHTTPHeaderField: "X-MAL-CLIENT-ID")
            request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
            request.setValue("application/json", forHTTPHeaderField: "Accept")

            do {
                let (data, response) = try await session.data(for: request)
                guard let httpResponse = response as? HTTPURLResponse else {
                    throw AnimeServiceError.requestFailed(statusCode: -1)
                }

                switch httpResponse.statusCode {
                case 200..<300:
                    do {
                        let decoded = try JSONDecoder().decode(T.self, from: data)
                        await APICache.shared.store(data, for: url, ttl: cacheTTL)
                        return decoded
                    } catch {
                        throw AnimeServiceError.decodingFailed
                    }
                case 401, 403:
                    throw AnimeServiceError.requestFailed(statusCode: httpResponse.statusCode)
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
                    throw AnimeServiceError.requestFailed(statusCode: httpResponse.statusCode)
                }
            } catch let error as AnimeServiceError {
                lastError = error
            } catch {
                lastError = .networkFailure(error)
            }

            if attempt < maxRetries - 1 {
                let delay = defaultRetryDelay(forAttempt: attempt)
                try? await Task.sleep(nanoseconds: delay)
            }
        }

        throw lastError ?? AnimeServiceError.requestFailed(statusCode: -1)
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

// MARK: - MAL DTOs

private struct MALListResponse: Decodable {
    let data: [MALAnimeEntry]
}

private struct MALAnimeEntry: Decodable {
    let node: MALAnimeNode
}

private struct MALAnimeNode: Decodable {
    struct Picture: Decodable {
        let medium: String?
        let large: String?
    }

    struct GenreDTO: Decodable {
        let id: Int
        let name: String
    }

    let id: Int
    let title: String
    let synopsis: String?
    let mean: Double?
    let numEpisodes: Int?
    let mainPicture: Picture?
    let genres: [GenreDTO]

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case synopsis
        case mean
        case numEpisodes = "num_episodes"
        case mainPicture = "main_picture"
        case genres
    }
}

private extension Anime {
    init(_ node: MALAnimeNode) {
        let genres = node.genres.map { AnimeGenre(id: $0.id, name: $0.name) }
        let imageURL = secureURL(from: node.mainPicture?.large ?? node.mainPicture?.medium)
        self.init(
            id: node.id,
            title: node.title,
            synopsis: node.synopsis ?? "No synopsis available.",
            imageURL: imageURL,
            score: node.mean,
            genres: genres,
            episodeCount: node.numEpisodes
        )
    }
}

private func secureURL(from string: String?) -> URL? {
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
