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
    @AppStorage(AppAppearance.storageKey) private var storedAppearance: String = AppAppearance.system.rawValue
    @StateObject private var navigation = AppNavigation()
    @StateObject private var playbackCoordinator = PlaybackCoordinator()
    @State private var showingSplash: Bool = true

    private var resolvedAppearance: AppAppearance {
        AppAppearance(rawValue: storedAppearance) ?? .system
    }

    var body: some View {
        ZStack {
            mainContent
                .opacity(showingSplash ? 0 : 1)

            if showingSplash {
                SplashView()
                    .transition(.opacity)
            }
        }
        .onAppear {
            // Simulate brief loading window; replace with real readiness checks if needed
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                withAnimation(.easeInOut(duration: 0.35)) {
                    showingSplash = false
                }
            }
        }
    }

    private var mainContent: some View {
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
#if os(iOS)
            NavigationStack {
                SettingsView()
            }
            .tabItem {
                Label("Settings", systemImage: "gearshape")
            }
            .tag(AppTab.settings)
#endif
        }
        .environmentObject(navigation)
        .environmentObject(playbackCoordinator)
        .sheet(item: $playbackCoordinator.pendingRequest) { request in
            LocalMediaPlaybackRoot(request: request)
                .environmentObject(playbackCoordinator)
        }
        .preferredColorScheme(resolvedAppearance.colorScheme)
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
