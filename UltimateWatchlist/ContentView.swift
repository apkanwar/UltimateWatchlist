//
//  ContentView.swift
//  UltimateWatchlist
//
//  Created by Atinderpaul Kanwar on 2025-10-13.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    @StateObject private var discoverViewModel = DiscoverViewModel()
    @StateObject private var navigation = AppNavigation()
    @StateObject private var playbackCoordinator = PlaybackCoordinator()

    var body: some View {
        TabView(selection: $navigation.selectedTab) {
            DiscoverView(viewModel: discoverViewModel)
                .tabItem {
                    Label("Discover", systemImage: "sparkles.tv.fill")
                }
                .tag(AppTab.discover)
            LibraryView()
                .tabItem {
                    Label("Library", systemImage: "books.vertical")
                }
                .tag(AppTab.library)
        }
        .environmentObject(navigation)
        .environmentObject(playbackCoordinator)
        .sheet(item: $playbackCoordinator.pendingRequest) { request in
            LocalMediaPlaybackRoot(request: request)
                .environmentObject(playbackCoordinator)
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(PreviewData.makeContainer(populated: true))
}

private struct LocalMediaPlaybackRoot: View {
    @EnvironmentObject private var playbackCoordinator: PlaybackCoordinator
    let request: PlaybackRequest

    var body: some View {
        LocalMediaPlaybackScreen(
            animeID: request.animeID,
            animeTitle: request.title,
            queue: request.queue,
            baseIndex: request.baseIndex,
            initialProgress: request.initialProgress,
            externalFallback: request.externalFallback,
            folderBookmarkData: request.folderBookmarkData
        ) {
            playbackCoordinator.clear()
        }
    }
}
