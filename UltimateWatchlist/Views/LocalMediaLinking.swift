import Foundation
import AVKit
import AVFoundation
import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

#if canImport(AppKit)
import AppKit
#endif

// MARK: - EpisodeFile

public struct EpisodeFile: Identifiable {
    public let id: URL
    public let url: URL
    public let displayName: String
    public let episodeNumber: Int?
    
    public init(url: URL) {
        self.id = url
        self.url = url
        self.displayName = url.lastPathComponent
        self.episodeNumber = EpisodeFile.inferEpisodeNumber(from: url.lastPathComponent)
    }
    
    /// Attempts to infer episode number from filename using regex /(ep|episode)?\s*(\d{1,3})/i and some common patterns.
    public static func inferEpisodeNumber(from filename: String) -> Int? {
        // Lowercased for easier matching
        let lower = filename.lowercased()
        
        // Possible patterns to check:
        // ep\d+
        // episode\d+
        // e\d+
        // s\d+e\d+ (season-episode)
        // just numbers maybe at start or end
        
        // 1. Regex for ep or episode prefix: /(ep|episode)?\s*(\d{1,3})/
        let regexPattern = #"(?i)(?:ep|episode|e)?\s*(\d{1,3})"#
        if let regex = try? NSRegularExpression(pattern: regexPattern, options: []) {
            let range = NSRange(lower.startIndex..<lower.endIndex, in: lower)
            if let match = regex.firstMatch(in: lower, options: [], range: range),
               match.numberOfRanges > 1,
               let epRange = Range(match.range(at: 1), in: lower) {
                let epStr = String(lower[epRange])
                if let epNum = Int(epStr) {
                    return epNum
                }
            }
        }
        
        // 2. Look for s\d+e\d+ pattern, return episode number from e\d+
        let sePattern = #"s\d{1,2}e(\d{1,3})"#
        if let regex = try? NSRegularExpression(pattern: sePattern, options: [.caseInsensitive]) {
            let range = NSRange(lower.startIndex..<lower.endIndex, in: lower)
            if let match = regex.firstMatch(in: lower, options: [], range: range),
               match.numberOfRanges > 1,
               let epRange = Range(match.range(at: 1), in: lower) {
                let epStr = String(lower[epRange])
                if let epNum = Int(epStr) {
                    return epNum
                }
            }
        }
        
        // 3. Look for just a number anywhere that might be episode
        let numberRegexPattern = #"\b(\d{1,3})\b"#
        if let regex = try? NSRegularExpression(pattern: numberRegexPattern, options: []) {
            let range = NSRange(lower.startIndex..<lower.endIndex, in: lower)
            let matches = regex.matches(in: lower, options: [], range: range)
            if !matches.isEmpty {
                // Pick the first number after keywords like ep or episode if possible
                for match in matches {
                    if match.numberOfRanges > 1,
                       let numRange = Range(match.range(at: 1), in: lower) {
                        let numStr = String(lower[numRange])
                        if let epNum = Int(numStr) {
                            return epNum
                        }
                    }
                }
            }
        }
        
        return nil
    }
}

// MARK: - LocalMediaError

public enum LocalMediaError: Error, LocalizedError {
    case folderNotLinked
    case accessDenied
    case resolutionFailed
    case noEpisodesFound
    case playbackFailed(String)
    
    public var errorDescription: String? {
        switch self {
        case .folderNotLinked:
            return NSLocalizedString("No folder has been linked.", comment: "")
        case .accessDenied:
            return NSLocalizedString("Access to the linked folder was denied.", comment: "")
        case .resolutionFailed:
            return NSLocalizedString("Failed to resolve the linked folder.", comment: "")
        case .noEpisodesFound:
            return NSLocalizedString("No episode files were found in the linked folder.", comment: "")
        case .playbackFailed(let message):
            return NSLocalizedString("Playback failed: \(message)", comment: "")
        }
    }
}

// MARK: - LocalMediaManager

@MainActor
public final class LocalMediaManager {
    private init() {}
    
    // MARK: Link Folder
    
