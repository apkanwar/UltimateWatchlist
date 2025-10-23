//
//  LibraryView.swift
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

private enum LibraryViewMode: String, CaseIterable, Identifiable {
    case alphabetical = "Alphabetical"
    case lastAdded = "Last Updated"
    case folderLinked = "Folder Linked"

    var id: String { rawValue }
    var display: String { rawValue }
}

#if os(iOS)
private enum LibraryCategory: Int, CaseIterable, Identifiable {
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

struct LibraryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: [SortDescriptor(\LibraryEntryModel.addedAt, order: .reverse)]) private var entries: [LibraryEntryModel]
    @State private var genreFilter: AnimeGenre?
    @State private var viewMode: LibraryViewMode = .lastAdded
#if os(iOS)
    @State private var iosSelectedCategory: LibraryCategory = .anime
    @State private var iosSearchText: String = ""
    @State private var iosNavigationPath: [Anime] = []
#endif

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
                if entries.isEmpty {
                    ContentUnavailableView(
                        "Your library is empty",
                        systemImage: "tray",
                        description: Text("Use the Discover tab to search for anime, TV shows, or movies and add them to your library.")
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    LibraryPagedContentiOS(
                        genreFilter: $genreFilter,
                        entries: entries,
                        viewMode: $viewMode,
                        selectedCategory: $iosSelectedCategory,
                        searchText: $iosSearchText
                    ) { anime in
                        iosNavigationPath.append(anime)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .background(libraryBackgroundColor.ignoresSafeArea())
            .navigationTitle("Library")
            .navigationDestination(for: Anime.self) { anime in
                ScrollView {
                    AnimeDetailCardView(
                        anime: anime,
                        onGenreTap: { genre in withAnimation { genreFilter = genre } },
                        allowLocalMediaLinking: true
                    )
                    .padding(20)
                }
                .background(libraryBackgroundColor)
                .navigationTitle(anime.title)
            }
        }
        .searchable(text: $iosSearchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search library")
    }
#else
    private var macBody: some View {
        NavigationStack {
            if entries.isEmpty {
                ContentUnavailableView(
                    "Your library is empty",
                    systemImage: "tray",
                    description: Text("Use the Discover tab to search for anime, TV shows, or movies and add them to your library.")
                )
                .navigationTitle("Library")
            } else {
                LibraryContent(
                    genreFilter: $genreFilter,
                    allEntries: entries,
                    viewMode: $viewMode
                )
                .navigationTitle("Library")
                .navigationDestination(for: Anime.self) { anime in
                    ScrollView {
                        AnimeDetailCardView(
                            anime: anime,
                            onGenreTap: { genre in withAnimation { genreFilter = genre } },
                            allowLocalMediaLinking: true
                        )
                        .padding(20)
                    }
                    .navigationTitle(anime.title)
                }
            }
        }
    }
#endif

    private var libraryBackgroundColor: Color {
        #if canImport(UIKit)
        return Color(UIColor.systemGroupedBackground)
        #elseif canImport(AppKit)
        return Color(NSColor.windowBackgroundColor)
        #else
        return Color.secondary.opacity(0.1)
        #endif
    }
}

#if DEBUG
#Preview("Empty Library") {
    LibraryView()
        .modelContainer(PreviewData.makeContainer(populated: false))
        .environmentObject(AppNavigation())
        .environmentObject(PlaybackCoordinator())
}

#Preview("Populated Library") {
    LibraryView()
        .modelContainer(PreviewData.makeContainer(populated: true))
        .environmentObject(AppNavigation())
        .environmentObject(PlaybackCoordinator())
}
#endif

private struct LibraryContent: View {
    @Binding var genreFilter: AnimeGenre?
    let allEntries: [LibraryEntryModel]
    @Binding var viewMode: LibraryViewMode
    @State private var searchText: String = ""

