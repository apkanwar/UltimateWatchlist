import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var entries: [LibraryEntryModel]

    private let refreshKey = "com.codex.UltimateWatchlist.lastRecommendationsRefresh"

    var body: some View {
        List {
            Section("Recommendations") {
                Button {
                    UserDefaults.standard.removeObject(forKey: refreshKey)
                } label: {
                    Label("Refresh recommendations now", systemImage: "arrow.clockwise")
                }
                .accessibilityLabel("Refresh recommendations now")
                Text("Recommendations refresh at most once per day. Use this to bypass the throttle.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

#if DEBUG
            Section("Debug") {
                Button(role: .destructive) {
                    // Clear library
                    for e in entries { modelContext.delete(e) }
                    try? modelContext.save()
                } label: {
                    Label("Clear library", systemImage: "trash")
                }

                Button {
                    // Reset migration state
                    UserDefaults.standard.removeObject(forKey: "com.codex.UltimateWatchlist.migratedToSwiftData")
                } label: {
                    Label("Reset migration state", systemImage: "arrow.uturn.backward")
                }
            }
#endif

            Section("Sync") {
                Label("iCloud sync is enabled via CloudKit", systemImage: "icloud")
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Settings")
    }
}

#Preview {
    let container = try! ModelContainer(for: AnimeModel.self, AnimeGenreModel.self, LibraryEntryModel.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    return NavigationStack { SettingsView() }
        .modelContainer(container)
}
