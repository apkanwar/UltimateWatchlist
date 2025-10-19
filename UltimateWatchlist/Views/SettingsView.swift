import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var entries: [LibraryEntryModel]
    @AppStorage(AppAppearance.storageKey) private var storedAppearance: String = AppAppearance.system.rawValue

    var body: some View {
        List {
            Section("Appearance") {
                Picker("Theme", selection: appearanceBinding) {
                    ForEach(AppAppearance.allCases) { appearance in
                        Text(appearance.title).tag(appearance)
                    }
                }
                .pickerStyle(.segmented)

                Text("Choose whether the app follows the system appearance or stays in light or dark mode.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Recommendations") {
                Button {
                    AppUserDefaults.clearRecommendationsThrottle()
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
                    AppUserDefaults.clearMigrationFlag()
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

    private var appearanceBinding: Binding<AppAppearance> {
        Binding(
            get: { AppAppearance(rawValue: storedAppearance) ?? .system },
            set: { storedAppearance = $0.rawValue }
        )
    }
}

#Preview {
    NavigationStack { SettingsView() }
        .modelContainer(PreviewData.makeContainer(populated: true))
}
