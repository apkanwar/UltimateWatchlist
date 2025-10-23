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

    static var tvMazeAPIKey: String {
        if let environmentValue = ProcessInfo.processInfo.environment["TVMAZE_API_KEY"], !environmentValue.isEmpty {
            return environmentValue
        }
        if let infoDictionaryValue = Bundle.main.object(forInfoDictionaryKey: "TVMazeAPIKey") as? String,
           !infoDictionaryValue.isEmpty {
            return infoDictionaryValue
        }
        return "uin_H1z_5VBcGn_yTnd5CCtC2Yhu6Mfv"
    }

    static var omdbAPIKey: String {
        if let environmentValue = ProcessInfo.processInfo.environment["OMDB_API_KEY"], !environmentValue.isEmpty {
            return environmentValue
        }
        if let infoDictionaryValue = Bundle.main.object(forInfoDictionaryKey: "OMDbAPIKey") as? String,
           !infoDictionaryValue.isEmpty {
            return infoDictionaryValue
        }
        return ""
    }
}
