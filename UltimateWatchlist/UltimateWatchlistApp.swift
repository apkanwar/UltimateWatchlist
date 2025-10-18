import SwiftUI
import SwiftData

@main
struct UltimateWatchlistApp: App {
    @State private var container: ModelContainer = {
        do {
            return try ModelContainer(
                for: AnimeModel.self,
                AnimeGenreModel.self,
                LibraryEntryModel.self
            )
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
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
