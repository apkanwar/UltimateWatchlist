import SwiftUI
import UIKit

struct SplashView: View {
    @Environment(\.colorScheme) private var colorScheme

    private func appIconImage() -> UIImage? {
        // Try alternate icon first (if set), otherwise default
        if let altName = UIApplication.shared.alternateIconName {
            // For alternate icons, the image name is the alt icon name itself
            if let image = UIImage(named: altName) {
                return image
            }
        }
        // Fallback to default app icon by reading Info.plist
        guard
            let iconsDict = Bundle.main.infoDictionary?["CFBundleIcons"] as? [String: Any],
            let primaryIcon = iconsDict["CFBundlePrimaryIcon"] as? [String: Any],
            let iconFiles = primaryIcon["CFBundleIconFiles"] as? [String]
        else {
            return nil
        }
        // Choose the largest icon filename (typically the last one)
        if let largest = iconFiles.last, let image = UIImage(named: largest) {
            return image
        }
        // Try any available icon file
        for name in iconFiles.reversed() {
            if let image = UIImage(named: name) { return image }
        }
        return nil
    }

    var body: some View {
        ZStack {
            // Background adapts to system appearance
            Rectangle()
                .fill(background)
                .ignoresSafeArea()

            VStack(spacing: 20) {
                appIcon
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(foreground)
            }
            .padding(32)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Loading")
    }

    private var background: Color {
        if colorScheme == .dark {
            // #282828
            return Color(red: 0x28/255.0, green: 0x28/255.0, blue: 0x28/255.0)
        } else {
            return .white
        }
    }

    private var foreground: Color {
        colorScheme == .dark ? .white : .black
    }

    private var appIcon: some View {
        // Use asset named "AppIconSplash" if available, otherwise fallback to app icon symbol
        Group {
            if colorScheme == .light, let darkVariant = UIImage(named: "AppIconDark") {
                // Show dark icon on white background (Light Mode)
                Image(uiImage: darkVariant)
                    .resizable()
                    .scaledToFit()
            } else if colorScheme == .dark, let lightVariant = UIImage(named: "AppIconLight") {
                // Optionally show light icon on dark background (Dark Mode)
                Image(uiImage: lightVariant)
                    .resizable()
                    .scaledToFit()
            } else if let uiImage = appIconImage() {
                // Fallback to actual app icon from bundle
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFit()
            } else {
                // Final fallback
                Image(systemName: "sparkles.tv.fill")
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(foreground)
            }
        }
        .frame(width: 120, height: 120)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(foreground.opacity(0.15))
        )
        .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.4 : 0.1), radius: 20, x: 0, y: 10)
        .accessibilityHidden(true)
    }
}

#Preview {
    Group {
        SplashView()
            .environment(\.colorScheme, .light)
        SplashView()
            .environment(\.colorScheme, .dark)
    }
}

