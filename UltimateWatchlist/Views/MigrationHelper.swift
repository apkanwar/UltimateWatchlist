import Foundation
import SwiftData

/// MigrationHelper is intentionally a no-op.
/// There are no legacy users to migrate, and the app has renamed Watchlist to Library.
/// Keeping this type allows existing call sites to remain, but it performs no work.
enum MigrationHelper {
    static func runIfNeeded(container: ModelContainer) async {
        // No migration required.
    }
}
