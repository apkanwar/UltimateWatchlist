//
//  DiscoverView.swift
//  UltimateWatchlist
//
//  Created by Codex on 2025-10-13.
//

import SwiftUI
import SwiftData
#if canImport(UIKit)
import UIKit
#endif
#if canImport(AppKit)
import AppKit
#endif

struct DiscoverView: View {
    @Environment(\.modelContext) private var modelContext
    @StateObject private var viewModel: DiscoverViewModel
    @State private var isSearchPanelVisible = false
    @State private var isSettingsPanelVisible = false
    @State private var genreFilter: AnimeGenre?
    @State private var isAnimeRecommendationsExpanded = true
    @State private var isShowRecommendationsExpanded = true
    @State private var isMovieRecommendationsExpanded = true
#if os(iOS)
    @State private var iosSelectedCategory: DiscoverPageCategory = .anime
    @State private var iosNavigationPath: [Anime] = []
    @State private var iosSearchText: String = ""
    @State private var iosSearchScope: DiscoverSearchScope = .anime
#endif

    var selectedGenreFilter: AnimeGenre? { genreFilter }

    // Observe library changes
    @Query private var libraryEntries: [LibraryEntryModel]

    private var animeLibraryEntries: [LibraryEntryModel] {
        libraryEntries.filter { $0.anime.kind == .anime }
    }

    private var showLibraryEntries: [LibraryEntryModel] {
        libraryEntries.filter { $0.anime.kind == .tvShow }
    }

    private var movieLibraryEntries: [LibraryEntryModel] {
        libraryEntries.filter { $0.anime.kind == .movie }
    }

    init(viewModel: DiscoverViewModel, showSearchPanel: Bool = false, showSettingsPanel: Bool = false) {
        _viewModel = StateObject(wrappedValue: viewModel)
        _libraryEntries = Query()
        _isSearchPanelVisible = State(initialValue: showSearchPanel)
        _isSettingsPanelVisible = State(initialValue: showSettingsPanel)
    }

