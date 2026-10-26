import AppKit
import SwiftUI

/// A card on Home saying Marquee has a Windows preview, for people with a PC too or friends
/// to tell. Closed for good with ✕.
@MainActor
struct WindowsPreviewCard: View {
    @AppStorage(Preferences.Key.windowsPromoDismissed.rawValue) private var dismissed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if !dismissed {
            HStack(spacing: 14) {
                Image(systemName: "pc")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 44, height: 44)
                    .background(Color.accentColor.opacity(0.14), in: Page.tile)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text("Marquee for Windows").font(.system(size: 14, weight: .semibold))
                        Text("Preview")
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(Color.primary.opacity(0.07), in: Capsule())
                    }
                    Text("An early build for Windows 10 and 11: the tray, shortcuts and settings so far, with captures and clipboard history on the way.")
                        .font(.system(size: 12.5))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Button("Get the Preview") { NSWorkspace.shared.open(UpdateNotifier.windowsURL) }
                    .glassButtonStyle()
                    .help("Open the Windows section of the Marquee website")
                Button {
                    if reduceMotion {
                        dismissed = true
                    } else {
                        withAnimation(.easeIn(duration: 0.18)) { dismissed = true }
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 20, height: 20)
                        .background(Color.primary.opacity(0.07), in: Circle())
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help("Don't show this again")
                .accessibilityLabel("Hide the Windows preview card")
            }
            .pageCard(padding: 16)
            .transition(.opacity.combined(with: .scale(scale: 0.97)))
            .accessibilityElement(children: .contain)
        }
    }
}
