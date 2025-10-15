//
//  AnimePosterView.swift
//  UltimateWatchlist
//
//  Created by Codex on 2025-10-13.
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct AnimePosterView: View {
    let imageURL: URL?
    var contentMode: ContentMode = .fill

    var body: some View {
        Group {
            if let url = imageURL {
                AsyncImage(url: url, transaction: Transaction(animation: .easeInOut)) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: contentMode)
                    case .failure:
                        placeholder
                    case .empty:
                        ProgressView()
                    @unknown default:
                        placeholder
                    }
                }
            } else {
                placeholder
            }
        }
        .background(backgroundColor)
    }

    private var placeholder: some View {
        ZStack {
            placeholderColor
            Image(systemName: "popcorn.fill")
                .imageScale(.large)
                .foregroundStyle(.secondary)
        }
    }

    private var backgroundColor: Color {
        #if canImport(UIKit)
        return Color(UIColor.secondarySystemBackground)
        #else
        return Color.secondary.opacity(0.15)
        #endif
    }

    private var placeholderColor: Color {
        #if canImport(UIKit)
        return Color(UIColor.systemGray5)
        #else
        return Color.secondary.opacity(0.25)
        #endif
    }
}

#Preview {
    AnimePosterView(imageURL: nil)
        .frame(width: 140, height: 200)
        .clipShape(RoundedRectangle(cornerRadius: 12))
}
