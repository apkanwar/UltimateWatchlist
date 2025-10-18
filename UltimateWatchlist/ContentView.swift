//
//  ContentView.swift
//  UltimateWatchlist
//
//  Created by Atinderpaul Kanwar on 2025-10-13.
//

import SwiftUI

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
    }
}

#Preview {
    ContentView()
}
