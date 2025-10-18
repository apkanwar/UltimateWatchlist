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
#endif

struct AnimeDetailCardView: View {
    let anime: Anime
    var showStatusBadge: Bool = false
    var onGenreTap: ((AnimeGenre) -> Void)?
    var allowLocalMediaLinking: Bool = false
    var synopsisLineLimit: Int?
    var cardHeight: CGFloat?

    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var navigation: AppNavigation
    @EnvironmentObject private var playbackCoordinator: PlaybackCoordinator
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

    private var isInLibrary: Bool { entry.first != nil }
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
                Task { @MainActor in
                    try? modelContext.save()
                }
                refreshEpisodes()
            }
        } catch { }
    }

    private func unlinkFolder() {
        if let e = entryModel {
            e.linkedFolderBookmarkData = nil
            e.linkedFolderDisplayPath = nil
            Task { @MainActor in
                try? modelContext.save()
            }
            episodes = []
        }
    }
    
    @ViewBuilder
    private var libraryActionControls: some View {
        if entryModel != nil {
            Menu {
                if allowLocalMediaLinking {
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
                
                Button(role: .destructive) {
                    removeEntry()
                } label: {
                    Label("Remove from Library", systemImage: "trash")
                }
            } label: {
                Label("  In Library", systemImage: "bookmark.fill")
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(tagBackground, in: Capsule())
                    .foregroundStyle(tagForeground)
            }
            .accessibilityLabel("Library options")
        } else {
            Button {
                addToLibrary()
            } label: {
                Label("Add to Library", systemImage: "plus.circle.fill")
                    .font(.footnote.weight(.semibold))
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private func play(_ ep: EpisodeFile) {
        guard allowLocalMediaLinking else { return }
        guard let index = episodes.firstIndex(where: { $0.id == ep.id }) else { return }
        let progress = PlaybackProgress(
            episodeNumber: ep.episodeNumber ?? index + 1,
            seconds: 0
        )
        presentPlayback(startingAt: index, initialProgress: progress)
    }

    private func presentPlayback(startingAt index: Int, initialProgress: PlaybackProgress?) {
        guard allowLocalMediaLinking else { return }
        guard !episodes.isEmpty, episodes.indices.contains(index) else { return }
        let queue = Array(episodes[index...])
        beginPlayback(with: queue, baseIndex: index, initialProgress: initialProgress)
    }

    private func beginPlayback(with queue: [EpisodeFile], baseIndex: Int, initialProgress: PlaybackProgress?) {
        guard allowLocalMediaLinking, !queue.isEmpty else { return }
        let split = LocalMediaManager.splitQueueForInlinePlayback(queue)
        guard !split.playable.isEmpty else {
            if let unsupported = split.firstUnsupported {
                LocalMediaManager.presentPlayer(for: unsupported, folderBookmark: entryModel?.linkedFolderBookmarkData)
            }
            return
        }
        playbackCoordinator.begin(
            PlaybackRequest(
                animeID: anime.id,
                title: anime.title,
                queue: split.playable,
                baseIndex: baseIndex,
                initialProgress: initialProgress,
                externalFallback: split.firstUnsupported,
                folderBookmarkData: entryModel?.linkedFolderBookmarkData
            )
        )
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
                            if showStatusBadge, isInLibrary {
                                Text("Options")
                                    .font(.caption2)
                                    .bold()
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(.ultraThinMaterial, in: Capsule())
                                    .padding(8)
                            }
                        }
                    libraryActionControls
                }
                

                VStack(alignment: .leading, spacing: 10) {
                    Label(anime.kind.displayName, systemImage: mediaTypeIconName)
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(tagBackground)
                        .foregroundStyle(tagForeground)
                        .clipShape(Capsule())

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
        .onChange(of: entryModel?.linkedFolderBookmarkData) { _, _ in
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

    private func addToLibrary() {
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
            entry.addedAt = Date()
        } else {
            let entry = LibraryEntryModel(id: anime.id, status: .planToWatch, addedAt: Date(), anime: animeModel)
            modelContext.insert(entry)
        }
        Task { @MainActor in
            try? modelContext.save()
        }
    }

    private func removeEntry() {
        if let entry = entry.first {
            modelContext.delete(entry)
            Task { @MainActor in
                try? modelContext.save()
            }
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

    private var mediaTypeIconName: String {
        switch anime.kind {
        case .anime: return "sparkles.tv"
        case .tvShow: return "tv.fill"
        }
    }

    private func resolveStartIndex(for episodes: [EpisodeFile], progress: PlaybackProgress?) -> Int {
        guard let progress else { return 0 }
        if let match = episodes.firstIndex(where: { $0.episodeNumber == progress.episodeNumber }) {
            return match
        }
        let fallback = progress.episodeNumber - 1
        if fallback >= 0 && fallback < episodes.count {
            return fallback
        }
        return 0
    }

    private func adjustedProgress(_ progress: PlaybackProgress?, for episodes: [EpisodeFile], startIndex: Int) -> PlaybackProgress? {
        guard let progress else { return nil }
        let episode = episodes[startIndex]
        let number = episode.episodeNumber ?? (startIndex + 1)
        if number == progress.episodeNumber {
            return progress
        }
        return PlaybackProgress(episodeNumber: number, seconds: progress.seconds)
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
    .modelContainer(PreviewData.makeContainer(populated: true))
    .environmentObject(AppNavigation())
    .environmentObject(PlaybackCoordinator())
}
#endif
