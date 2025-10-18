import Foundation
import SwiftData

/// Handles lightweight data migrations that depend on runtime logic rather than SwiftData schema tools.
enum MigrationHelper {
    @MainActor
    static func runIfNeeded(container: ModelContainer) async {
        let context = container.mainContext
        let fetch = FetchDescriptor<AnimeModel>()

        guard let models = try? context.fetch(fetch), !models.isEmpty else { return }

        var needsSave = false
        for model in models {
            if model.providerID == 0 {
                model.providerID = model.kind.providerID(from: model.id)
                needsSave = true
            }
            if model.kindRaw.isEmpty {
                model.kind = .anime
                needsSave = true
            }
        }

        if needsSave {
            try? context.save()
        }
    }
}
