//
//  DiscoverViewModel.swift
//  UltimateWatchlist
//
//  Created by Codex on 2025-10-13.
//

import Combine
import Foundation
import SwiftData

@MainActor
final class DiscoverViewModel: ObservableObject {
    @Published private(set) var trending: [Anime] = []
    @Published private(set) var recommendations: [Anime] = []
    @Published private(set) var searchResults: [Anime] = []
    @Published var searchQuery: String = ""
    @Published private(set) var isLoadingInitial = false
    @Published private(set) var isSearching = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var searchErrorMessage: String?

    private let service: AnimeService
    private var searchTask: Task<Void, Never>?

    @MainActor init(service: AnimeService? = nil) {
        self.service = service ?? .shared
    }

    deinit {}

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

        do {
            let trendingAnime = try await service.fetchTopAnime(limit: 25)
            trending = trendingAnime
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoadingInitial = false
    }

    private func fetchRecommendations(using context: ModelContext) async {
        let fetchDescriptor = FetchDescriptor<LibraryEntryModel>()
        let entries = (try? context.fetch(fetchDescriptor)) ?? []
        let genres = preferredGenres(from: entries, limit: 3)
        do {
            let items = try await service.fetchRecommendations(for: genres, limit: 25)
            recommendations = items
        } catch {
            if recommendations.isEmpty { errorMessage = error.localizedDescription }
        }
    }

    private func preferredGenres(from entries: [LibraryEntryModel], limit: Int) -> [AnimeGenre] {
        let all = entries.flatMap { $0.anime.genres }
        var counts: [Int: (name: String, count: Int)] = [:]
        for g in all { counts[g.id] = (g.name, (counts[g.id]?.count ?? 0) + 1) }
        let sorted = counts.sorted { lhs, rhs in
            if lhs.value.count == rhs.value.count { return lhs.value.name < rhs.value.name }
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
            let results = try await service.searchAnime(query: trimmed, limit: 30)
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
}
