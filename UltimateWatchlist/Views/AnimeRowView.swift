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

    private var entryModel: LibraryEntryModel? { entry.first }
    private var isInLibrary: Bool { entryModel != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 12) {
                AnimePosterView(imageURL: anime.imageURL)
                    .frame(width: 80, height: 112)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                
                VStack(alignment: .leading, spacing: 6) {
                    Label(anime.kind.displayName, systemImage: mediaTypeIconName)
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(tagBackground)
                        .foregroundStyle(tagForeground)
                        .clipShape(Capsule())
                    
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
                }
                
                Spacer()
                
                if isInLibrary {
                    Menu {
                        Button(role: .destructive) {
                            removeEntry()
                        } label: {
                            Label("Remove from Library", systemImage: "trash")
                        }
                    } label: {
                        Label("Added", systemImage: "checkmark.circle.fill")
                            .font(.footnote)
                    }
                } else {
                    Button {
                        addToLibrary()
                    } label: {
                        Label("Add", systemImage: "plus.circle.fill")
                            .font(.footnote)
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(.vertical, 8)
            
            if !anime.genres.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 8) {
                        ForEach(anime.genres, id: \.id) { genre in
                            Text(genre.name)
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(tagBackground)
                                .foregroundStyle(tagForeground)
                                .clipShape(Capsule())
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    private func addToLibrary() {
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
        if let e = entry.first {
            modelContext.delete(e)
            Task { @MainActor in
                try? modelContext.save()
            }
        }
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
        case .movie: return "film.fill"
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
