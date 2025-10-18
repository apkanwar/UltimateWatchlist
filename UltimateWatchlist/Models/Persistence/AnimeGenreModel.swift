import Foundation
import SwiftData

@Model
final class AnimeGenreModel: Identifiable {
    @Attribute(.unique) var id: Int
    var name: String

    init(id: Int, name: String) {
        self.id = id
        self.name = name
    }
}

extension AnimeGenreModel {
    convenience init(from dto: AnimeGenre) {
        self.init(id: dto.id, name: dto.name)
    }
}
