//
//  AnimeRowView.swift
//  UltimateWatchlist
//
//  Created by Codex on 2025-10-13.
//

import SwiftUI
import SwiftData
#if canImport(UIKit)
import UIKit
#endif

struct AnimeRowView: View {
    let anime: Anime

    @Environment(\.modelContext) private var modelContext
    @Query private var entry: [LibraryEntryModel]

    init(anime: Anime) {
        self.anime = anime
        let predicate = #Predicate<LibraryEntryModel> { $0.id == anime.id }
        _entry = Query(filter: predicate)
    }

    private var libraryStatus: LibraryStatus? { entry.first?.status }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            AnimePosterView(imageURL: anime.imageURL)
                .frame(width: 80, height: 112)
                .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 6) {
                Text(anime.title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)

                if let score = anime.score {
                    Label(String(format: "%.1f", score), systemImage: "star.fill")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .imageScale(.small)
                }

                Text(anime.synopsis)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)

                if !anime.genres.isEmpty {
                    Text(anime.genres.map(\.name).joined(separator: ", "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            Menu {
                ForEach(LibraryStatus.allCases) { status in
                    Button(status.rawValue) {
                        withAnimation { upsertFromDTO(status: status) }
                    }
                }

                if libraryStatus != nil {
                    Divider()
                    Button(role: .destructive) {
                        withAnimation { removeEntry() }
                    } label: {
                        Label("Remove from Library", systemImage: "trash")
                    }
                }
            } label: {
                Label(libraryStatus?.rawValue ?? "Add", systemImage: libraryStatus?.systemImageName ?? "plus.circle")
                    .font(.footnote)
                    .padding(.top, 4)
            }
        }
        .padding(.vertical, 8)
    }

    private func upsertFromDTO(status: LibraryStatus) {
        // Upsert genres
        let genreModels: [AnimeGenreModel] = anime.genres.map { g in
            let fetch = try? modelContext.fetch(
                FetchDescriptor<AnimeGenreModel>(
                    predicate: #Predicate { $0.id == g.id }
                )
            )
            if let existing = fetch?.first {
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
        if let e = entry.first {
            modelContext.delete(e)
            try? modelContext.save()
        }
    }
}

#Preview(traits: .sizeThatFitsLayout) {
    // DTO preview only
    AnimeRowView(anime: Anime(
        id: 1,
        title: "Fullmetal Alchemist: Brotherhood",
        synopsis: "Two brothers search for a Philosopher's Stone.",
        imageURL: nil,
        score: 9.2,
        genres: [AnimeGenre(id: 1, name: "Action"), AnimeGenre(id: 2, name: "Adventure")],
        episodeCount: 64
    ))
    .padding()
}
