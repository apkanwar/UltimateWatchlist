//
//  AnimeGridItemView.swift
//  UltimateWatchlist
//
//  Created by Codex on 2025-10-13.
//

import SwiftUI
import SwiftData
import AVKit
#if canImport(UIKit)
import UIKit
#endif

struct AnimeGridItemView: View {
    let animeModel: AnimeModel
    let showStatusBadge: Bool
    let allowLocalMediaLinking: Bool
    let onGenreTap: ((AnimeGenre) -> Void)?

    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @Query private var watchlistEntry: [LibraryEntryModel]

    init(animeModel: AnimeModel, showStatusBadge: Bool = false, allowLocalMediaLinking: Bool = false, onGenreTap: ((AnimeGenre) -> Void)? = nil) {
        self.animeModel = animeModel
        self.showStatusBadge = showStatusBadge
        self.allowLocalMediaLinking = allowLocalMediaLinking
        self.onGenreTap = onGenreTap
        let targetID = animeModel.id
        let predicate = #Predicate<LibraryEntryModel> { $0.id == targetID }
        _watchlistEntry = Query(filter: predicate)
    }

    private var watchlistStatus: LibraryStatus? { watchlistEntry.first?.status }
    private var entryModel: LibraryEntryModel? { watchlistEntry.first }

    private var cornerRadius: CGFloat { 14 }
    private var titleAreaMinHeight: CGFloat { 32 }
    private var genreDTOs: [AnimeGenre] {
        animeModel.genres.map { AnimeGenre(id: $0.id, name: $0.name) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ZStack(alignment: .topTrailing) {
                AnimePosterView(imageURL: animeModel.imageURL, contentMode: .fill)
                    .frame(height: 200)
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius))

                Menu {
                    ForEach(LibraryStatus.allCases) { status in
                        Button {
                            withAnimation(.spring()) { upsertEntry(status: status) }
                        } label: {
                            Label(status.rawValue, systemImage: status.systemImageName)
                        }
                    }

                    if watchlistStatus != nil {
                        Divider()
                        Button(role: .destructive) {
                            withAnimation(.easeInOut) { removeEntry() }
                        } label: {
                            Label("Remove from Library", systemImage: "trash")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle.fill")
                        .imageScale(.large)
                        .foregroundStyle(Color.white)
                        .padding(10)
                }
                .accessibilityLabel("More options")

                if showStatusBadge, let status = watchlistStatus {
                    Text(status.rawValue)
                        .font(.caption2)
                        .bold()
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.white, in: Capsule())
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 6)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(animeModel.title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityLabel(animeModel.title)
                }
                .frame(minHeight: titleAreaMinHeight, alignment: .topLeading)

                if let episodes = animeModel.episodeCount {
                    Text("\(episodes) episode\(episodes == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if !genreDTOs.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(genreDTOs, id: \.id) { genre in
                                genreChip(for: genre)
                            }
                        }
                        .padding(.trailing, 4)
                    }
                }
            }

            Spacer(minLength: 0)

            if allowLocalMediaLinking, entryModel?.linkedFolderBookmarkData != nil {
                Button {
                    playOrResume()
                } label: {
                    let label: String = {
                        if let progress = PlaybackProgressStore.load(for: animeModel.id), let ep = progress.episodeNumber as Int? {
                            return "Resume E\(ep)"
                        } else { return "Play Episode 1" }
                    }()
                    Label(label, systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 320, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(borderColor, lineWidth: 1)
        )
        .shadow(color: shadowColor, radius: 3, x: 0, y: 1)
        .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
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

    private func upsertEntry(status: LibraryStatus) {
        if let entry = watchlistEntry.first {
            entry.status = status
            entry.addedAt = Date()
            try? modelContext.save()
        } else {
            let entry = LibraryEntryModel(id: animeModel.id, status: status, addedAt: Date(), anime: animeModel)
            modelContext.insert(entry)
            try? modelContext.save()
        }
    }

    private func removeEntry() {
        if let entry = watchlistEntry.first {
            modelContext.delete(entry)
            try? modelContext.save()
        }
    }

    private func loadEpisodes() -> [EpisodeFile] {
        guard let data = entryModel?.linkedFolderBookmarkData,
              let url = try? LocalMediaManager.resolveLinkedFolder(from: data) else { return [] }
        defer { LocalMediaManager.stopAccessIfNeeded(url: url) }
        return (try? LocalMediaManager.listEpisodes(in: url)) ?? []
    }

    private func playOrResume() {
        let episodes = loadEpisodes()
        guard !episodes.isEmpty else { return }
        let id = animeModel.id
        if let progress = PlaybackProgressStore.load(for: id),
           let ep = episodes.first(where: { $0.episodeNumber == progress.episodeNumber }) ?? episodes.first {
            #if os(iOS) || os(tvOS)
            let player = AVPlayer(url: ep.url)
            let time = CMTime(seconds: progress.seconds, preferredTimescale: 600)
            player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
            let vc = AVPlayerViewController(); vc.player = player
            if let root = UIApplication.shared.windows.first(where: { $0.isKeyWindow })?.rootViewController {
                root.present(vc, animated: true) { player.play() }
            }
            #else
            LocalMediaManager.presentPlayer(for: ep)
            #endif
        } else if let first = episodes.first {
            LocalMediaManager.presentPlayer(for: first)
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

    // Create sample genres
    let action = AnimeGenreModel(id: 1, name: "Action")
    let adventure = AnimeGenreModel(id: 2, name: "Adventure")

    // Insert genres individually (ModelContext.insert expects a PersistentModel, not an array)
    context.insert(action)
    context.insert(adventure)

    // Create sample anime referencing the genres
    let anime = AnimeModel(
        id: 1,
        title: "FMAB",
        synopsis: "Two brothers...",
        imageURLString: nil,
        score: 9.2,
        episodeCount: 64,
        genres: [action, adventure]
    )

    // Insert anime
    context.insert(anime)

    return AnimeGridItemView(animeModel: anime, showStatusBadge: true, allowLocalMediaLinking: true)
        .frame(width: 200)
        .modelContainer(container)
}
