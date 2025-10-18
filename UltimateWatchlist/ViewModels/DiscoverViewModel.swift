//
//  DiscoverViewModel.swift
//  UltimateWatchlist
//
//  Created by Codex on 2025-10-13.
//

import Combine
import Foundation
import SwiftData

enum DiscoverSearchScope: String, CaseIterable, Identifiable {
    case anime
    case tvShows

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .anime: return "Anime"
        case .tvShows: return "TV Shows"
        }
    }
}

@MainActor
final class DiscoverViewModel: ObservableObject {
    @Published private(set) var trending: [Anime] = []
    @Published private(set) var trendingShows: [Anime] = []
    @Published private(set) var animeRecommendations: [Anime] = []
    @Published private(set) var showRecommendations: [Anime] = []
    @Published private(set) var searchResults: [Anime] = []
    @Published var searchQuery: String = ""
    @Published var searchScope: DiscoverSearchScope = .anime {
        didSet {
            guard searchScope != oldValue else { return }
            searchTask?.cancel()
            searchResults = []
            searchErrorMessage = nil
            isSearching = false
        }
    }
    @Published private(set) var isLoadingInitial = false
    @Published private(set) var isSearching = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var showErrorMessage: String?
    @Published private(set) var searchErrorMessage: String?
    @Published private(set) var animeRecommendationsErrorMessage: String?
    @Published private(set) var showRecommendationsErrorMessage: String?
    @Published private(set) var isLoadingRecommendations = false

    private let animeService: AnimeService
    private let tvShowService: TVMazeService
    private var searchTask: Task<Void, Never>?

    @MainActor init(
        animeService: AnimeService? = nil,
        tvShowService: TVMazeService? = nil
    ) {
        self.animeService = animeService ?? .shared
        self.tvShowService = tvShowService ?? .shared
    }

    func loadInitial() {
        Task { await fetchInitialContent() }
    }

    func refreshRecommendations(using context: ModelContext) {
        Task { await fetchRecommendations(using: context) }
    }

