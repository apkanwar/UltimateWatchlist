//
//  AnimeDetailCardView.swift
//  UltimateWatchlist
//
//  Created by Codex on 2025-10-13.
//

import SwiftUI
import SwiftData
#if canImport(UIKit)
import UIKit
import AVKit
#endif

struct AnimeDetailCardView: View {
    let anime: Anime
    var showStatusBadge: Bool = false
    var onGenreTap: ((AnimeGenre) -> Void)?
    var allowLocalMediaLinking: Bool = false
    var synopsisLineLimit: Int?
    var cardHeight: CGFloat?

    @Environment(\.modelContext) private var modelContext
    @Query private var entry: [LibraryEntryModel]

    @State private var episodes: [EpisodeFile] = []

    init(
        anime: Anime,
        showStatusBadge: Bool = false,
        onGenreTap: ((AnimeGenre) -> Void)? = nil,
        allowLocalMediaLinking: Bool = false,
        synopsisLineLimit: Int? = nil,
        cardHeight: CGFloat? = nil
    ) {
        self.anime = anime
        self.showStatusBadge = showStatusBadge
        self.onGenreTap = onGenreTap
        self.allowLocalMediaLinking = allowLocalMediaLinking
        self.synopsisLineLimit = synopsisLineLimit
        self.cardHeight = cardHeight
        let predicate = #Predicate<LibraryEntryModel> { $0.id == anime.id }
        _entry = Query(filter: predicate)
    }

    private var watchlistStatus: LibraryStatus? { entry.first?.status }
    private var entryModel: LibraryEntryModel? { entry.first }

    private func refreshEpisodes() {
        guard let data = entryModel?.linkedFolderBookmarkData,
              let folderURL = try? LocalMediaManager.resolveLinkedFolder(from: data) else {
            episodes = []
            return
        }
        defer { LocalMediaManager.stopAccessIfNeeded(url: folderURL) }
        episodes = (try? LocalMediaManager.listEpisodes(in: folderURL)) ?? []
    }

    private func linkFolder() async {
        do {
            let result = try await LocalMediaManager.linkFolder()
            if let e = entryModel {
                e.linkedFolderBookmarkData = result.bookmark
                e.linkedFolderDisplayPath = result.displayPath
                try? modelContext.save()
                refreshEpisodes()
            }
        } catch { }
    }

    private func unlinkFolder() {
        if let e = entryModel {
            e.linkedFolderBookmarkData = nil
            e.linkedFolderDisplayPath = nil
            try? modelContext.save()
            episodes = []
        }
    }

    private func play(_ ep: EpisodeFile) {
        LocalMediaManager.presentPlayer(for: ep)
    }

