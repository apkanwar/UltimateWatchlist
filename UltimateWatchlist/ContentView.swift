//
//  ContentView.swift
//  UltimateWatchlist
//
//  Created by Atinderpaul Kanwar on 2025-10-13.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var discoverViewModel = DiscoverViewModel()

    var body: some View {
        TabView {
            DiscoverView(viewModel: discoverViewModel)
                .tabItem {
                    Label("Discover", systemImage: "sparkles.tv.fill")
                }
            LibraryView()
                .tabItem {
                    Label("Library", systemImage: "books.vertical")
                }
        }
    }
}

#Preview {
    ContentView()
}
