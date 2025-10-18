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

private enum LibraryViewMode: String, CaseIterable, Identifiable {
    case alphabetical = "Alphabetical"
    case lastAdded = "Last Updated"
    case folderLinked = "Folder Linked"

    var id: String { rawValue }
    var display: String { rawValue }
}

struct LibraryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: [SortDescriptor(\LibraryEntryModel.addedAt, order: .reverse)]) private var entries: [LibraryEntryModel]
    @State private var genreFilter: AnimeGenre?
    @State private var viewMode: LibraryViewMode = .lastAdded

    var body: some View {
        NavigationStack {
            if entries.isEmpty {
                ContentUnavailableView(
                    "Your library is empty",
                    systemImage: "tray",
                    description: Text("Use the Discover tab to search for anime or TV shows and add them to your library.")
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
                        AnimeDetailCardView(anime: anime, onGenreTap: { genre in withAnimation { genreFilter = genre } }, allowLocalMediaLinking: true)
                            .padding(20)
                    }
                    .navigationTitle(anime.title)
                }
            }
        }
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
        let sortedEntries = sortEntries(allEntries)
        let searchedEntries = applySearch(to: sortedEntries)
        let animeEntries = searchedEntries.filter { $0.anime.kind == .anime }
        let tvEntries = searchedEntries.filter { $0.anime.kind == .tvShow && !isAnimeGenre($0.anime) }
        let animeTitle = "Anime"
        let tvTitle = "TV Shows"

        return ScrollView {
            VStack(spacing: 20) {
                if let filter = genreFilter {
                    genreFilterIndicator(filter: filter)
                        .padding(.horizontal)
                }

                if animeEntries.isEmpty && tvEntries.isEmpty {
                    ContentUnavailableView(
                        "No titles match your filters",
                        systemImage: "tray",
                        description: Text("Adjust your filters or search terms to see your saved shows.")
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

    private func sortEntries(_ entries: [LibraryEntryModel]) -> [LibraryEntryModel] {
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

    private func applySearch(to entries: [LibraryEntryModel]) -> [LibraryEntryModel] {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
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

    private func isAnimeGenre(_ anime: AnimeModel) -> Bool {
        anime.genres.contains {
            $0.name.compare("Anime", options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        }
    }
}

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