    private let cornerRadius: CGFloat = 18

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    AnimePosterView(imageURL: anime.imageURL, contentMode: .fill)
                        .frame(width: 130, height: 190)
                        .clipShape(RoundedRectangle(cornerRadius: cornerRadius * 0.6))
                        .overlay(alignment: .bottomLeading) {
                            if showStatusBadge, let status = watchlistStatus {
                                Text(status.rawValue)
                                    .font(.caption2)
                                    .bold()
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(.ultraThinMaterial, in: Capsule())
                                    .padding(8)
                            }
                        }
                    Menu {
                        ForEach(LibraryStatus.allCases) { status in
                            Button {
                                withAnimation(.spring()) { upsertFromDTO(status: status) }
                            } label: {
                                Label(status.rawValue, systemImage: status.systemImageName)
                            }
                        }
                        
                        if watchlistStatus != nil {
                            Divider()
                            Button(role: .destructive) {
                                withAnimation(.easeInOut) { removeEntry() }
                            } label: {
                                Label("Remove from Watchlist", systemImage: "trash")
                            }
                        }
                        if allowLocalMediaLinking {
                            Divider()
                            if entryModel?.linkedFolderBookmarkData == nil {
                                Button {
                                    Task { await linkFolder() }
                                } label: {
                                    Label("Link Folder", systemImage: "folder.badge.plus")
                                }
                            } else {
                                Button(role: .destructive) {
                                    unlinkFolder()
                                } label: {
                                    Label("Unlink Folder", systemImage: "folder.badge.minus")
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "ellipsis.circle.fill")
                                .imageScale(.large)
                                .foregroundStyle(.secondary)

                            Text("  Status")
                                .foregroundColor(.secondary)
                        }
                        .padding(.top, 2)
                    }
                    .accessibilityLabel("More options")
                }
                

                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .top) {
                        Text(anime.title)
                            .font(.headline)
                            .foregroundStyle(.primary)
                            .multilineTextAlignment(.leading)
                            .lineLimit(2)
                            .truncationMode(.tail)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    infoRow
                    genreTags

                    Text(anime.synopsis)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                        .lineLimit(synopsisLineLimit)

                    if allowLocalMediaLinking, entryModel?.linkedFolderBookmarkData != nil {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Episodes", systemImage: "list.bullet.rectangle")
                                .font(.subheadline.weight(.semibold))
                            if episodes.isEmpty {
                                Text("No episodes found.")
                                    .foregroundStyle(.secondary)
                            } else {
                                ForEach(episodes) { ep in
                                    Button {
                                        play(ep)
                                        if let num = ep.episodeNumber {
                                            PlaybackProgressStore.save(PlaybackProgress(episodeNumber: num, seconds: 0), for: anime.id)
                                        }
                                    } label: {
                                        HStack {
                                            Text(ep.displayName)
                                            Spacer()
                                            if let n = ep.episodeNumber {
                                                Text("Ep \(n)")
                                                    .foregroundStyle(.secondary)
                                            }
                                            Image(systemName: "play.fill")
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                }
                            }
                        }
                        .padding(.top, 6)
                    }
                }
            }
        }
        .padding(18)
        .frame(minHeight: 260, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius)
                .strokeBorder(borderColor)
        )
        .contentShape(RoundedRectangle(cornerRadius: cornerRadius))
        .frame(minHeight: cardHeight ?? 260, maxHeight: cardHeight, alignment: .topLeading)
        .onAppear {
            if allowLocalMediaLinking {
                refreshEpisodes()
            }
        }
        .onChange(of: entryModel?.linkedFolderBookmarkData) { _ in
            if allowLocalMediaLinking {
                refreshEpisodes()
            }
        }
    }

    private var infoRow: some View {
        HStack(spacing: 12) {
            if let score = anime.score {
                Label(String(format: "%.1f", score), systemImage: "star.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            if let episodes = anime.episodeCount {
                Label("\(episodes) ep\(episodes == 1 ? "" : "s")", systemImage: "play.tv")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var genreTags: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(anime.genres, id: \.id) { genre in
                    Button {
                        onGenreTap?(genre)
                    } label: {
                        Text(genre.name)
                            .font(.caption.weight(.medium))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(tagBackground)
                            .foregroundStyle(tagForeground)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Filter by \(genre.name)")
                }
            }
            .padding(.trailing, 4)
        }
    }

    private func upsertFromDTO(status: LibraryStatus) {
        // Upsert genres
        let genreModels: [AnimeGenreModel] = anime.genres.map { g in
            // Attempt to fetch an existing genre model
            let fetched: [AnimeGenreModel]? = try? modelContext.fetch(
                FetchDescriptor<AnimeGenreModel>(predicate: #Predicate { $0.id == g.id })
            )
            if let existing = fetched?.first {
                return existing
            } else {
                let model = AnimeGenreModel(id: g.id, name: g.name)
                modelContext.insert(model)
                return model
            }
        }
        // Upsert anime
        let existingAnime = try? modelContext.fetch(FetchDescriptor<AnimeModel>(predicate: #Predicate { $0.id == anime.id })).first
        let animeModel = existingAnime ?? AnimeModel(from: anime, genres: genreModels)
        if existingAnime == nil { modelContext.insert(animeModel) }

        // Upsert entry
        let existingEntry = try? modelContext.fetch(FetchDescriptor<LibraryEntryModel>(predicate: #Predicate { $0.id == anime.id })).first
        if let entry = existingEntry {
            entry.status = status
            entry.addedAt = Date()
        } else {
            let entry = LibraryEntryModel(id: anime.id, status: status, addedAt: Date(), anime: animeModel)
            modelContext.insert(entry)
        }
        try? modelContext.save()
    }

    private func removeEntry() {
        if let entry = entry.first {
            modelContext.delete(entry)
            try? modelContext.save()
        }
    }

    private var cardBackground: Color {
        #if canImport(UIKit)
        return Color(UIColor.secondarySystemGroupedBackground)
        #else
        return Color.secondary.opacity(0.1)
        #endif
    }

    private var borderColor: Color {
        #if canImport(UIKit)
        return Color(UIColor.separator).opacity(0.35)
        #else
        return Color.primary.opacity(0.08)
        #endif
    }

    private var tagBackground: Color {
        #if canImport(UIKit)
        return Color(UIColor.tertiarySystemFill)
        #else
        return Color.secondary.opacity(0.2)
        #endif
    }

    private var tagForeground: Color {
        #if canImport(UIKit)
        return Color(UIColor.label)
        #else
        return Color.primary
        #endif
    }
}

#if DEBUG
#Preview {
    // DTO preview only
    AnimeDetailCardView(
        anime: Anime(
            id: 1,
            title: "Fullmetal Alchemist: Brotherhood",
            synopsis: "Two brothers search for a Philosopher's Stone after attempting to resurrect their mother through alchemy.",
            imageURL: nil,
            score: 9.2,
            genres: [AnimeGenre(id: 1, name: "Action"), AnimeGenre(id: 2, name: "Adventure")],
            episodeCount: 64
        ),
        showStatusBadge: true,
        onGenreTap: { _ in },
        allowLocalMediaLinking: true
    )
}
#endif
