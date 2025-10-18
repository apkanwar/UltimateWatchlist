//
//  AnimeGridItemView.swift
//  UltimateWatchlist
//
//  Created by Codex on 2025-10-13.
//

import SwiftUI
import SwiftData
#if canImport(UIKit)
import UIKit
#endif

struct AnimeGridItemView: View {
    let animeModel: AnimeModel
    let showStatusBadge: Bool
    let allowLocalMediaLinking: Bool
    let onGenreTap: ((AnimeGenre) -> Void)?
    let preferredWidth: CGFloat?
    private let libraryEntry: LibraryEntryModel?

    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var playbackCoordinator: PlaybackCoordinator
    @State private var resumeProgress: PlaybackProgress? = nil
    @State private var hasLinkedFolderState: Bool = false
    @State private var genresState: [AnimeGenre] = []

    init(
        animeModel: AnimeModel,
        showStatusBadge: Bool = false,
        allowLocalMediaLinking: Bool = false,
        onGenreTap: ((AnimeGenre) -> Void)? = nil,
        preferredWidth: CGFloat? = nil,
        libraryEntry: LibraryEntryModel? = nil
    ) {
        self.animeModel = animeModel
        self.showStatusBadge = showStatusBadge
        self.allowLocalMediaLinking = allowLocalMediaLinking
        self.onGenreTap = onGenreTap
        self.preferredWidth = preferredWidth
        self.libraryEntry = libraryEntry
    }

    private var entry: LibraryEntryModel? { libraryEntry }

