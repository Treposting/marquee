import AppKit
import SwiftUI

/// A small card for QuitX, a free menu bar app to quit and force quit apps. On Home it
/// can be closed for good with ✕; the QuitX page in the sidebar always shows it. The icon is
/// drawn here, so nothing is downloaded.
@MainActor
struct QuitXPromo: View {
    var dismissible = true
    @AppStorage(Preferences.Key.quitXPromoDismissed.rawValue) private var dismissed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovering = false

    /// QuitX's brand amber.
    static let amber = Color(red: 1, green: 0.72, blue: 0)
    /// Amber for symbols on the page: darker in light mode so it stays readable (3:1 or more).
    static let amberInk = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(red: 1, green: 0.72, blue: 0, alpha: 1)
            : NSColor(red: 0.7, green: 0.42, blue: 0, alpha: 1)
    })
    static let url = URL(string: "https://quitx.kiron.dev")!

    private static let features = [
        Feature(symbol: "xmark.circle", title: "Quit all"),
        Feature(symbol: "bolt.circle", title: "Force quit"),
        Feature(symbol: "eye.circle", title: "Background apps"),
    ]

    private struct Feature: Identifiable {
        let symbol: String
        let title: String
        var id: String { title }
    }

    var body: some View {
        if !dismissed || !dismissible {
            HStack(alignment: .center, spacing: 16) {
                icon
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text("QuitX")
                            .font(.system(size: 15, weight: .semibold))
                        Text("Free · Open source")
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(Color.primary.opacity(0.07), in: Capsule())
                    }
                    Text("Quit anything from the menu bar. Quit one app, a few or all of them, force quit with ⌥, and see the helpers hiding in the background.")
                        .font(.system(size: 12.5))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 12) {
                        ForEach(Self.features) { feature in
                            Label(feature.title, systemImage: feature.symbol)
                                .font(.system(size: 11.5, weight: .medium))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
                Spacer(minLength: 8)
                Button {
                    NSWorkspace.shared.open(Self.url)
                } label: {
                    Label("Get QuitX", systemImage: "arrow.up.right")
                        .labelStyle(TrailingIconLabelStyle())
                        // Dark text on amber reads far better than white (contrast about 11:1).
                        .foregroundStyle(Color.black.opacity(0.85))
                        .padding(.horizontal, 4)
                }
                .glassButtonStyle(prominent: true)
                .tint(Self.amber)
                .controlSize(.large)
                .help("Open quitx.kiron.dev")
            }
            .padding(.vertical, 16)
            .padding(.leading, 16)
            .padding(.trailing, dismissible ? 40 : 16)
            .glassSurface(Page.card, tint: Self.amber.opacity(hovering ? 0.16 : 0.1))
            .overlay(alignment: .topTrailing) {
                if dismissible { dismissButton }
            }
            .onHover { inside in
                if reduceMotion {
                    hovering = inside
                } else {
                    withAnimation(.easeOut(duration: 0.2)) { hovering = inside }
                }
            }
            .transition(.opacity.combined(with: .scale(scale: 0.97)))
            .accessibilityElement(children: .contain)
            .accessibilityLabel("QuitX, a free app to quit and force quit apps from the menu bar")
        }
    }

    private var dismissButton: some View {
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
        .padding(10)
        .help("Don't show this again")
        .accessibilityLabel("Hide the QuitX suggestion")
    }

    /// QuitX's look: a power symbol on an amber squircle, nudged on hover.
    private var icon: some View {
        RoundedRectangle(cornerRadius: 13, style: .continuous)
            .fill(LinearGradient(colors: [Self.amber, Color(red: 1, green: 0.55, blue: 0)],
                                 startPoint: .top, endPoint: .bottom))
            .frame(width: 54, height: 54)
            .overlay {
                Image(systemName: "power")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(Color.black.opacity(0.82))
            }
            .shadow(color: Self.amber.opacity(hovering ? 0.45 : 0.25), radius: hovering ? 10 : 6, y: 3)
            .rotationEffect(.degrees(hovering && !reduceMotion ? -6 : 0))
            .scaleEffect(hovering && !reduceMotion ? 1.05 : 1)
            .accessibilityHidden(true)
    }
}

/// Title first, then the icon ("Get QuitX ↗").
private struct TrailingIconLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 5) {
            configuration.title
            configuration.icon.font(.system(size: 11, weight: .bold))
        }
    }
}

/// The QuitX page in the sidebar: the card, then what QuitX does.
@MainActor
struct QuitXPage: View {
    private struct Highlight: Identifiable {
        let symbol: String
        let title: String
        let text: String
        var id: String { title }
    }

    private static let highlights = [
        Highlight(symbol: "checklist", title: "Quit one, some or all",
                  text: "Every running app in one list with its windows and helpers. Search, or sort by name, CPU or memory."),
        Highlight(symbol: "bolt.fill", title: "Quit or force quit",
                  text: "A normal quit lets apps save first. Hold ⌥ to force quit, or make it the default."),
        Highlight(symbol: "checkmark.shield", title: "Confirm before quitting",
                  text: "A quick check before Quit All, and optionally before single quits and restarts."),
        Highlight(symbol: "eye", title: "Background apps",
                  text: "See the helpers and agents that never show in the Dock (⌘B)."),
        Highlight(symbol: "hand.raised", title: "Exclude apps",
                  text: "Excluded apps leave the list and are never quit. Protect music apps with one switch."),
        Highlight(symbol: "menubar.rectangle", title: "Lives in the menu bar",
                  text: "Fast and minimal. Free and open source, for macOS 14 and later."),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                PageHeader(title: "QuitX", subtitle: "A free menu bar app to quit, force quit and manage running apps") {
                    Button {
                        NSWorkspace.shared.open(URL(string: "https://github.com/kiron0/quitx")!)
                    } label: {
                        Label("Source code", systemImage: "chevron.left.forwardslash.chevron.right")
                    }
                    .glassButtonStyle()
                    .help("Open QuitX on GitHub")
                }
                VStack(alignment: .leading, spacing: 18) {
                    QuitXPromo(dismissible: false)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 250), spacing: 12)], spacing: 12) {
                        ForEach(Self.highlights) { item in
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: item.symbol)
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(QuitXPromo.amberInk)
                                    .frame(width: 32, height: 32)
                                    .background(QuitXPromo.amber.opacity(0.14), in: Page.tile)
                                    .accessibilityHidden(true)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(item.title).font(.system(size: 13, weight: .semibold))
                                    Text(item.text)
                                        .font(.system(size: 12))
                                        .foregroundStyle(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                Spacer(minLength: 0)
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                            .pageCard(padding: 14)
                            .accessibilityElement(children: .combine)
                        }
                    }
                }
                .padding(.horizontal, Page.gutter)
                .padding(.bottom, Page.gutter)
            }
            .frame(maxWidth: Page.maxWidth, alignment: .leading)
        }
    }
}
