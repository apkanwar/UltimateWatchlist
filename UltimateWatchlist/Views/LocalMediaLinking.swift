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

public struct EpisodeFile: Identifiable, Hashable {
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
    public static func == (lhs: EpisodeFile, rhs: EpisodeFile) -> Bool {
        lhs.id == rhs.id
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
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

    public typealias FolderLinkResult = (bookmark: Data, displayPath: String)

    private static var bookmarkOptions: URL.BookmarkCreationOptions {
#if os(macOS)
        return [.withSecurityScope]
#else
        return []
#endif
    }

    private static var bookmarkResolutionOptions: URL.BookmarkResolutionOptions {
#if os(macOS)
        return [.withSecurityScope]
#else
        return []
#endif
    }
    
    private final class ScopedFolderAccessHolder {
        let url: URL
        init(url: URL) {
            self.url = url
        }
        deinit {
            Task { @MainActor in
                LocalMediaManager.stopAccessIfNeeded(url: url)
            }
        }
    }
    
    private static var folderAccessAssociationKey: UInt8 = 0
    
#if os(iOS) || os(tvOS)
    private static func findPresentingViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .filter { $0.activationState == .foregroundActive }
        
        for scene in scenes {
            if let root = scene.windows.first(where: { $0.isKeyWindow })?.rootViewController {
                return topViewController(from: root)
            }
        }
        
        if let windowProvider = UIApplication.shared.delegate?.window,
           let window = windowProvider,
           let root = window.rootViewController {
            return topViewController(from: root)
        }
        
        return nil
    }

    private static func topViewController(from controller: UIViewController) -> UIViewController {
        if let presented = controller.presentedViewController {
            return topViewController(from: presented)
        }
        if let navigation = controller as? UINavigationController,
           let visible = navigation.visibleViewController {
            return topViewController(from: visible)
        }
        if let tab = controller as? UITabBarController,
           let selected = tab.selectedViewController {
            return topViewController(from: selected)
        }
        return controller
    }
#endif
    
    // MARK: Link Folder
    
    /// Link local folder using platform-specific UI and return bookmark data and display path.
    /// The caller is responsible for persisting these values on the entry model.
    public static func linkFolder() async throws -> FolderLinkResult {
        #if os(iOS) || os(tvOS)
        // UIDocumentPicker for folder selection
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<FolderLinkResult, Error>) in
            class Delegate: NSObject, UIDocumentPickerDelegate {
                var continuation: CheckedContinuation<FolderLinkResult, Error>?
                init(continuation: CheckedContinuation<FolderLinkResult, Error>) {
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
                        let bookmark = try url.bookmarkData(options: LocalMediaManager.bookmarkOptions, includingResourceValuesForKeys: nil, relativeTo: nil)
                        continuation?.resume(returning: (bookmark: bookmark, displayPath: url.lastPathComponent))
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
            
            guard let presenter = findPresentingViewController() else {
                continuation.resume(throwing: LocalMediaError.folderNotLinked)
                return
            }
            
            // Keep delegateHolder alive while presented
            objc_setAssociatedObject(picker, "LocalMediaManagerDelegate", delegateHolder, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
            
            presenter.present(picker, animated: true, completion: nil)
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
            let bookmark = try url.bookmarkData(options: bookmarkOptions, includingResourceValuesForKeys: nil, relativeTo: nil)
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
                          options: bookmarkResolutionOptions,
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
    public static func presentPlayer(for file: EpisodeFile, folderBookmark: Data? = nil) {
        #if os(iOS) || os(tvOS)
        var folderAccessHolder: ScopedFolderAccessHolder?
        if let bookmark = folderBookmark {
            do {
                let folderURL = try LocalMediaManager.resolveLinkedFolder(from: bookmark)
                folderAccessHolder = ScopedFolderAccessHolder(url: folderURL)
            } catch {
                folderAccessHolder = nil
            }
        }
        let player = AVPlayer(url: file.url)
        if let holder = folderAccessHolder {
            objc_setAssociatedObject(player, &folderAccessAssociationKey, holder, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
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
            var linkedFolderURL: URL?
            if let bookmark = folderBookmark {
                do {
                    linkedFolderURL = try LocalMediaManager.resolveLinkedFolder(from: bookmark)
                } catch {
                    linkedFolderURL = nil
                }
            }
            NSWorkspace.shared.open(file.url)
            if let folderURL = linkedFolderURL {
                let delay = DispatchTime.now() + .seconds(5)
                DispatchQueue.main.asyncAfter(deadline: delay) {
                    LocalMediaManager.stopAccessIfNeeded(url: folderURL)
                }
            }
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

// MARK: - Playback capability helpers

public extension LocalMediaManager {
    private static let inlineSupportedExtensions: Set<String> = ["mp4", "m4v", "mov", "avi"]

    static func supportsInlinePlayback(_ url: URL) -> Bool {
        inlineSupportedExtensions.contains(url.pathExtension.lowercased())
    }

    static func splitQueueForInlinePlayback(_ queue: [EpisodeFile]) -> (playable: [EpisodeFile], firstUnsupported: EpisodeFile?) {
        guard let index = queue.firstIndex(where: { !supportsInlinePlayback($0.url) }) else {
            return (queue, nil)
        }
        let playable = Array(queue.prefix(index))
        return (playable, queue[index])
    }
}
