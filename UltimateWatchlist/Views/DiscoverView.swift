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

    var selectedGenreFilter: AnimeGenre? { genreFilter }

    // Observe watchlist changes
    @Query private var watchlistEntries: [LibraryEntryModel]

    init(viewModel: DiscoverViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
        _watchlistEntries = Query()
    }

    var body: some View {
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
            viewModel.loadInitial()
            refreshRecommendationsIfNeeded()
        }
        .onChange(of: watchlistEntries) { _, _ in
            refreshRecommendationsIfNeeded()
        }
    }

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

    private func refreshRecommendationsIfNeeded() {
        let key = "com.codex.UltimateWatchlist.lastRecommendationsRefresh"
        let defaults = UserDefaults.standard
        let now = Date()
        if let last = defaults.object(forKey: key) as? Date, now.timeIntervalSince(last) < 60 * 60 * 24 {
            return
        }
        viewModel.refreshRecommendations(using: modelContext)
        defaults.set(now, forKey: key)
    }

    private func mainContent(width: CGFloat) -> some View {
        Group {
            if viewModel.isLoadingInitial && viewModel.trending.isEmpty {
                ProgressView("Loading anime…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = viewModel.errorMessage, viewModel.trending.isEmpty {
                VStack(spacing: 16) {
                    ContentUnavailableView(
                        "Unable to load anime",
                        systemImage: "wifi.slash",
                        description: Text(error)
                    )
                    Button {
                        viewModel.loadInitial()
                    } label: {
                        Label("Retry", systemImage: "arrow.clockwise")
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        if let filter = genreFilter { genreFilterIndicator(filter: filter) }
                        recommendationsSection(width: width)
                        trendingSection(width: width)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 28)
                }
                .background(backgroundColor)
            }
        }
    }

    private func recommendationsSection(width: CGFloat) -> some View {
        let items = Array(filteredAnime(viewModel.recommendations).prefix(12))
        return VStack(alignment: .leading, spacing: 12) {
            Text("For You")
                .font(.title3.weight(.semibold))

            if watchlistEntries.isEmpty {
                Text("Add anime to your library to get personalised suggestions.")
                    .foregroundStyle(.secondary)
            } else if items.isEmpty {
                if viewModel.isLoadingInitial {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text("Loading recommendations…")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text("We couldn't find recommendations right now. Try again later.")
                        .foregroundStyle(.secondary)
                }
            } else {
                responsiveGrid(for: items, availableWidth: width)
            }
        }
    }

    private func trendingSection(width: CGFloat) -> some View {
        let items = Array(filteredAnime(viewModel.trending).prefix(12))
        return VStack(alignment: .leading, spacing: 12) {
            Text("Trending Now")
                .font(.title3.weight(.semibold))

            if items.isEmpty {
                Text(genreFilter != nil ? "No titles match the selected genre." : "Trending titles are currently unavailable.")
                    .foregroundStyle(.secondary)
            } else {
                responsiveGrid(for: items, availableWidth: width)
            }
        }
    }

    @ViewBuilder
    private func responsiveGrid(for items: [Anime], availableWidth: CGFloat) -> some View {
        let columns = columns(for: availableWidth)
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(items) { anime in
                AnimeDetailCardView(
                    anime: anime,
                    onGenreTap: handleGenreTap,
                    allowLocalMediaLinking: false,
                    synopsisLineLimit: 5
                )
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private func columns(for availableWidth: CGFloat) -> [GridItem] {
        let horizontalPadding: CGFloat = 40
        let spacing: CGFloat = 20
        let usableWidth = max(availableWidth - horizontalPadding, 320)
        let minColumnWidth: CGFloat = 320
        let maxColumns = 4

        var columnCount = Int((usableWidth + spacing) / (minColumnWidth + spacing))
        columnCount = max(1, min(maxColumns, columnCount))

        let columnWidth = (usableWidth - CGFloat(columnCount - 1) * spacing) / CGFloat(columnCount)
        let column = GridItem(.flexible(minimum: columnWidth, maximum: columnWidth), spacing: spacing)
        return Array(repeating: column, count: columnCount)
    }

    private func filteredAnime(_ items: [Anime]) -> [Anime] {
        guard let filter = genreFilter else { return items }
        return items.filter { anime in
            anime.genres.contains(where: { $0.id == filter.id })
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

            TextField("Search anime", text: searchBinding)
                .textFieldStyle(.roundedBorder)
#if os(iOS)
                .textInputAutocapitalization(.never)
#endif
                .disableAutocorrection(true)
                .focused($isSearchFieldFocused)
                .onSubmit { viewModel.searchDebounced() }

            Divider()

            Group {
                if viewModel.isSearching {
                    HStack(spacing: 8) { ProgressView(); Text("Searching…").foregroundStyle(.secondary) }
                        .frame(maxWidth: .infinity, alignment: .center)
                } else if let message = viewModel.searchErrorMessage {
                    Text(message).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
                } else if viewModel.searchResults.isEmpty {
                    Text(viewModel.searchQuery.isEmpty ? "Type a title to start searching." : "No anime found for \"\(viewModel.searchQuery)\".")
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
                                    synopsisLineLimit: 5,
                                    cardHeight: 360
                                )
                            }
                        }
                        .padding(.bottom, 12)
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
        .onAppear { isSearchFieldFocused = true }
    }

    private func closePanel() {
        withAnimation(.easeInOut(duration: 0.2)) { isPresented = false }
        viewModel.searchQuery = ""
        viewModel.cancelSearch()
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

#if DEBUG
#Preview {
    // In-memory SwiftData container for previews
    let container = try! ModelContainer(for: AnimeModel.self, AnimeGenreModel.self, LibraryEntryModel.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    return DiscoverView(viewModel: DiscoverViewModel())
        .modelContainer(container)
}
#endif