    /// Link local folder using platform-specific UI and return bookmark data and display path.
    /// The caller is responsible for persisting these values on the entry model.
    public static func linkFolder() async throws -> (bookmark: Data, displayPath: String) {
        #if os(iOS) || os(tvOS)
        // UIDocumentPicker for folder selection
        return try await withCheckedThrowingContinuation { continuation in
            class Delegate: NSObject, UIDocumentPickerDelegate {
                var continuation: CheckedContinuation<(Data, String), Error>?
                init(continuation: CheckedContinuation<(Data, String), Error>) {
                    self.continuation = continuation
                }
                func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
                    guard let url = urls.first else {
                        continuation?.resume(throwing: LocalMediaError.folderNotLinked)
                        continuation = nil
                        return
                    }
                    do {
                        // Create security scoped bookmark
                        let bookmark = try url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
                        continuation?.resume(returning: (bookmark, url.lastPathComponent))
                        continuation = nil
                    } catch {
                        continuation?.resume(throwing: error)
                        continuation = nil
                    }
                }
                func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
                    continuation?.resume(throwing: LocalMediaError.folderNotLinked)
                    continuation = nil
                }
            }
            
            let delegateHolder = Delegate(continuation: continuation)
            let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.folder], asCopy: false)
            picker.allowsMultipleSelection = false
            picker.delegate = delegateHolder
            picker.modalPresentationStyle = .formSheet
            
            guard let rootVC = UIApplication.shared.windows.first(where: { $0.isKeyWindow })?.rootViewController else {
                continuation.resume(throwing: LocalMediaError.folderNotLinked)
                return
            }
            
            // Keep delegateHolder alive while presented
            objc_setAssociatedObject(picker, "LocalMediaManagerDelegate", delegateHolder, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
            
            rootVC.present(picker, animated: true, completion: nil)
        }
        #elseif canImport(AppKit)
        // macOS NSOpenPanel
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.title = "Select Folder to Link"
        panel.prompt = "Link Folder"
        
        let response = panel.runModal()
        guard response == .OK, let url = panel.url else {
            throw LocalMediaError.folderNotLinked
        }
        
        do {
            let bookmark = try url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
            return (bookmark, url.lastPathComponent)
        } catch {
            throw error
        }
        #else
        throw LocalMediaError.folderNotLinked
        #endif
    }
    
    // MARK: Resolve Linked Folder
    
    private static var accessedURLs = NSMapTable<NSURL, NSNumber>(keyOptions: .strongMemory, valueOptions: .strongMemory)
    
    /// Attempts to resolve a linked folder URL from bookmark data by resolving bookmark and starting security scoped access.
    /// Call stopAccessIfNeeded(url:) when done.
    /// - Parameter bookmarkData: The bookmark data representing the linked folder.
    /// - Returns: The resolved URL with security access started.
    public static func resolveLinkedFolder(from bookmarkData: Data) throws -> URL {
        var isStale = false
        let url = try URL(resolvingBookmarkData: bookmarkData,
                          options: [.withSecurityScope],
                          relativeTo: nil,
                          bookmarkDataIsStale: &isStale)
        guard url.startAccessingSecurityScopedResource() else {
            throw LocalMediaError.accessDenied
        }
        accessedURLs.setObject(NSNumber(value: true), forKey: url as NSURL)
        return url
    }
    
    /// Stops security scoped access for a URL if it was previously started.
    /// - Parameter url: The URL to stop accessing.
    public static func stopAccessIfNeeded(url: URL) {
        let nsURL = url as NSURL
        if accessedURLs.object(forKey: nsURL) != nil {
            url.stopAccessingSecurityScopedResource()
            accessedURLs.removeObject(forKey: nsURL)
        }
    }
    
    // MARK: List Episodes
    
    /// Recursively enumerates video files in the folder with common video extensions.
    /// Sorts by inferred episode number (ascending), then by display name.
    /// - Parameter folderURL: Folder URL to enumerate.
    /// - Returns: Array of EpisodeFile found.
    public static func listEpisodes(in folderURL: URL) throws -> [EpisodeFile] {
        let videoExtensions = ["mp4", "mkv", "mov", "avi", "m4v"]
        var files: [EpisodeFile] = []
        let fm = FileManager.default
        let keys: [URLResourceKey] = [.isRegularFileKey, .nameKey]
        
        guard let enumerator = fm.enumerator(at: folderURL, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles, .skipsPackageDescendants]) else {
            throw LocalMediaError.noEpisodesFound
        }
        
        for case let fileURL as URL in enumerator {
            guard let resourceValues = try? fileURL.resourceValues(forKeys: Set(keys)),
                  resourceValues.isRegularFile == true else {
                continue
            }
            
            if videoExtensions.contains(fileURL.pathExtension.lowercased()) {
                files.append(EpisodeFile(url: fileURL))
            }
        }
        
        if files.isEmpty {
            throw LocalMediaError.noEpisodesFound
        }
        
        return files.sorted {
            switch ($0.episodeNumber, $1.episodeNumber) {
            case let (a?, b?):
                if a == b {
                    return $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending
                }
                return a < b
            case (nil, nil):
                return $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending
            case (nil, _?):
                return false
            case (_?, nil):
                return true
            }
        }
    }
    
    // MARK: Present Player
    
    /// Presents a player to play the episode file.
    /// On iOS presents AVPlayerViewController on top-most.
    /// On macOS opens file with NSWorkspace.
    /// - Parameter file: EpisodeFile to play.
    public static func presentPlayer(for file: EpisodeFile) {
        #if os(iOS) || os(tvOS)
        let player = AVPlayer(url: file.url)
        let playerVC = AVPlayerViewController()
        playerVC.player = player
        
        guard let rootVC = UIApplication.shared.windows.first(where: { $0.isKeyWindow })?.rootViewController else {
            return
        }
        
        DispatchQueue.main.async {
            rootVC.present(playerVC, animated: true) {
                player.play()
            }
        }
        #elseif canImport(AppKit)
        DispatchQueue.main.async {
            NSWorkspace.shared.open(file.url)
        }
        #else
        // Unsupported platform - do nothing
        #endif
    }
}

