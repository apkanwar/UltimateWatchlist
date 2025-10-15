//
//  LibraryView.swift
//  UltimateWatchlist
//
//  Created by Codex on 2025-10-13.
//

import SwiftUI
import SwiftData

private enum LibraryFilter: Identifiable, Hashable, CaseIterable {
    case all
    case status(LibraryStatus)

    static var allCases: [LibraryFilter] {
        var cases: [LibraryFilter] = [.all]
        cases.append(contentsOf: LibraryStatus.allCases.map { .status($0) })
        return cases
    }

    var id: String { display }
    var display: String {
        switch self {
        case .all: return "All"
        case .status(let s): return s.rawValue
        }
    }
}

private enum LibraryViewMode: String, CaseIterable, Identifiable {
    case alphabetical = "Alphabetical"
    case lastAdded = "Last Added"
    case folderLinked = "Folder Linked"

    var id: String { rawValue }
    var display: String { rawValue }
}

struct LibraryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: [SortDescriptor(\LibraryEntryModel.addedAt, order: .reverse)]) private var entries: [LibraryEntryModel]
    @State private var selectedFilter: LibraryFilter = .all
    @State private var genreFilter: AnimeGenre?
    @State private var viewMode: LibraryViewMode = .lastAdded

    private var grouped: [LibraryStatus: [LibraryEntryModel]] {
        Dictionary(grouping: entries, by: { $0.status })
    }

    var body: some View {
        NavigationStack {
            if entries.isEmpty {
                ContentUnavailableView(
                    "Your library is empty",
                    systemImage: "tray",
                    description: Text("Use the Discover tab to search for anime and add them to your library.")
                )
                .navigationTitle("Library")
            } else {
                LibraryContent(
                    selectedFilter: $selectedFilter,
                    groupedEntries: grouped,
                    genreFilter: $genreFilter,
                    allEntries: entries,
                    viewMode: $viewMode
                )
                .navigationTitle("Library")
                .onChange(of: entries) { _, newEntries in
                    switch selectedFilter {
                    case .status(let s):
                        if !newEntries.contains(where: { $0.status == s }) {
                            if !newEntries.isEmpty {
                                if let next = LibraryStatus.allCases.first(where: { (grouped[$0]?.isEmpty == false) }) {
                                    selectedFilter = .status(next)
                                } else {
                                    selectedFilter = .all
                                }
                            }
                        }
                    case .all:
                        break
                    }
                }
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
#Preview {
    LibraryView()
        .modelContainer(for: [AnimeModel.self, AnimeGenreModel.self, LibraryEntryModel.self], inMemory: true)
}
#endif

private struct LibraryContent: View {
    @Binding var selectedFilter: LibraryFilter
    let groupedEntries: [LibraryStatus: [LibraryEntryModel]]
    @Binding var genreFilter: AnimeGenre?
    let allEntries: [LibraryEntryModel]
    @Binding var viewMode: LibraryViewMode

    private let columns = [GridItem(.adaptive(minimum: 200, maximum: 260), spacing: 16, alignment: .leading)]

    var body: some View {
        VStack(spacing: 16) {
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Picker("Status", selection: $selectedFilter) {
                        ForEach(LibraryFilter.allCases) { filter in
                            Text(filter.display).tag(filter)
                        }
                    }
                    .pickerStyle(.menu)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .leading, spacing: 6) {
                    Picker("Sort", selection: $viewMode) {
                        ForEach(LibraryViewMode.allCases) { mode in
                            Text(mode.display).tag(mode)
                        }
                    }
                    .pickerStyle(.menu)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal)

            if let filter = genreFilter {
                // Reuse Discover-style indicator
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
                .background(
                    {
                        #if canImport(UIKit)
                        Color(UIColor.secondarySystemGroupedBackground)
                        #else
                        Color.secondary.opacity(0.12)
                        #endif
                    }()
                )
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .padding(.horizontal)
            }

            let entriesForFilter: [LibraryEntryModel] = {
                switch selectedFilter {
                case .all:
                    return allEntries
                case .status(let s):
                    return groupedEntries[s] ?? []
                }
            }()

            let finalEntries: [LibraryEntryModel] = {
                switch viewMode {
                case .lastAdded:
                    return entriesForFilter.sorted(by: { $0.addedAt > $1.addedAt })
                case .alphabetical:
                    return entriesForFilter.sorted {
                        $0.anime.title.localizedCaseInsensitiveCompare($1.anime.title) == .orderedAscending
                    }
                case .folderLinked:
                    return entriesForFilter
                        .filter { $0.linkedFolderBookmarkData != nil }
                        .sorted(by: { $0.addedAt > $1.addedAt })
                }
            }()

            LibraryPage(
                title: selectedFilter.display,
                entries: finalEntries,
                columns: columns,
                genreFilter: genreFilter,
                viewMode: viewMode,
                onGenreTap: { genre in withAnimation { genreFilter = genre } }
            )
            .id("\(selectedFilter.id)-\(viewMode.id)")
        }
        .padding(.bottom)
    }
}

private struct LibraryPage: View {
    let title: String
    let entries: [LibraryEntryModel]
    let columns: [GridItem]
    let genreFilter: AnimeGenre?
    let viewMode: LibraryViewMode
    let onGenreTap: (AnimeGenre) -> Void

    var body: some View {
        let filteredEntries: [LibraryEntryModel] = {
            if let filter = genreFilter {
                return entries.filter { entry in
                    entry.anime.genres.contains(where: { $0.id == filter.id })
                }
            } else {
                return entries
            }
        }()

        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(title)
                    .font(.headline)
                    .padding(.horizontal)

                if filteredEntries.isEmpty {
                    contentUnavailableView
                    .frame(maxWidth: .infinity, minHeight: 240, alignment: .center)
                } else {
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 20) {
                        ForEach(filteredEntries) { entry in
                            NavigationLink(value: entry.anime.asDTO) {
                                AnimeGridItemView(
                                    animeModel: entry.anime,
                                    showStatusBadge: true,
                                    allowLocalMediaLinking: true,
                                    onGenreTap: onGenreTap
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
                    .padding(.bottom, 24)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
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
                description: Text("Add anime to this list from the Discover tab.")
            )
        }
    }
}

extension AnimeModel {
    var asDTO: Anime {
        let genresDTO = genres.map { AnimeGenre(id: $0.id, name: $0.name) }
        return Anime(
            id: id,
            title: title,
            synopsis: synopsis,
            imageURL: imageURL,
            score: score,
            genres: genresDTO,
            episodeCount: episodeCount
        )
    }
}
