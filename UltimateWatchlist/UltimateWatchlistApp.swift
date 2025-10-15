import SwiftUI
import SwiftData

@main
struct UltimateWatchlistApp: App {
    @State private var container: ModelContainer = {
        let schema = Schema([AnimeModel.self, AnimeGenreModel.self, LibraryEntryModel.self])
        return try! ModelContainer(for: schema)
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .modelContainer(container)
                .task {
                    await MigrationHelper.runIfNeeded(container: container)
                }
        }
    }
}
