import Combine
import Foundation

enum AppTab: Hashable {
    case discover
    case library
}

final class AppNavigation: ObservableObject {
    @Published var selectedTab: AppTab = .discover
}

struct PlaybackRequest: Identifiable, Hashable {
    let id = UUID()
    let animeID: Int
    let title: String
    let queue: [EpisodeFile]
    let baseIndex: Int
    let initialProgress: PlaybackProgress?
    let externalFallback: EpisodeFile?
    let folderBookmarkData: Data?
}

final class PlaybackCoordinator: ObservableObject {
    @Published var pendingRequest: PlaybackRequest?

    func begin(_ request: PlaybackRequest) {
        DispatchQueue.main.async {
            self.pendingRequest = request
        }
    }

    func clear() {
        DispatchQueue.main.async {
            self.pendingRequest = nil
        }
    }
}
