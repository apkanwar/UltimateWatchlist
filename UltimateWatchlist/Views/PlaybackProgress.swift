import Foundation

struct PlaybackProgress: Codable {
    let episodeNumber: Int
    let seconds: Double
}

enum PlaybackProgressStore {
    private static func key(for id: Int) -> String {
        return "PlaybackProgress_\(id)"
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
        if let data = try? encoder.encode(progress) {
            defaults.set(data, forKey: key(for: id))
        }
    }
    
    static func clear(for id: Int) {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: key(for: id))
    }
}
