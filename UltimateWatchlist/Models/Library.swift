//
//  Library.swift
//  UltimateWatchlist
//
//  Created by Codex on 2025-10-13.
//

import Foundation

enum LibraryStatus: String, CaseIterable, Codable, Identifiable {
    case currentlyWatching = "Currently Watching"
    case completed = "Completed"
    case onHold = "On Hold"
    case dropped = "Dropped"
    case planToWatch = "Plan to Watch"

    var id: String { rawValue }

    var systemImageName: String {
        switch self {
        case .currentlyWatching: return "play.circle.fill"
        case .completed: return "checkmark.circle.fill"
        case .onHold: return "pause.circle.fill"
        case .dropped: return "xmark.circle.fill"
        case .planToWatch: return "clock.fill"
        }
    }
}