    private let cornerRadius: CGFloat = 14
    private let posterHeight: CGFloat = 220
    private let cardBaseHeight: CGFloat = 400
    private let titleAreaMinHeight: CGFloat = 40

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            
            ZStack(alignment: .topTrailing) {
                AnimePosterView(imageURL: animeModel.imageURL, contentMode: .fill)
                    .frame(height: posterHeight)
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
                    .padding(.top, 24)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(animeModel.title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel(animeModel.title)
                    .frame(minHeight: titleAreaMinHeight, alignment: .topLeading)

                if let episodes = animeModel.episodeCount {
                    Label("\(episodes) episode\(episodes == 1 ? "" : "s")", systemImage: "play.tv")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                if !genresState.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(genresState, id: \.id) { genre in
                                genreChip(for: genre)
                            }
                        }
                        .padding(.trailing, 4)
                    }
                }
            }
        }
        .padding(14)
        .frame(width: preferredWidth)
        .frame(maxWidth: preferredWidth ?? .infinity, maxHeight: cardBaseHeight, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(borderColor, lineWidth: 1)
        )
        .overlay(alignment: .topTrailing) {
            libraryControls
                .padding(12)
                .zIndex(10)
                .allowsHitTesting(true)
        }
        .shadow(color: shadowColor, radius: 3, x: 0, y: 1)
        .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .task(id: animeModel.id) {
            if allowLocalMediaLinking {
                resumeProgress = PlaybackProgressStore.load(for: animeModel.id)
            } else {
                resumeProgress = nil
            }
            hasLinkedFolderState = (entry?.linkedFolderBookmarkData != nil)
            genresState = animeModel.genres.map { AnimeGenre(id: $0.id, name: $0.name) }
        }
        .task(id: entry?.linkedFolderBookmarkData) {
            hasLinkedFolderState = (entry?.linkedFolderBookmarkData != nil)
        }
    }

    @ViewBuilder
    private var libraryControls: some View {
        if let entry {
            Menu {
                if allowLocalMediaLinking {
                    if entry.linkedFolderBookmarkData == nil {
                        Button {
                            linkFolder(for: entry)
                        } label: {
                            Label("Link Folder", systemImage: "folder.badge.plus")
                        }
                    } else {
                        Button(role: .destructive) {
                            unlinkFolder(for: entry)
                        } label: {
                            Label("Unlink Folder", systemImage: "folder.badge.minus")
                        }
                    }
                    Divider()
                }
                Button(role: .destructive) {
                    Task { @MainActor in
                        removeEntry()
                    }
                } label: {
                    Label("Remove from Library", systemImage: "trash")
                }
            } label: {
                if showStatusBadge {
                    HStack(spacing: 6) {
                        Image(systemName: "bookmark.fill")
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(tagBackground, in: Capsule())
                    .foregroundStyle(tagForeground)
                } else {
                    Image(systemName: "ellipsis.circle.fill")
                        .imageScale(.large)
                        .foregroundStyle(Color.white)
                        .padding(10)
                }
            }
            .accessibilityLabel("Library options")
            .buttonStyle(.borderless)
            .contentShape(Rectangle())
            .zIndex(2)
        }
    }
    
    private func linkFolder(for entry: LibraryEntryModel) {
        guard allowLocalMediaLinking else { return }
        Task { @MainActor in
            do {
                let result = try await LocalMediaManager.linkFolder()
                entry.linkedFolderBookmarkData = result.bookmark
                entry.linkedFolderDisplayPath = result.displayPath
                try? modelContext.save()
                hasLinkedFolderState = true
            } catch {
                // Ignore cancellation/denial
            }
        }
    }

    private func unlinkFolder(for entry: LibraryEntryModel) {
        guard allowLocalMediaLinking else { return }
        Task { @MainActor in
            entry.linkedFolderBookmarkData = nil
            entry.linkedFolderDisplayPath = nil
            try? modelContext.save()
            hasLinkedFolderState = false
        }
    }

    @ViewBuilder
    private func genreChip(for genre: AnimeGenre) -> some View {
        if let onGenreTap {
            Button {
                onGenreTap(genre)
            } label: {
                chipLabel(for: genre.name)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Filter by \(genre.name)")
        } else {
            chipLabel(for: genre.name)
        }
    }

    private func chipLabel(for name: String) -> some View {
        Text(name)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(tagBackground)
            .foregroundStyle(tagForeground)
            .clipShape(Capsule())
            .fixedSize(horizontal: true, vertical: true)
    }

    private func removeEntry() {
        guard let entry else { return }
        modelContext.delete(entry)
        // Defer the save to the next actor turn to avoid publishing during view updates
        Task { @MainActor in
            try? modelContext.save()
        }
    }

    private func loadEpisodes() -> [EpisodeFile] {
        guard let entry,
              let data = entry.linkedFolderBookmarkData,
              let folderURL = try? LocalMediaManager.resolveLinkedFolder(from: data) else {
            return []
        }
        defer { LocalMediaManager.stopAccessIfNeeded(url: folderURL) }
        return (try? LocalMediaManager.listEpisodes(in: folderURL)) ?? []
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
        let episodeNumber = episode.episodeNumber ?? (startIndex + 1)
        if episodeNumber == progress.episodeNumber {
            return progress
        }
        return PlaybackProgress(episodeNumber: episodeNumber, seconds: progress.seconds)
    }

    private func beginPlayback(with queue: [EpisodeFile], baseIndex: Int, initialProgress: PlaybackProgress?) {
        guard allowLocalMediaLinking, !queue.isEmpty else { return }
        // Local fallback for splitting queue when LocalMediaManager API is unavailable
        struct InlineSplit {
            let playable: [EpisodeFile]
            let firstUnsupported: EpisodeFile?
        }
        func inlineSplitQueue(_ files: [EpisodeFile]) -> InlineSplit {
            // Heuristic: assume all files are playable; adjust if EpisodeFile exposes capability flags.
            return InlineSplit(playable: files, firstUnsupported: nil)
        }
        let split = inlineSplitQueue(queue)
        guard !split.playable.isEmpty else {
            if let unsupported = split.firstUnsupported {
                LocalMediaManager.presentPlayer(for: unsupported, folderBookmark: entry?.linkedFolderBookmarkData)
            }
            return
        }
        Task { @MainActor in
            playbackCoordinator.begin(
                PlaybackRequest(
                    animeID: animeModel.id,
                    title: animeModel.title,
                    queue: split.playable,
                    baseIndex: baseIndex,
                    initialProgress: initialProgress,
                    externalFallback: split.firstUnsupported,
                    folderBookmarkData: entry?.linkedFolderBookmarkData
                )
            )
        }
    }

    private var cardBackground: Color {
        #if canImport(UIKit)
        return Color(.secondarySystemBackground)
        #else
        return Color.secondary.opacity(0.08)
        #endif
    }

    private var borderColor: Color {
        #if canImport(UIKit)
        return Color(.separator).opacity(0.3)
        #else
        return Color.primary.opacity(0.1)
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

    private var shadowColor: Color {
        colorScheme == .dark ? Color.black.opacity(0.45) : Color.black.opacity(0.08)
    }
}

#Preview {
    // In-memory preview container
    let container = try! ModelContainer(
        for: AnimeModel.self,
        AnimeGenreModel.self,
        LibraryEntryModel.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    let context = ModelContext(container)

    let action = AnimeGenreModel(id: 1, name: "Action")
    let adventure = AnimeGenreModel(id: 2, name: "Adventure")
    context.insert(action)
    context.insert(adventure)

    let anime = AnimeModel(
        id: 1,
        providerID: 1,
        kind: .anime,
        title: "FMAB",
        synopsis: "Two brothers...",
        imageURLString: nil,
        score: 9.2,
        episodeCount: 64,
        genres: [action, adventure]
    )
    context.insert(anime)
    let entry = LibraryEntryModel(id: anime.id, status: .completed, anime: anime)
    context.insert(entry)

    return AnimeGridItemView(
        animeModel: anime,
        showStatusBadge: true,
        allowLocalMediaLinking: true,
        preferredWidth: 240,
        libraryEntry: entry
    )
        .modelContainer(container)
        .environmentObject(AppNavigation())
        .environmentObject(PlaybackCoordinator())
}
