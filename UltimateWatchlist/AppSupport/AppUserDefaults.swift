import Foundation

/// Centralized access to the app-specific `UserDefaults` keys. Handles legacy key cleanup so renames do not lose state.
enum AppUserDefaults {
    private enum Key {
        static let recommendationsRefresh = "com.codex.UltimateLibrary.lastRecommendationsRefresh"
        static let legacyRecommendations = [
            "com.codex.UltimateWatchlist.lastRecommendationsRefresh"
        ]

        static let migrationFlag = "com.codex.UltimateLibrary.migratedToSwiftData"
        static let legacyMigrationFlags = [
            "com.codex.UltimateWatchlist.migratedToSwiftData"
        ]
    }

    private static var defaults: UserDefaults { .standard }

    static func lastRecommendationsRefreshDate() -> Date? {
        if let date = defaults.object(forKey: Key.recommendationsRefresh) as? Date {
            return date
        }
        for legacyKey in Key.legacyRecommendations {
            if let date = defaults.object(forKey: legacyKey) as? Date {
                return date
            }
        }
        return nil
    }

    static func setLastRecommendationsRefreshDate(_ date: Date) {
        defaults.set(date, forKey: Key.recommendationsRefresh)
        clearLegacyRecommendationsKey()
    }

    static func clearRecommendationsThrottle() {
        defaults.removeObject(forKey: Key.recommendationsRefresh)
        clearLegacyRecommendationsKey()
    }

    static func clearMigrationFlag() {
        defaults.removeObject(forKey: Key.migrationFlag)
        for key in Key.legacyMigrationFlags {
            defaults.removeObject(forKey: key)
        }
    }

    private static func clearLegacyRecommendationsKey() {
        for key in Key.legacyRecommendations {
            defaults.removeObject(forKey: key)
        }
    }
}
