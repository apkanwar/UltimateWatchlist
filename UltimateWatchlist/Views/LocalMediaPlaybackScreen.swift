import Combine
import SwiftUI
import AVKit
#if canImport(AppKit)
import AppKit
#endif

final class LocalMediaPlaybackController: NSObject, ObservableObject {
    @Published private(set) var currentEpisode: EpisodeFile
    @Published private(set) var queue: [EpisodeFile]
    @Published private(set) var currentIndex: Int = 0
    @Published private(set) var isPlaying: Bool = false
    @Published private(set) var currentTime: Double = 0
    @Published private(set) var duration: Double = 0
    @Published private(set) var playbackError: String?
    @Published private(set) var didFinishQueue: Bool = false

    let animeID: Int
    let animeTitle: String
    let player: AVPlayer

    let baseIndex: Int
    let folderBookmarkData: Data?
    private var linkedFolderURL: URL?
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?
    private var statusObserver: AnyCancellable?
    private var lastSaved = Date.distantPast
    private var initialProgress: PlaybackProgress?
    private let externalFallback: EpisodeFile?

    init(animeID: Int, animeTitle: String, queue: [EpisodeFile], baseIndex: Int, initialProgress: PlaybackProgress?, externalFallback: EpisodeFile?, folderBookmarkData: Data?) {
        precondition(!queue.isEmpty, "Playback queue cannot be empty")
        self.animeID = animeID
        self.animeTitle = animeTitle
        self.queue = queue
        self.baseIndex = baseIndex
        self.currentEpisode = queue[0]
        self.player = AVPlayer()
        self.initialProgress = initialProgress
        self.externalFallback = externalFallback
        self.folderBookmarkData = folderBookmarkData
        super.init()
        player.actionAtItemEnd = .pause
        player.automaticallyWaitsToMinimizeStalling = true
        acquireFolderAccessIfNeeded()
        configureCurrentItem(seekingToInitialProgress: true)
        addTimeObserver()
    }

    deinit {
        cleanup()
    }

    func start() {
        player.play()
        isPlaying = true
        didFinishQueue = false
        persistProgressIfNeeded(force: true)
    }

    func togglePlayback() {
        if isPlaying {
            player.pause()
            isPlaying = false
            persistProgressIfNeeded(force: true)
        } else {
            player.play()
            isPlaying = true
        }
    }

    func stop() {
        persistProgressIfNeeded(force: true)
        player.pause()
        isPlaying = false
        playbackError = nil
        cleanup()
    }

    func seek(to time: Double) {
        guard time.isFinite else { return }
        let cmTime = CMTime(seconds: time, preferredTimescale: 600)
        player.seek(to: cmTime) { [weak self] _ in
            self?.currentTime = time
            self?.persistProgressIfNeeded(force: true)
        }
    }

    private func configureCurrentItem(seekingToInitialProgress: Bool) {
        guard let resolvedURL = resolvedURL(for: currentEpisode) else {
            playbackError = LocalMediaError.accessDenied.errorDescription ?? "Unable to access the linked folder."
            player.replaceCurrentItem(with: nil)
            isPlaying = false
            return
        }
        let item = AVPlayerItem(url: resolvedURL)
        duration = 0
        removeEndObserver()
        statusObserver?.cancel()
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            self?.handleItemFinished()
        }
        player.replaceCurrentItem(with: item)
        observeStatus(for: item)
        loadDuration(for: item)

