//
//  APICache.swift
//  UltimateWatchlist
//
//  Created by Codex on 2025-10-22.
//

import Foundation

/// Lightweight in-memory response cache shared across networking services.
actor APICache {
    static let shared = APICache()

    private struct Entry {
        let data: Data
        let expiresAt: Date
    }

    private var storage: [String: Entry] = [:]
    private let defaultTTL: TimeInterval = 300

    func data(for url: URL) -> Data? {
        let key = cacheKey(for: url)
        guard let entry = storage[key] else {
            return nil
        }
        if entry.expiresAt > Date() {
            return entry.data
        }
        storage.removeValue(forKey: key)
        return nil
    }

    func store(_ data: Data, for url: URL, ttl: TimeInterval?) {
        let effectiveTTL = (ttl ?? defaultTTL)
        guard effectiveTTL > 0 else { return }
        let key = cacheKey(for: url)
        storage[key] = Entry(data: data, expiresAt: Date().addingTimeInterval(effectiveTTL))
    }

    func removeData(for url: URL) {
        let key = cacheKey(for: url)
        storage.removeValue(forKey: key)
    }

    func removeAll() {
        storage.removeAll()
    }

    private func cacheKey(for url: URL) -> String {
        url.absoluteString
    }
}