    var body: some View {
#if os(iOS)
        iosBody
#else
        macBody
#endif
    }

#if os(iOS)
    private var iosBody: some View {
        NavigationStack(path: $iosNavigationPath) {
            Group {
                if iosSearchIsActive {
                    iosSearchResultsView
                } else {
                    VStack(spacing: 16) {
                        if let filter = genreFilter {
                            genreFilterIndicator(filter: filter)
                                .padding(.horizontal, 4)
                        }

                        Picker("Category", selection: $iosSelectedCategory) {
                            ForEach(DiscoverPageCategory.allCases) { category in
                                Text(category.title).tag(category)
                            }
                        }
                        .pickerStyle(.segmented)

                        TabView(selection: $iosSelectedCategory) {
                            iosRecommendationsPage(for: .anime)
                                .tag(DiscoverPageCategory.anime)

                            iosRecommendationsPage(for: .shows)
                                .tag(DiscoverPageCategory.shows)

                            iosRecommendationsPage(for: .movies)
                                .tag(DiscoverPageCategory.movies)
                        }
                        .tabViewStyle(.page(indexDisplayMode: .never))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    .padding(.top, 20)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                }
            }
            .background(backgroundColor.ignoresSafeArea())
            .navigationTitle("Discover")
            .navigationDestination(for: Anime.self) { anime in
                ScrollView {
                    AnimeDetailCardView(anime: anime, onGenreTap: handleGenreTap, allowLocalMediaLinking: false)
                        .padding(20)
                }
                .background(backgroundColor)
                .navigationTitle(anime.title)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        refreshRecommendationsIfNeeded(force: true)
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .accessibilityLabel("Refresh recommendations")
                }
            }
        }
        .task {
            refreshRecommendationsIfNeeded(force: true)
        }
        .onChange(of: libraryEntries) { _, _ in
            refreshRecommendationsIfNeeded(force: true)
        }
        .searchable(
            text: $iosSearchText,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: "Search anime, TV shows, or movies"
        )
        .searchScopes($iosSearchScope) {
            ForEach(DiscoverSearchScope.allCases) { scope in
                Text(scope.displayName).tag(scope)
            }
        }
        .onChange(of: iosSearchText) { _, newValue in
            let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            viewModel.searchQuery = trimmed
            if trimmed.isEmpty {
                viewModel.cancelSearch()
            } else {
                viewModel.searchDebounced()
            }
        }
        .onChange(of: iosSearchScope) { _, newScope in
            viewModel.searchScope = newScope
            if iosSearchIsActive {
                viewModel.searchDebounced()
            }
        }
        .onSubmit(of: .search) {
            if iosSearchIsActive {
                viewModel.searchDebounced()
            }
        }
    }
#else
    private var macBody: some View {
        NavigationStack {
            GeometryReader { geometry in
                ZStack(alignment: .trailing) {
                    // Main content stays full width
                    mainContent(width: geometry.size.width)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                    if isSearchPanelVisible || isSettingsPanelVisible {
                        Color.black.opacity(0.18)
                            .ignoresSafeArea()
                            .transition(.opacity)
                            .onTapGesture { hideAllPanels() }
                            .zIndex(0.5)
                    }

                    if isSearchPanelVisible {
                        let width = panelWidth(for: geometry.size.width)
                        DiscoverSearchPanel(
                            viewModel: viewModel,
                            isPresented: $isSearchPanelVisible,
                            onGenreTap: handleGenreTap
                        )
                        .frame(width: width)
                        .padding(.trailing, geometry.size.width >= 520 ? 12 : 0)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                        .zIndex(1)
                    }

                    if isSettingsPanelVisible {
                        let width = panelWidth(for: geometry.size.width)
                        SettingsPanel(
                            isPresented: $isSettingsPanelVisible
                        ) {
                            // Embed your existing settings content
                            SettingsView()
                        }
                        .frame(width: width)
                        .padding(.trailing, geometry.size.width >= 520 ? 12 : 0)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                        .zIndex(1)
                    }
                }
                .animation(.easeInOut(duration: 0.25), value: isSearchPanelVisible)
                .animation(.easeInOut(duration: 0.25), value: isSettingsPanelVisible)
            }
            .navigationTitle("Discover")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    HStack(spacing: 14) {
                        Button {
                            withAnimation(.easeInOut(duration: 0.25)) {
                                if isSearchPanelVisible {
                                    isSearchPanelVisible = false
                                }
                                isSettingsPanelVisible.toggle()
                                if isSettingsPanelVisible {
                                    isSearchPanelVisible = false
                                }
                            }
                        } label: {
                            Image(systemName: isSettingsPanelVisible ? "xmark" : "gearshape")
                        }
                        .accessibilityLabel(isSettingsPanelVisible ? "Hide settings panel" : "Show settings panel")

                        Button {
                            withAnimation(.easeInOut(duration: 0.25)) {
                                if isSettingsPanelVisible {
                                    isSettingsPanelVisible = false
                                }
                                isSearchPanelVisible.toggle()
                                if isSearchPanelVisible {
                                    isSettingsPanelVisible = false
                                }
                            }
                        } label: {
                            Image(systemName: isSearchPanelVisible ? "xmark" : "magnifyingglass")
                        }
                        .accessibilityLabel(isSearchPanelVisible ? "Hide search panel" : "Show search panel")
                    }
                }
            }
            .navigationDestination(for: Anime.self) { anime in
                ScrollView {
                    AnimeDetailCardView(anime: anime, onGenreTap: handleGenreTap, allowLocalMediaLinking: false)
                        .padding(20)
                }
                .background(backgroundColor)
                .navigationTitle(anime.title)
            }
            .background(backgroundColor.ignoresSafeArea())
        }
        .onChange(of: viewModel.searchQuery) { _, _ in viewModel.searchDebounced() }
        .onChange(of: isSearchPanelVisible) { _, visible in
            guard !visible else { return }
            viewModel.searchQuery = ""
            viewModel.cancelSearch()
        }
        .task {
            refreshRecommendationsIfNeeded(force: true)
        }
        .onChange(of: libraryEntries) { _, _ in
            refreshRecommendationsIfNeeded(force: true)
        }
    }
#endif

    private func hideSearchPanel() { withAnimation(.easeInOut(duration: 0.2)) { isSearchPanelVisible = false } }

    private func hideAllPanels() {
        withAnimation(.easeInOut(duration: 0.2)) {
            isSearchPanelVisible = false
            isSettingsPanelVisible = false
        }
    }

    private func panelWidth(for containerWidth: CGFloat) -> CGFloat {
        let minWidth: CGFloat = 320
        let ideal = containerWidth * 0.42
        let maxWidth: CGFloat = 420
        return min(max(ideal, minWidth), maxWidth)
    }

    private func refreshRecommendationsIfNeeded(force: Bool = false) {
        let now = Date()
        if !force,
           let last = AppUserDefaults.lastRecommendationsRefreshDate(),
           now.timeIntervalSince(last) < 60 * 60 * 24 {
            return
        }
        viewModel.refreshRecommendations(using: modelContext)
        AppUserDefaults.setLastRecommendationsRefreshDate(now)
    }