    func searchDebounced() {
        searchTask?.cancel()
        let query = searchQuery

        searchTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled else { return }
            await self?.performSearch(query: query)
        }
    }

    func cancelSearch() {
        searchTask?.cancel()
        searchResults = []
        searchErrorMessage = nil
        isSearching = false
    }

    // MARK: - Private

    private func fetchInitialContent() async {
        guard !isLoadingInitial else { return }
        isLoadingInitial = true
        errorMessage = nil
        showErrorMessage = nil

        let trendingTask = Task { () -> Result<[Anime], Error> in
            do {
                let value = try await animeService.fetchTopAnime(limit: 25)
                return .success(value)
            } catch {
                return .failure(error)
            }
        }

        let showTask = Task { () -> Result<[Anime], Error> in
            do {
                let value = try await tvShowService.fetchPopularShows(limit: 25)
                return .success(value)
            } catch {
                return .failure(error)
            }
        }

        let trendingResult = await trendingTask.value
        let showResult = await showTask.value

        if Task.isCancelled { return }

        switch trendingResult {
        case .success(let items):
            trending = items
        case .failure(let error):
            errorMessage = error.localizedDescription
        }

        switch showResult {
        case .success(let items):
            trendingShows = sanitizedShows(from: items)
        case .failure(let error):
            showErrorMessage = error.localizedDescription
        }

        isLoadingInitial = false
    }

    private func fetchRecommendations(using context: ModelContext) async {
        isLoadingRecommendations = true
        defer { isLoadingRecommendations = false }

        let fetchDescriptor = FetchDescriptor<LibraryEntryModel>()
        let entries = (try? context.fetch(fetchDescriptor)) ?? []
        animeRecommendationsErrorMessage = nil
        showRecommendationsErrorMessage = nil
        let animeEntries = entries.filter { $0.anime.kind == .anime }
        let showEntries = entries.filter { $0.anime.kind == .tvShow }
        let animeGenres = preferredGenres(from: animeEntries, limit: 3)
        let showGenres = preferredGenres(from: showEntries, limit: 3)
        let animeLimit = animeEntries.isEmpty ? 10 : 20
        let showLimit = showEntries.isEmpty ? 10 : 20
        let libraryIDs = Set(entries.map(\.id))
        let animeFetchLimit = min(60, max(animeLimit * 2, animeLimit + libraryIDs.count))
        let showFetchLimit = min(60, max(showLimit * 2, showLimit + libraryIDs.count))

        async let animeResult = fetchAnimeRecommendations(genres: animeGenres, limit: animeFetchLimit)
        async let showResult = fetchShowRecommendations(genres: showGenres, limit: showFetchLimit)

        switch await animeResult {
        case .success(let items):
            let filtered = items.filter { !libraryIDs.contains($0.id) }
            animeRecommendations = Array(filtered.prefix(animeLimit))
            animeRecommendationsErrorMessage = nil
        case .failure(let error):
            if animeRecommendations.isEmpty {
                animeRecommendationsErrorMessage = error.localizedDescription
            }
        }

        switch await showResult {
        case .success(let items):
            let sanitized = sanitizedShows(from: items)
            let filtered = sanitized.filter { !libraryIDs.contains($0.id) }
            showRecommendations = Array(filtered.prefix(showLimit))
            showRecommendationsErrorMessage = nil
        case .failure(let error):
            if showRecommendations.isEmpty {
                showRecommendationsErrorMessage = error.localizedDescription
            }
        }
    }

    private func preferredGenres(from entries: [LibraryEntryModel], limit: Int) -> [AnimeGenre] {
        let all = entries.flatMap { $0.anime.genres }
        var counts: [Int: (name: String, count: Int)] = [:]
        for genre in all {
            counts[genre.id] = (genre.name, (counts[genre.id]?.count ?? 0) + 1)
        }
        let sorted = counts.sorted { lhs, rhs in
            if lhs.value.count == rhs.value.count {
                return lhs.value.name < rhs.value.name
            }
            return lhs.value.count > rhs.value.count
        }
        return Array(sorted.prefix(limit)).map { AnimeGenre(id: $0.key, name: $0.value.name) }
    }

    private func performSearch(query: String) async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            await MainActor.run {
                self.searchResults = []
                self.searchErrorMessage = nil
                self.isSearching = false
            }
            return
        }

        await MainActor.run {
            isSearching = true
            searchErrorMessage = nil
        }

        do {
            let scope = searchScope
            let results: [Anime]
            switch scope {
            case .anime:
                results = try await animeService.searchAnime(query: trimmed, limit: 30)
            case .tvShows:
                results = sanitizedShows(from: try await tvShowService.searchShows(query: trimmed, limit: 30))
            }
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self.searchResults = results
                self.isSearching = false
            }
        } catch {
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self.searchResults = []
                self.searchErrorMessage = error.localizedDescription
                self.isSearching = false
            }
        }
    }

    private func fetchAnimeRecommendations(genres: [AnimeGenre], limit: Int) async -> Result<[Anime], Error> {
        do {
            let items = try await animeService.fetchRecommendations(for: genres, limit: limit)
            return .success(items)
        } catch {
            return .failure(error)
        }
    }

    private func fetchShowRecommendations(genres: [AnimeGenre], limit: Int) async -> Result<[Anime], Error> {
        do {
            let items = try await tvShowService.fetchRecommendations(for: genres, limit: limit)
            return .success(items)
        } catch {
            return .failure(error)
        }
    }
    
    private func sanitizedShows(from items: [Anime]) -> [Anime] {
        items.filter { anime in
            !anime.genres.contains { $0.name.compare("Anime", options: .caseInsensitive) == .orderedSame }
        }
    }
}

#if DEBUG
extension DiscoverViewModel {
    @MainActor
    static func previewModel() -> DiscoverViewModel {
        let model = DiscoverViewModel()
        model.populatePreviewData()
        return model
    }

    @MainActor
    private func populatePreviewData() {
        let anime = Self.sampleEntries(kind: .anime, prefix: "Anime", baseID: 1)
        let shows = Self.sampleEntries(kind: .tvShow, prefix: "Show", baseID: 101)
        trending = Array(anime.prefix(6))
        trendingShows = Array(shows.prefix(6))
        animeRecommendations = Array(anime.dropFirst(2))
        showRecommendations = Array(shows.dropFirst(1))
        searchResults = Array(anime.prefix(5))
        searchQuery = "Fullmetal"
        searchScope = .anime
        errorMessage = nil
        showErrorMessage = nil
        searchErrorMessage = nil
        animeRecommendationsErrorMessage = nil
        showRecommendationsErrorMessage = nil
        isLoadingInitial = false
        isLoadingRecommendations = false
        isSearching = false
    }

    private static func sampleEntries(kind: MediaKind, prefix: String, baseID: Int) -> [Anime] {
        (0..<10).map { offset in
            let providerID = baseID + offset
            return Anime(
                id: providerID,
                title: "\(prefix) \(offset + 1)",
                synopsis: "Sample synopsis for \(prefix.lowercased()) \(offset + 1).",
                imageURL: nil,
                score: 8.0 + Double(offset) * 0.2,
                genres: [
                    AnimeGenre(id: providerID, name: "Action"),
                    AnimeGenre(id: providerID + 10, name: "Adventure")
                ],
                episodeCount: 12 + offset,
                kind: kind,
                providerID: providerID
            )
        }
    }
}
#endif