        if seekingToInitialProgress,
           let progress = initialProgress,
           progress.episodeNumber == episodeNumber(for: currentIndex),
           progress.seconds > 0 {
            player.seek(to: CMTime(seconds: progress.seconds, preferredTimescale: 600))
            currentTime = progress.seconds
        } else {
            currentTime = 0
        }
        initialProgress = nil
        persistProgressIfNeeded(force: true)
    }

    private func handleItemFinished() {
        let nextIndex = currentIndex + 1
        if nextIndex < queue.count {
            currentIndex = nextIndex
            currentEpisode = queue[nextIndex]
            playbackError = nil
            configureCurrentItem(seekingToInitialProgress: false)
            player.play()
            isPlaying = true
            persistProgressIfNeeded(force: true)
        } else {
            PlaybackProgressStore.clear(for: animeID)
            lastSaved = Date()
            player.pause()
            isPlaying = false
            didFinishQueue = true
            if let fallback = externalFallback {
#if os(iOS) || os(tvOS)
                playbackError = "This format isn't supported for in-app playback on this device."
#else
                LocalMediaManager.presentPlayer(for: fallback, folderBookmark: folderBookmarkData)
#endif
            }
        }
    }

    private func observeStatus(for item: AVPlayerItem) {
        playbackError = nil
        statusObserver = item.publisher(for: \AVPlayerItem.status)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                guard let self else { return }
                switch status {
                case .failed:
                    self.player.pause()
                    self.isPlaying = false
                    self.playbackError = item.error?.localizedDescription ?? "Unable to play this file."
                default:
                    break
                }
            }
    }

    private func loadDuration(for item: AVPlayerItem) {
        Task { [weak self] in
            guard let self else { return }
            do {
                let time = try await item.asset.load(.duration)
                let seconds = time.seconds
                await MainActor.run {
                    self.duration = seconds.isFinite ? seconds : 0
                }
            } catch {
                await MainActor.run {
                    self.duration = 0
                }
            }
        }
    }

    private func addTimeObserver() {
        let interval = CMTime(seconds: 1, preferredTimescale: 2)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self else { return }
            let seconds = time.seconds
            if seconds.isFinite {
                self.currentTime = seconds
                self.persistProgressIfNeeded(force: false)
            }
        }
    }

    private func persistProgressIfNeeded(force: Bool) {
        guard queue.indices.contains(currentIndex) else { return }
        let now = Date()
        if !force && now.timeIntervalSince(lastSaved) < 5 { return }
        lastSaved = now
        let seconds = player.currentTime().seconds
        guard seconds.isFinite else { return }
        let episodeNumber = self.episodeNumber(for: currentIndex)
        let progress = PlaybackProgress(episodeNumber: episodeNumber, seconds: seconds, updatedAt: now)
        PlaybackProgressStore.save(progress, for: animeID)
    }

    private func episodeNumber(for index: Int) -> Int {
        if let number = queue[index].episodeNumber {
            return number
        }
        return baseIndex + index + 1
    }

    private func cleanup() {
        if let observer = timeObserver {
            player.removeTimeObserver(observer)
            timeObserver = nil
        }
        removeEndObserver()
        statusObserver?.cancel()
        statusObserver = nil
        if let folderURL = linkedFolderURL {
            LocalMediaManager.stopAccessIfNeeded(url: folderURL)
            linkedFolderURL = nil
        }
    }

    private func removeEndObserver() {
        if let observer = endObserver {
            NotificationCenter.default.removeObserver(observer)
            endObserver = nil
        }
    }

    private func acquireFolderAccessIfNeeded() {
        guard linkedFolderURL == nil, let bookmark = folderBookmarkData else { return }
        do {
            linkedFolderURL = try LocalMediaManager.resolveLinkedFolder(from: bookmark)
        } catch {
            linkedFolderURL = nil
            playbackError = LocalMediaError.accessDenied.errorDescription ?? "Access to the linked folder was denied."
        }
    }

    private func resolvedURL(for episode: EpisodeFile) -> URL? {
        if linkedFolderURL == nil, folderBookmarkData != nil {
            acquireFolderAccessIfNeeded()
        }
        if folderBookmarkData != nil && linkedFolderURL == nil {
            return nil
        }
        if let folderURL = linkedFolderURL {
            let folderPath = folderURL.standardizedFileURL.path
            let episodePath = episode.url.standardizedFileURL.path
            guard episodePath.hasPrefix(folderPath) else {
                return nil
            }
        }
        return episode.url
    }
}