#if os(iOS)
    private func iosRecommendationsPage(for category: DiscoverPageCategory) -> some View {
        let allItems: [Anime]
        let errorMessage: String?
        let hasPersonalised: Bool
        let nonPersonalisedMessage: String
        let emptyFallbackMessage: String
        let scopeLabel: String

        switch category {
        case .anime:
            allItems = viewModel.animeRecommendations
            errorMessage = viewModel.animeRecommendationsErrorMessage
            hasPersonalised = !animeLibraryEntries.isEmpty
            nonPersonalisedMessage = "Showing top 10 highest rated anime. Add anime to your library for personalised picks."
            emptyFallbackMessage = "No anime recommendations available right now. Try again later."
            scopeLabel = "anime"
        case .shows:
            allItems = viewModel.showRecommendations
            errorMessage = viewModel.showRecommendationsErrorMessage
            hasPersonalised = !showLibraryEntries.isEmpty
            nonPersonalisedMessage = "Showing top 10 highest rated TV shows. Add shows to your library for personalised picks."
            emptyFallbackMessage = "No TV show recommendations available right now. Try again later."
            scopeLabel = "TV shows"
        case .movies:
            allItems = viewModel.movieRecommendations
            errorMessage = viewModel.movieRecommendationsErrorMessage
            hasPersonalised = !movieLibraryEntries.isEmpty
            nonPersonalisedMessage = "Showing top 10 highest rated movies. Add movies to your library for personalised picks."
            emptyFallbackMessage = "No movie recommendations available right now. Try again later."
            scopeLabel = "movies"
        }

        let items = filteredMedia(allItems)
        let isLoading = viewModel.isLoadingRecommendations && allItems.isEmpty
        let lastID = items.last?.id

        return ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if isLoading {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Loading \(scopeLabel) recommendations…")
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 220, alignment: .center)
                    .padding(.vertical, 24)
                } else if items.isEmpty {
                    if genreFilter != nil, !allItems.isEmpty {
                        Text("No titles match the selected genre.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 40)
                            .frame(maxWidth: .infinity, alignment: .center)
                    } else if let message = errorMessage {
                        Text(message)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.vertical, 40)
                            .frame(maxWidth: .infinity, alignment: .center)
                    } else {
                        Text(emptyFallbackMessage)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.vertical, 40)
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                } else {
                    if !hasPersonalised {
                        Text(nonPersonalisedMessage)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 4)
                            .padding(.bottom, 12)
                    }

                    ForEach(items) { anime in
                        VStack(spacing: 0) {
                            AnimeRowView(anime: anime)
                                .padding(.horizontal, 4)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    iosNavigationPath.append(anime)
                                }

                            if anime.id != lastID {
                                Divider()
                                    .padding(.leading, 92)
                                    .padding(.vertical, 6)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .animation(.easeInOut(duration: 0.18), value: items.count)
                }
            }
            .padding(.top, 4)
            .padding(.bottom, 24)
        }
        .background(backgroundColor)
        .refreshable {
            refreshRecommendationsIfNeeded(force: true)
        }
    }

    private var iosSearchIsActive: Bool {
        !viewModel.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var iosSearchResultsView: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if let filter = genreFilter {
                    genreFilterIndicator(filter: filter)
                        .padding(.horizontal, 4)
                        .padding(.bottom, 12)
                }

                if viewModel.isSearching {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Searching…")
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 220, alignment: .center)
                    .padding(.vertical, 24)
                } else if let message = viewModel.searchErrorMessage, !message.isEmpty {
                    Text(message)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 40)
                        .frame(maxWidth: .infinity, alignment: .center)
                } else if viewModel.searchResults.isEmpty {
                    Text("No \(discoverScopeLabel(viewModel.searchScope)) found for \"\(viewModel.searchQuery)\".")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 40)
                        .frame(maxWidth: .infinity, alignment: .center)
                } else {
                    let lastID = viewModel.searchResults.last?.id
                    ForEach(viewModel.searchResults) { anime in
                        VStack(spacing: 0) {
                            AnimeRowView(anime: anime)
                                .padding(.horizontal, 4)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    iosNavigationPath.append(anime)
                                }

                            if anime.id != lastID {
                                Divider()
                                    .padding(.leading, 92)
                                    .padding(.vertical, 6)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .padding(.top, 12)
            .padding(.horizontal, 16)
            .padding(.bottom, 32)
        }
        .background(backgroundColor.ignoresSafeArea())
    }
#endif

    private func mainContent(width: CGFloat) -> some View {
        Group {
            if viewModel.isLoadingRecommendations && viewModel.animeRecommendations.isEmpty && viewModel.showRecommendations.isEmpty && viewModel.movieRecommendations.isEmpty {
                ProgressView("Loading recommendations…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        if let filter = genreFilter { genreFilterIndicator(filter: filter) }
                        animeRecommendationsSection(width: width)
                        showRecommendationsSection(width: width)
                        movieRecommendationsSection(width: width)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 28)
                }
                .background(backgroundColor)
            }
        }
    }

    private func animeRecommendationsSection(width: CGFloat) -> some View {
        let items = filteredMedia(viewModel.animeRecommendations)
        let hasPersonalisedAnime = !animeLibraryEntries.isEmpty

        return VStack(alignment: .leading, spacing: 12) {
            sectionHeader(
                title: "Anime Recommendations",
                isExpanded: $isAnimeRecommendationsExpanded,
                currentPage: 0,
                totalPages: 1,
                onPrevious: {},
                onNext: {}
            )

            if isAnimeRecommendationsExpanded {
                if viewModel.isLoadingRecommendations && viewModel.animeRecommendations.isEmpty {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text("Loading anime recommendations…")
                            .foregroundStyle(.secondary)
                    }
                } else if items.isEmpty {
                    if genreFilter != nil, !viewModel.animeRecommendations.isEmpty {
                        Text("No titles match the selected genre.")
                            .foregroundStyle(.secondary)
                    } else if let message = viewModel.animeRecommendationsErrorMessage {
                        Text(message).foregroundStyle(.secondary)
                    } else {
                        Text("No anime recommendations available right now. Try again later.")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    if !hasPersonalisedAnime {
                        Text("Showing top 10 highest rated anime. Add anime to your library for personalised picks.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    horizontalCarousel(for: items, availableWidth: width)
                }
            }
        }
    }

    private func showRecommendationsSection(width: CGFloat) -> some View {
        let items = filteredMedia(viewModel.showRecommendations)
        let hasPersonalisedShows = !showLibraryEntries.isEmpty

        return VStack(alignment: .leading, spacing: 12) {
            sectionHeader(
                title: "Show Recommendations",
                isExpanded: $isShowRecommendationsExpanded,
                currentPage: 0,
                totalPages: 1,
                onPrevious: {},
                onNext: {}
            )

            if isShowRecommendationsExpanded {
                if viewModel.isLoadingRecommendations && viewModel.showRecommendations.isEmpty {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text("Loading show recommendations…")
                            .foregroundStyle(.secondary)
                    }
                } else if items.isEmpty {
                    if genreFilter != nil, !viewModel.showRecommendations.isEmpty {
                        Text("No titles match the selected genre.")
                            .foregroundStyle(.secondary)
                    } else if let message = viewModel.showRecommendationsErrorMessage {
                        Text(message).foregroundStyle(.secondary)
                    } else {
                        Text("No show recommendations available right now. Try again later.")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    if !hasPersonalisedShows {
                        Text("Showing top 10 highest rated TV shows. Add shows to your library for personalised picks.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    horizontalCarousel(for: items, availableWidth: width)
                }
            }
        }
    }

    private func movieRecommendationsSection(width: CGFloat) -> some View {
        let items = filteredMedia(viewModel.movieRecommendations)
        let hasPersonalisedMovies = !movieLibraryEntries.isEmpty

        return VStack(alignment: .leading, spacing: 12) {
            sectionHeader(
                title: "Movie Recommendations",
                isExpanded: $isMovieRecommendationsExpanded,
                currentPage: 0,
                totalPages: 1,
                onPrevious: {},
                onNext: {}
            )

            if isMovieRecommendationsExpanded {
                if viewModel.isLoadingRecommendations && viewModel.movieRecommendations.isEmpty {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text("Loading movie recommendations…")
                            .foregroundStyle(.secondary)
                    }
                } else if items.isEmpty {
                    if genreFilter != nil, !viewModel.movieRecommendations.isEmpty {
                        Text("No titles match the selected genre.")
                            .foregroundStyle(.secondary)
                    } else if let message = viewModel.movieRecommendationsErrorMessage {
                        Text(message).foregroundStyle(.secondary)
                    } else {
                        Text("No movie recommendations available right now. Try again later.")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    if !hasPersonalisedMovies {
                        Text("Showing top 10 highest rated movies. Add movies to your library for personalised picks.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    horizontalCarousel(for: items, availableWidth: width)
                }
            }
        }
    }

    private func horizontalCarousel(for items: [Anime], availableWidth: CGFloat) -> some View {
        let horizontalPadding: CGFloat = 40
        let usableWidth = max(availableWidth - horizontalPadding, 320)
        let cardWidth = min(max(usableWidth * 0.38, 220), 340)

        return ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 16) {
                ForEach(items) { anime in
                    AnimeDetailCardView(
                        anime: anime,
                        onGenreTap: handleGenreTap,
                        allowLocalMediaLinking: false,
                        synopsisLineLimit: 4,
                        enforceMacUniformLayout: true
                    )
                    .frame(width: cardWidth)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func sectionHeader(
        title: String,
        isExpanded: Binding<Bool>,
        currentPage: Int,
        totalPages: Int,
        onPrevious: @escaping () -> Void,
        onNext: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 12) {
            Button {
                withAnimation(.easeInOut) { isExpanded.wrappedValue.toggle() }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: isExpanded.wrappedValue ? "chevron.down.circle.fill" : "chevron.right.circle.fill")
                        .imageScale(.small)
                    Text(title)
                        .font(.title3.weight(.semibold))
                }
            }
            .buttonStyle(.plain)

            Spacer()

            if totalPages > 1 {
                HStack(spacing: 8) {
                    Button(action: onPrevious) {
                        Image(systemName: "chevron.left")
                    }
                    .buttonStyle(.borderless)
                    .disabled(currentPage <= 0)

                    Text("\(currentPage + 1) / \(totalPages)")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)

                    Button(action: onNext) {
                        Image(systemName: "chevron.right")
                    }
                    .buttonStyle(.borderless)
                    .disabled(currentPage >= totalPages - 1)
                }
            }
        }
    }

    private func filteredMedia(_ items: [Anime]) -> [Anime] {
        guard let filter = genreFilter else { return items }
        let target = filter.name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        return items.filter { anime in
            anime.genres.contains {
                $0.name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current) == target
            }
        }
    }

    func genreFilterIndicator(filter: AnimeGenre) -> some View {
        HStack(spacing: 12) {
            Label("Filtering by \(filter.name)", systemImage: "line.3.horizontal.decrease.circle")
                .font(.subheadline.weight(.semibold))
            Spacer()
            Button {
                withAnimation(.easeInOut) { genreFilter = nil }
            } label: {
                Label("Clear", systemImage: "xmark.circle")
            }
            .buttonStyle(.borderless)
        }
        .padding(14)
        .background(filterBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func handleGenreTap(_ genre: AnimeGenre) { withAnimation(.easeInOut) { genreFilter = genre } }

    private var backgroundColor: Color {
        #if canImport(UIKit)
        return Color(UIColor.systemGroupedBackground)
        #elseif canImport(AppKit)
        return Color(NSColor.windowBackgroundColor)
        #else
        return Color.secondary.opacity(0.1)
        #endif
    }

    private var filterBackground: Color {
        #if canImport(UIKit)
        return Color(UIColor.secondarySystemGroupedBackground)
        #elseif canImport(AppKit)
        return Color(NSColor.controlBackgroundColor)
        #else
        return Color.secondary.opacity(0.12)
        #endif
    }
}

#if os(iOS)
private enum DiscoverPageCategory: Int, CaseIterable, Identifiable {
    case anime
    case shows
    case movies

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .anime: return "Anime"
        case .shows: return "TV Shows"
        case .movies: return "Movies"
        }
    }
}
#endif

private struct DiscoverSearchPanel: View {
    @ObservedObject var viewModel: DiscoverViewModel
    @Binding var isPresented: Bool
    var onGenreTap: (AnimeGenre) -> Void

    @FocusState private var isSearchFieldFocused: Bool

    private var searchBinding: Binding<String> {
        Binding(
            get: { viewModel.searchQuery },
            set: { newValue in viewModel.searchQuery = newValue }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("Search", systemImage: "magnifyingglass").font(.headline)
            }

            Picker("Type", selection: $viewModel.searchScope) {
                ForEach(DiscoverSearchScope.allCases) { scope in
                    Text(scope.displayName).tag(scope)
                }
            }
            .pickerStyle(.segmented)

            TextField("Search titles", text: searchBinding)
                .textFieldStyle(.roundedBorder)
#if os(iOS)
                .textInputAutocapitalization(.never)
#endif
                .disableAutocorrection(true)
                .focused($isSearchFieldFocused)
                .onSubmit { viewModel.searchDebounced() }

            Divider()

            if viewModel.isSearching {
                HStack(spacing: 8) { ProgressView(); Text("Searching…").foregroundStyle(.secondary) }
                    .frame(maxWidth: .infinity, alignment: .center)
            } else if let message = viewModel.searchErrorMessage {
                Text(message)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else if viewModel.searchResults.isEmpty {
                Text(viewModel.searchQuery.isEmpty ? "Type a title to start searching." : "No \(discoverScopeLabel(viewModel.searchScope)) found for \"\(viewModel.searchQuery)\".")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        ForEach(viewModel.searchResults) { anime in
                            AnimeDetailCardView(
                                anime: anime,
                                onGenreTap: { genre in
                                    onGenreTap(genre)
                                    viewModel.searchQuery = ""
                                    viewModel.cancelSearch()
                                },
                                allowLocalMediaLinking: false,
                                synopsisLineLimit: 4,
                                enforceMacUniformLayout: true
                            )
                        }
                    }
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(panelBackgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: Color.black.opacity(0.12), radius: 18, x: 0, y: 10)
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Color.primary.opacity(0.05)))
        .onChange(of: viewModel.searchScope) { _, _ in
            if !viewModel.searchQuery.isEmpty {
                viewModel.searchDebounced()
            }
        }
        .onAppear { isSearchFieldFocused = true }
    }

    private func closePanel() {
        withAnimation(.easeInOut(duration: 0.2)) { isPresented = false }
        viewModel.searchQuery = ""
        viewModel.cancelSearch()
    }

    private func scopeLabel(for scope: DiscoverSearchScope) -> String {
        switch scope {
        case .anime: return "anime"
        case .tvShows: return "TV shows"
        case .movies: return "movies"
        }
    }

    private var panelBackgroundColor: Color {
        #if canImport(UIKit)
        return Color(UIColor.systemBackground)
        #elseif canImport(AppKit)
        return Color(NSColor.windowBackgroundColor)
        #else
        return Color.white
        #endif
    }
}

private struct SettingsPanel<Content: View>: View {
    @Binding var isPresented: Bool
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label("Settings", systemImage: "gearshape").font(.headline)
                Spacer()
            }
            .padding(.bottom, 12)

            Divider()
                .padding(.bottom, 12)

            content()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(panelBackgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: Color.black.opacity(0.12), radius: 18, x: 0, y: 10)
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Color.primary.opacity(0.05)))
    }

    private var panelBackgroundColor: Color {
        #if canImport(UIKit)
        return Color(UIColor.systemBackground)
        #elseif canImport(AppKit)
        return Color(NSColor.windowBackgroundColor)
        #else
        return Color.white
        #endif
    }
}

private func discoverScopeLabel(_ scope: DiscoverSearchScope) -> String {
    switch scope {
    case .anime: return "anime"
    case .tvShows: return "TV shows"
    case .movies: return "movies"
    }
}

#if DEBUG
#Preview("Recommendations") {
    let container = PreviewData.makeContainer(populated: true)
    return DiscoverView(viewModel: DiscoverViewModel.previewModel())
        .modelContainer(container)
}

#Preview("Search Panel") {
    let container = PreviewData.makeContainer(populated: true)
    return DiscoverView(viewModel: DiscoverViewModel.previewModel(), showSearchPanel: true)
        .modelContainer(container)
}

#Preview("Settings Panel") {
    let container = PreviewData.makeContainer(populated: true)
    return DiscoverView(viewModel: DiscoverViewModel.previewModel(), showSettingsPanel: true)
        .modelContainer(container)
}
#endif