    var body: some View {
        let sortedEntries = sortEntries(allEntries, by: viewMode)
        let searchedEntries = searchEntries(sortedEntries, query: searchText)
        let animeEntries = searchedEntries.filter { $0.anime.kind == .anime }
        let tvEntries = searchedEntries.filter { $0.anime.kind == .tvShow && !isAnimeGenre($0.anime) }
        let movieEntries = searchedEntries.filter { $0.anime.kind == .movie }
        let animeTitle = "Anime"
        let tvTitle = "TV Shows"
        let movieTitle = "Movies"

        return ScrollView {
            VStack(spacing: 20) {
                if let filter = genreFilter {
                    genreFilterIndicator(filter: filter)
                        .padding(.horizontal)
                }

                if animeEntries.isEmpty && tvEntries.isEmpty && movieEntries.isEmpty {
                    ContentUnavailableView(
                        "No titles match your filters",
                        systemImage: "tray",
                        description: Text("Adjust your filters or search terms to see your saved titles.")
                    )
                    .padding(.horizontal)
                    .frame(maxWidth: .infinity, minHeight: 240)
                } else {
                    VStack(spacing: 28) {
                        if !animeEntries.isEmpty {
                            LibrarySectionView(
                                title: animeTitle,
                                entries: animeEntries,
                                genreFilter: genreFilter,
                                viewMode: viewMode,
                                onGenreTap: { genre in withAnimation { genreFilter = genre } }
                            )
                            .transition(.opacity)
                        }
                        if !tvEntries.isEmpty {
                            LibrarySectionView(
                                title: tvTitle,
                                entries: tvEntries,
                                genreFilter: genreFilter,
                                viewMode: viewMode,
                                onGenreTap: { genre in withAnimation { genreFilter = genre } }
                            )
                            .transition(.opacity)
                        }
                        if !movieEntries.isEmpty {
                            LibrarySectionView(
                                title: movieTitle,
                                entries: movieEntries,
                                genreFilter: genreFilter,
                                viewMode: viewMode,
                                onGenreTap: { genre in withAnimation { genreFilter = genre } }
                            )
                            .transition(.opacity)
                        }
                    }
                    .padding(.horizontal)
                }
            }
            .padding(.vertical, 18)
        }
        .safeAreaInset(edge: .top) {
            headerControls
                .padding(.horizontal)
                .background(
                    Rectangle()
                        .fill(.clear)
                        .background(.ultraThinMaterial)
                )
                .overlay(
                    Divider()
                        .opacity(0.5)
                        .padding(.top, -0.5)
                    , alignment: .bottom
                )
        }
    }

