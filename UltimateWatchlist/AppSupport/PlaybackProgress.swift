import Foundation

struct PlaybackProgress: Codable, Hashable {
    let episodeNumber: Int
    let seconds: Double
    let updatedAt: Date

    init(episodeNumber: Int, seconds: Double, updatedAt: Date = Date()) {
        self.episodeNumber = episodeNumber
        self.seconds = seconds
        self.updatedAt = updatedAt
    }

    private enum CodingKeys: String, CodingKey {
        case episodeNumber
        case seconds
        case updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        episodeNumber = try container.decode(Int.self, forKey: .episodeNumber)
        seconds = try container.decode(Double.self, forKey: .seconds)
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date()
    }
}

enum PlaybackProgressStore {
    static let progressDidChangeNotification = Notification.Name("PlaybackProgressDidChangeNotification")

    private static let indexKey = "PlaybackProgress_Index"

    private static func key(for id: Int) -> String {
        return "PlaybackProgress_\(id)"
    }

    private static func notifyChange() {
        NotificationCenter.default.post(name: progressDidChangeNotification, object: nil)
    }

    private static func ids() -> [Int] {
        let defaults = UserDefaults.standard
        return defaults.array(forKey: indexKey) as? [Int] ?? []
    }

    private static func store(ids: [Int]) {
        UserDefaults.standard.set(ids, forKey: indexKey)
    }

    private static func addToIndex(_ id: Int) {
        var current = ids()
        if !current.contains(id) {
            current.append(id)
            store(ids: current)
        }
    }

    private static func removeFromIndex(_ id: Int) {
        var current = ids()
        if let idx = current.firstIndex(of: id) {
            current.remove(at: idx)
            store(ids: current)
        }
    }

    static func load(for id: Int) -> PlaybackProgress? {
        let defaults = UserDefaults.standard
        guard let data = defaults.data(forKey: key(for: id)) else {
            return nil
        }
        let decoder = JSONDecoder()
        return try? decoder.decode(PlaybackProgress.self, from: data)
    }

    static func save(_ progress: PlaybackProgress, for id: Int) {
        let defaults = UserDefaults.standard
        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(progress) else { return }
        defaults.set(data, forKey: key(for: id))
        addToIndex(id)
        notifyChange()
    }

    static func clear(for id: Int) {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: key(for: id))
        removeFromIndex(id)
        notifyChange()
    }

    static func allProgress() -> [Int: PlaybackProgress] {
        var result: [Int: PlaybackProgress] = [:]
        for id in ids() {
            if let progress = load(for: id) {
                result[id] = progress
            }
        }
        return result
    }
}
