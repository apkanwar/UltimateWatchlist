//
//  AppConfiguration.swift
//  UltimateWatchlist
//
//  Created by Codex on 2025-10-13.
//

import Foundation

enum AppConfiguration {
    static var malClientID: String {
        if let environmentValue = ProcessInfo.processInfo.environment["MAL_CLIENT_ID"], !environmentValue.isEmpty {
            return environmentValue
        }
        if let infoDictionaryValue = Bundle.main.object(forInfoDictionaryKey: "MALClientID") as? String,
           !infoDictionaryValue.isEmpty {
            return infoDictionaryValue
        }
        return ""
    }
}
