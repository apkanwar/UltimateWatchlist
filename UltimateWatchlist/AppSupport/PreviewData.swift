import Foundation
import SwiftData

enum PreviewData {
    static func makeContainer(populated: Bool = true) -> ModelContainer {
        let container = try! ModelContainer(
            for: AnimeModel.self,
            AnimeGenreModel.self,
            LibraryEntryModel.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        if populated {
            populateSampleLibrary(in: container.mainContext)
        }
        return container
    }

    @discardableResult
    static func populateSampleLibrary(in context: ModelContext) -> [LibraryEntryModel] {
        let action = AnimeGenreModel(id: 1, name: "Action")
        let drama = AnimeGenreModel(id: 2, name: "Drama")
        let fantasy = AnimeGenreModel(id: 3, name: "Fantasy")
        context.insert(action)
        context.insert(drama)
        context.insert(fantasy)

        let anime = AnimeModel(
            id: 1001,
            providerID: 1001,
            kind: .anime,
            title: "Eternal Alchemy",
            synopsis: "Two siblings search for a lost secret.",
            imageURLString: nil,
            score: 9.1,
            episodeCount: 64,
            genres: [action, fantasy]
        )
        let show = AnimeModel(
            id: 2001,
            providerID: 2001,
            kind: .tvShow,
            title: "Starlight Detectives",
            synopsis: "A detective duo solves mysteries between worlds.",
            imageURLString: nil,
            score: 8.6,
            episodeCount: 24,
            genres: [drama, fantasy]
        )

        context.insert(anime)
        context.insert(show)

        let first = LibraryEntryModel(id: anime.id, status: .currentlyWatching, anime: anime)
        let second = LibraryEntryModel(id: show.id, status: .planToWatch, anime: show)
        context.insert(first)
        context.insert(second)

        try? context.save()
        return [first, second]
    }

    static func sampleEpisodes() -> [EpisodeFile] {
        [
            EpisodeFile(url: URL(fileURLWithPath: "/tmp/EternalAlchemy-E01.mp4")),
            EpisodeFile(url: URL(fileURLWithPath: "/tmp/EternalAlchemy-E02.mp4")),
            EpisodeFile(url: URL(fileURLWithPath: "/tmp/EternalAlchemy-E03.mp4"))
        ]
    }
}