struct LocalMediaPlaybackScreen: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var controller: LocalMediaPlaybackController
    private let onDismiss: (() -> Void)?
    private let externalFallback: EpisodeFile?

    init(animeID: Int, animeTitle: String, queue: [EpisodeFile], baseIndex: Int, initialProgress: PlaybackProgress?, externalFallback: EpisodeFile? = nil, folderBookmarkData: Data? = nil, onDismiss: (() -> Void)? = nil) {
        _controller = StateObject(
            wrappedValue: LocalMediaPlaybackController(
                animeID: animeID,
                animeTitle: animeTitle,
                queue: queue,
                baseIndex: baseIndex,
                initialProgress: initialProgress,
                externalFallback: externalFallback,
                folderBookmarkData: folderBookmarkData
            )
        )
        self.onDismiss = onDismiss
        self.externalFallback = externalFallback
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                if let error = controller.playbackError {
                    playbackErrorView(message: error)
                } else {
                    VideoPlayer(player: controller.player)
                        .background(Color.black)
                        .frame(minHeight: 240)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }

                playbackInfo
                    .padding(.horizontal)

                if controller.duration > 0 {
                    VStack(spacing: 8) {
                        Slider(
                            value: Binding(
                                get: { controller.currentTime },
                                set: { controller.seek(to: $0) }
                            ),
                            in: 0...controller.duration
                        )
                        HStack {
                            Text(timeString(controller.currentTime))
                            Spacer()
                            Text(timeString(controller.duration))
                        }
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal)
                }

                if controller.queue.count > 1 {
                    upcomingList
                }
            }
            .padding(.vertical, 20)
            .navigationTitle(controller.animeTitle)
#if os(iOS) || os(tvOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        controller.stop()
                        dismiss()
                        onDismiss?()
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button(controller.isPlaying ? "Pause" : "Play") {
                        controller.togglePlayback()
        }
    }
}

        }
        .interactiveDismissDisabled()
        .onAppear { controller.start() }
        .onDisappear { controller.stop() }
        .onChange(of: controller.didFinishQueue) { _, didFinish in
            guard didFinish else { return }
            dismiss()
            onDismiss?()
    }
}

#if DEBUG
private struct LocalMediaPlaybackScreenPreview: View {
    var body: some View {
        let episodes = PreviewData.sampleEpisodes()
        LocalMediaPlaybackScreen(
            animeID: 101,
            animeTitle: "Sample Series",
            queue: episodes,
            baseIndex: 0,
            initialProgress: PlaybackProgress(episodeNumber: 1, seconds: 42),
            externalFallback: episodes.last
        )
    }
}

#Preview("Inline Player") {
    LocalMediaPlaybackScreenPreview()
}
#endif

    @ViewBuilder
    private func playbackErrorView(message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .imageScale(.large)
                .foregroundStyle(.orange)
            Text("Playback Unavailable")
                .font(.headline)
            Text(message)
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            if let fallback = externalFallback {
                Text("We'll open \(fallback.displayName) with your default player instead.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Button {
                controller.stop()
                LocalMediaManager.presentPlayer(for: controller.currentEpisode, folderBookmark: controller.folderBookmarkData)
                dismiss()
            } label: {
                Label("Open in System Player", systemImage: "play.rectangle")
            }
        }
        .frame(maxWidth: .infinity, minHeight: 240)
        .padding()
        .background(errorBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var errorBackground: Color {
#if canImport(UIKit)
        return Color(.secondarySystemBackground)
#elseif canImport(AppKit)
        return Color(NSColor.windowBackgroundColor)
#else
        return Color.gray.opacity(0.2)
#endif
    }

    private var playbackInfo: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(controller.currentEpisode.displayName)
                .font(.headline)
            Text("Episode \(controller.currentEpisode.episodeNumber ?? controller.currentIndex + controller.baseIndex + 1)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var upcomingList: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Up Next")
                .font(.headline)
                .padding(.horizontal)

            ScrollView(.vertical, showsIndicators: true) {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(controller.queue.enumerated()), id: \.1.id) { index, episode in
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(episode.displayName)
                                    .font(.body.weight(index == controller.currentIndex ? .semibold : .regular))
                                if let number = episode.episodeNumber {
                                    Text("Episode \(number)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            if index == controller.currentIndex {
                                Label("Now", systemImage: "play.fill")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.blue)
                            }
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 6)
                        .background(
                            index == controller.currentIndex
                            ? Color.accentColor.opacity(0.1)
                            : Color.clear
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                }
                .padding(.bottom, 12)
            }
        }
    }

    private func timeString(_ seconds: Double) -> String {
        guard seconds.isFinite else { return "--:--" }
        let time = Int(seconds)
        let minutes = time / 60
        let secs = time % 60
        return String(format: "%02d:%02d", minutes, secs)
    }
}
