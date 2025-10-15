import Foundation
import SwiftData

@Model
final class LibraryEntryModel: Identifiable {
    @Attribute(.unique) var id: Int // same as anime.id
    var statusRaw: String
    var addedAt: Date
    // Security-scoped bookmark data for a linked local folder (if user linked downloads)
    var linkedFolderBookmarkData: Data?
    // Cached, human-readable path for display purposes only (not used for access)
    var linkedFolderDisplayPath: String?
    @Relationship(deleteRule: .nullify) var anime: AnimeModel

    init(
        id: Int,
        status: LibraryStatus,
        addedAt: Date = Date(),
        anime: AnimeModel,
        linkedFolderBookmarkData: Data? = nil,
        linkedFolderDisplayPath: String? = nil
    ) {
        self.id = id
        self.statusRaw = status.rawValue
        self.addedAt = addedAt
        self.anime = anime
        self.linkedFolderBookmarkData = linkedFolderBookmarkData
        self.linkedFolderDisplayPath = linkedFolderDisplayPath
    }
}

extension LibraryEntryModel {
    var status: LibraryStatus {
        get { LibraryStatus(rawValue: statusRaw) ?? .planToWatch }
        set { statusRaw = newValue.rawValue }
    }
}