    private var headerControls: some View {
        HStack(alignment: .top, spacing: 20) {
            Picker("Sort", selection: $viewMode) {
                ForEach(LibraryViewMode.allCases) { mode in
                    Text(mode.display).tag(mode)
                }
            }
            .pickerStyle(.menu)
            
            Spacer()
            TextField("Search library", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 320)
#if os(iOS)
                .textInputAutocapitalization(.never)
#endif
                .disableAutocorrection(true)
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func genreFilterIndicator(filter: AnimeGenre) -> some View {
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
        .background(filterBackgroundColor, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var filterBackgroundColor: Color {
        #if canImport(UIKit)
        Color(UIColor.secondarySystemGroupedBackground)
        #else
        Color.secondary.opacity(0.12)
        #endif
    }

}

private func sortEntries(_ entries: [LibraryEntryModel], by viewMode: LibraryViewMode) -> [LibraryEntryModel] {
    switch viewMode {
    case .lastAdded:
        return entries.sorted(by: { $0.addedAt > $1.addedAt })
    case .alphabetical:
        return entries.sorted {
            $0.anime.title.localizedCaseInsensitiveCompare($1.anime.title) == .orderedAscending
        }
    case .folderLinked:
        return entries
            .filter { $0.linkedFolderBookmarkData != nil }
            .sorted(by: { $0.addedAt > $1.addedAt })
    }
}

private func searchEntries(_ entries: [LibraryEntryModel], query: String) -> [LibraryEntryModel] {
    let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return entries }
    let normalizedQuery = trimmed.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    return entries.filter { entry in
        let title = entry.anime.title.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        if title.contains(normalizedQuery) { return true }
        return entry.anime.genres.contains {
            $0.name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current).contains(normalizedQuery)
        }
    }
}

private func entriesFilteredByGenre(_ entries: [LibraryEntryModel], using genreFilter: AnimeGenre?) -> [LibraryEntryModel] {
    guard let filter = genreFilter else { return entries }
    let target = filter.name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    return entries.filter { entry in
        entry.anime.genres.contains {
            $0.name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current) == target
        }
    }
}

private func isAnimeGenre(_ anime: AnimeModel) -> Bool {
    anime.genres.contains {
        $0.name.compare("Anime", options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
    }
}

#if os(iOS)
private struct LibraryPagedContentiOS: View {
    @Binding var genreFilter: AnimeGenre?
    let entries: [LibraryEntryModel]
    @Binding var viewMode: LibraryViewMode
    @Binding var selectedCategory: LibraryCategory
    @Binding var searchText: String
    var onEntryTap: (Anime) -> Void

    private var processedEntries: [LibraryEntryModel] {
        let sorted = sortEntries(entries, by: viewMode)
        let searched = searchEntries(sorted, query: searchText)
        return entriesFilteredByGenre(searched, using: genreFilter)
    }

    private var animeEntries: [LibraryEntryModel] {
        processedEntries.filter { $0.anime.kind == .anime }
    }

    private var showEntries: [LibraryEntryModel] {
        processedEntries.filter { $0.anime.kind == .tvShow && !isAnimeGenre($0.anime) }
    }

    private var movieEntries: [LibraryEntryModel] {
        processedEntries.filter { $0.anime.kind == .movie }
    }

    private var hasAnyEntries: Bool {
        !animeEntries.isEmpty || !showEntries.isEmpty || !movieEntries.isEmpty
    }

    var body: some View {
        VStack(spacing: 16) {
            header

            if !hasAnyEntries {
                emptyStateView(for: selectedCategory)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            } else {
                TabView(selection: $selectedCategory) {
                    libraryPage(for: animeEntries, category: .anime)
                        .tag(LibraryCategory.anime)

                    libraryPage(for: showEntries, category: .shows)
                        .tag(LibraryCategory.shows)

                    libraryPage(for: movieEntries, category: .movies)
                        .tag(LibraryCategory.movies)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(.easeInOut(duration: 0.2), value: selectedCategory)
            }
        }
        .padding(.top, 20)
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }

    private var header: some View {
        VStack(spacing: 12) {
            if let filter = genreFilter {
                genreFilterIndicator(filter: filter)
            }

            HStack {
                Picker("Sort", selection: $viewMode) {
                    ForEach(LibraryViewMode.allCases) { mode in
                        Text(mode.display).tag(mode)
                    }
                }
                .pickerStyle(.menu)

                Spacer()
            }

            Picker("Category", selection: $selectedCategory) {
                ForEach(LibraryCategory.allCases) { category in
                    Text(category.title).tag(category)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    @ViewBuilder
    private func libraryPage(for entries: [LibraryEntryModel], category: LibraryCategory) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if entries.isEmpty {
                    emptyStateView(for: category)
                        .frame(maxWidth: .infinity, minHeight: 220, alignment: .center)
                        .padding(.top, 32)
                } else {
                    let lastID = entries.last?.id
                    ForEach(entries) { entry in
                        VStack(spacing: 0) {
                            AnimeRowView(anime: entry.anime.asDTO)
                                .padding(.horizontal, 4)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    onEntryTap(entry.anime.asDTO)
                                }

                            if entry.id != lastID {
                                Divider()
                                    .padding(.leading, 92)
                                    .padding(.vertical, 6)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .padding(.top, 4)
            .padding(.bottom, 28)
        }
    }

    private func emptyStateView(for category: LibraryCategory) -> some View {
        let isFiltered = !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || genreFilter != nil

        if viewMode == .folderLinked {
            return ContentUnavailableView(
                "No linked folders yet",
                systemImage: "externaldrive.badge.icloud",
                description: Text("Link a local folder to an entry to have it show up here.")
            )
        } else if isFiltered {
            return ContentUnavailableView(
                "No titles match your filters",
                systemImage: "tray",
                description: Text("Adjust your filters or search terms to see your saved titles.")
            )
        } else {
            let title: String
            switch category {
            case .anime: title = "No anime saved yet"
            case .shows: title = "No shows saved yet"
            case .movies: title = "No movies saved yet"
            }
            return ContentUnavailableView(
                title,
                systemImage: "tray",
                description: Text("Add titles from Discover to build your library.")
            )
        }
    }

    private func genreFilterIndicator(filter: AnimeGenre) -> some View {
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
        .background(filterIndicatorBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var filterIndicatorBackground: Color {
        #if canImport(UIKit)
        return Color(UIColor.secondarySystemGroupedBackground)
        #else
        return Color.secondary.opacity(0.12)
        #endif
    }
}
#endif

private struct LibrarySectionView: View {
    let title: String
    let entries: [LibraryEntryModel]
    let genreFilter: AnimeGenre?
    let viewMode: LibraryViewMode
    let onGenreTap: (AnimeGenre) -> Void

    private var cardWidth: CGFloat {
#if canImport(UIKit)
        let screenWidth = UIScreen.main.bounds.width
        return max(220, min(screenWidth * 0.36, 320))
#else
        return 280
#endif
    }

    private var sectionHeight: CGFloat { 432 }

    var body: some View {
        let filteredEntries: [LibraryEntryModel] = {
            if let filter = genreFilter {
                let target = filter.name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
                return entries.filter { entry in
                    entry.anime.genres.contains {
                        $0.name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current) == target
                    }
                }
            } else {
                return entries
            }
        }()

        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.title3.weight(.semibold))
                .padding(.horizontal)

            if filteredEntries.isEmpty {
                contentUnavailableView
                    .frame(maxWidth: .infinity, minHeight: 200, alignment: .center)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 16) {
                        ForEach(filteredEntries) { entry in
                            NavigationLink(value: entry.anime.asDTO) {
                                AnimeGridItemView(
                                    animeModel: entry.anime,
                                    showStatusBadge: true,
                                    allowLocalMediaLinking: true,
                                    onGenreTap: onGenreTap,
                                    preferredWidth: cardWidth,
                                    libraryEntry: entry
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 6)
                }
                .frame(height: sectionHeight)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var contentUnavailableView: some View {
        switch viewMode {
        case .folderLinked:
            ContentUnavailableView(
                "No linked folders yet",
                systemImage: "externaldrive.badge.icloud",
                description: Text("Link a local folder to an entry to have it show up here.")
            )
        default:
            ContentUnavailableView(
                "No titles here yet",
                systemImage: "tray",
                description: Text("Add titles to this list from the Discover tab.")
            )
        }
    }
}

extension AnimeModel {
    var asDTO: Anime {
        let genresDTO = genres.map { AnimeGenre(id: $0.id, name: $0.name) }
        let provider = resolvedProviderID
        return Anime(
            id: provider,
            title: title,
            synopsis: synopsis,
            imageURL: imageURL,
            score: score,
            genres: genresDTO,
            episodeCount: episodeCount,
            kind: kind,
            providerID: provider
        )
    }
}