// MARK: - SwiftUI Convenience Views

#if canImport(SwiftUI)

/// A SwiftUI view that shows a list of episode files with buttons to play them.
public struct LocalEpisodePickerView: View {
    public let episodes: [EpisodeFile]
    public let onSelect: (EpisodeFile) -> Void
    
    public init(episodes: [EpisodeFile], onSelect: @escaping (EpisodeFile) -> Void) {
        self.episodes = episodes
        self.onSelect = onSelect
    }
    
    public var body: some View {
        List(episodes) { episode in
            Button(action: {
                onSelect(episode)
            }) {
                HStack {
                    Text(episode.displayName)
                    Spacer()
                    if let ep = episode.episodeNumber {
                        Text("Ep \(ep)").foregroundColor(.secondary).font(.footnote)
                    }
                }
            }
        }
        .navigationTitle("Episodes")
    }
}

/// A SwiftUI view modifier presenting a Menu with local media actions: Link Folder, Unlink Folder, Browse Episodes.
/// Browse Episodes is shown only when a folder is linked (indicated by a Bool binding).
public struct LocalMediaActionsButton: View {
    public typealias LinkAction = () async throws -> Void
    public typealias UnlinkAction = () -> Void
    public typealias BrowseAction = () -> Void
    
    private let isLinked: Bool
    private let linkAction: LinkAction
    private let unlinkAction: UnlinkAction
    private let browseAction: BrowseAction
    
    public init(isLinked: Bool,
                linkAction: @escaping LinkAction,
                unlinkAction: @escaping UnlinkAction,
                browseAction: @escaping BrowseAction) {
        self.isLinked = isLinked
        self.linkAction = linkAction
        self.unlinkAction = unlinkAction
        self.browseAction = browseAction
    }
    
    public var body: some View {
        Menu {
            Button("Link Folder") {
                Task {
                    do {
                        try await linkAction()
                    } catch {
                        // Handle error if needed
                    }
                }
            }
            if isLinked {
                Button("Unlink Folder", role: .destructive) {
                    unlinkAction()
                }
                Button("Browse Episodes") {
                    browseAction()
                }
            }
        } label: {
            Image(systemName: "folder")
                .imageScale(.large)
                .accessibilityLabel("Local Media Actions")
        }
    }
}

#endif
