import AppKit
import SwiftUI

extension ShortcutAction {
    var symbol: String {
        switch self {
        case .allInOne: return "square.grid.2x2"
        case .captureArea: return "rectangle.dashed"
        case .captureWindow: return "macwindow"
        case .captureFullscreen: return "display"
        case .captureTimed: return "timer"
        case .captureText: return "text.viewfinder"
        case .captureScrolling: return "scroll"
        case .recordArea: return "record.circle"
        case .recordScreen: return "video.circle"
        case .measure: return "ruler"
        case .pickColor: return "eyedropper"
        case .clipboardHistory: return "list.clipboard"
        }
    }

    var subtitle: String {
        switch self {
        case .allInOne: return "Select an area, then choose what to do"
        case .captureArea: return "Drag over any part of the screen"
        case .captureWindow: return "Click a window to capture it"
        case .captureFullscreen: return "The display under the pointer"
        case .captureTimed: return "Full screen after 5 seconds"
        case .captureText: return "Select text anywhere and copy it"
        case .captureScrolling: return "One long screenshot as you scroll"
        case .recordArea: return "Video of an area, with audio"
        case .recordScreen: return "Video of the whole display"
        case .measure: return "Distances and sizes on screen"
        case .pickColor: return "Copy any color on screen"
        case .clipboardHistory: return "Everything you've copied"
        }
    }

    /// Short name for tiles ("Area" rather than "Capture Area").
    var tileTitle: String {
        switch self {
        case .allInOne: return "All-in-One"
        case .captureArea: return "Area"
        case .captureWindow: return "Window"
        case .captureFullscreen: return "Full Screen"
        case .captureTimed: return "Self-Timer"
        case .captureText: return "Copy Text"
        case .captureScrolling: return "Scrolling"
        case .recordArea: return "Record Area"
        case .recordScreen: return "Record Screen"
        case .measure: return "Measure"
        case .pickColor: return "Color Picker"
        case .clipboardHistory: return "Clipboard"
        }
    }

    var isRecording: Bool { self == .recordArea || self == .recordScreen }
}

/// The first page of the Marquee window: All-in-One up front, the latest capture next to it,
/// every other action in compact rows, then recent captures.
@MainActor
struct HomeView: View {
    @ObservedObject var navigation: MainNavigation
    @ObservedObject var library = CaptureLibrary.shared
    @StateObject private var permissions = PermissionsModel()
    @State private var shortcutsVersion = 0

    private struct ActionGroup: Identifiable {
        let title: String
        let actions: [ShortcutAction]
        var id: String { title }
    }

    private let groups: [ActionGroup] = [
        ActionGroup(title: "Capture", actions: [.captureArea, .captureWindow, .captureFullscreen, .captureScrolling, .captureTimed, .captureText]),
        ActionGroup(title: "Record", actions: [.recordArea, .recordScreen]),
        ActionGroup(title: "Tools", actions: [.measure, .pickColor, .clipboardHistory]),
    ]

    var body: some View {
        ScrollView {
            PageHeader(title: "Marquee",
                       subtitle: "Capture, record, measure, and keep everything you copy.",
                       icon: NSApp.applicationIconImage) {
                Button {
                    navigation.section = .settings
                } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 14, weight: .medium))
                        .frame(width: 32, height: 32)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .glassSurface(Circle(), interactive: true)
                .help("Settings")
                .accessibilityLabel("Settings")
            }
            .frame(maxWidth: Page.maxWidth, alignment: .leading)

            VStack(alignment: .leading, spacing: 28) {
                if !permissions.screenRecording {
                    PermissionBanner { navigation.section = .permissions }
                }

                HStack(alignment: .top, spacing: 14) {
                    AllInOneCard(version: shortcutsVersion)
                    LatestCaptureCard(item: library.items.first, revision: library.revision) {
                        navigation.section = .library
                    }
                    .frame(width: 236)
                }
                .fixedSize(horizontal: false, vertical: true)

                ForEach(groups) { group in
                    VStack(alignment: .leading, spacing: 10) {
                        SectionTitle(group.title)
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 230), spacing: 10)], spacing: 10) {
                            ForEach(group.actions) { action in
                                ActionRow(action: action, version: shortcutsVersion)
                            }
                        }
                    }
                }

                recent

                AboutFooter()
                    .padding(.top, 4)
            }
            .padding(.horizontal, Page.gutter)
            .padding(.bottom, Page.gutter)
            .frame(maxWidth: Page.maxWidth, alignment: .leading)
        }
        .onReceive(NotificationCenter.default.publisher(for: ShortcutStore.didChange)) { _ in
            shortcutsVersion += 1
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            permissions.refresh()
        }
    }

    @ViewBuilder
    private var recent: some View {
        let items = Array(library.items.dropFirst().prefix(8))
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    SectionTitle("Earlier captures")
                    Spacer()
                    Button("Show All") { navigation.section = .library }
                        .glassButtonStyle()
                        .controlSize(.small)
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(items) { item in
                            LibraryThumbnail(item: item, revision: library.revision)
                                .frame(width: 150, height: 94)
                                .background(Color.primary.opacity(0.04))
                                .clipShape(Page.tile)
                                .overlay(Page.tile.strokeBorder(Color.primary.opacity(0.08)))
                                .onTapGesture(count: 2) { library.open(item) }
                                .contextMenu { LibraryItemMenu(item: item) }
                                .help(item.date.formatted(date: .abbreviated, time: .shortened))
                                .accessibilityLabel(item.isVideo ? "Recording" : "Screenshot")
                                .accessibilityValue(item.date.formatted(date: .abbreviated, time: .shortened))
                        }
                    }
                }
            }
        }
    }
}

private struct SectionTitle: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .pageSectionTitle()
            .accessibilityAddTraits(.isHeader)
    }
}

/// The one primary action on Home: All-in-One reaches every capture.
@MainActor
private struct AllInOneCard: View {
    let version: Int
    private let shape = Page.card

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: ShortcutAction.allInOne.symbol)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 42, height: 42)
                    .background(Color.accentColor.gradient, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("All-in-One")
                        .font(.system(size: 17, weight: .semibold))
                    Text("Select an area, then screenshot, record, copy, pin or read its text.")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
            HStack(spacing: 12) {
                Button {
                    AppModel.shared.perform(.allInOne)
                } label: {
                    Label("Start All-in-One", systemImage: "viewfinder")
                        .padding(.horizontal, 4)
                }
                .glassButtonStyle(prominent: true)
                .controlSize(.large)
                if let combo = ShortcutStore.combo(for: .allInOne) {
                    KeyCaps(combo: combo)
                    Text("from anywhere")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }
            .id(version)
        }
        .padding(18)
        .frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
        .background(
            LinearGradient(colors: [Color.accentColor.opacity(0.16), Color.accentColor.opacity(0.05)],
                           startPoint: .topLeading, endPoint: .bottomTrailing),
            in: shape
        )
        .overlay(shape.strokeBorder(Color.accentColor.opacity(0.25)))
        .accessibilityElement(children: .contain)
    }
}

/// The newest capture, so the last thing you took is one click away.
@MainActor
private struct LatestCaptureCard: View {
    let item: LibraryItem?
    let revision: Int
    let showLibrary: @MainActor () -> Void
    private let shape = Page.card

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Latest capture")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                if let item {
                    Text(item.date.formatted(.relative(presentation: .named)))
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
            }
            if let item {
                LibraryThumbnail(item: item, revision: revision)
                    .frame(maxWidth: .infinity)
                    .frame(height: 96)
                    .background(Color.primary.opacity(0.04))
                    .clipShape(Page.tile)
                    .onTapGesture(count: 2) { CaptureLibrary.shared.open(item) }
                    .contextMenu { LibraryItemMenu(item: item) }
                    .accessibilityLabel(item.isVideo ? "Latest recording" : "Latest screenshot")
                HStack(spacing: 6) {
                    Button("Copy") { CaptureLibrary.shared.copy(item) }
                    Button("Open") { CaptureLibrary.shared.open(item) }
                    Spacer(minLength: 0)
                    Button("Library", action: showLibrary)
                        .buttonStyle(.link)
                }
                .controlSize(.small)
            } else {
                Spacer(minLength: 0)
                VStack(spacing: 6) {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 24, weight: .light))
                        .foregroundStyle(.tertiary)
                    Text("Your captures show up here")
                        .font(.system(size: 12, weight: .medium))
                    Text("Take a screenshot or recording to start.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                Spacer(minLength: 0)
            }
        }
        .padding(14)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Color.primary.opacity(0.035), in: shape)
        .overlay(shape.strokeBorder(Color.primary.opacity(0.08)))
    }
}

/// A compact row for one action: icon, name, what it does, and its shortcut if it has one.
private struct ActionRow: View {
    let action: ShortcutAction
    let version: Int

    var body: some View {
        Button {
            AppModel.shared.perform(action)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: action.symbol)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(action.isRecording ? Color.red : Color.accentColor)
                    .frame(width: 34, height: 34)
                    .background((action.isRecording ? Color.red : Color.accentColor).opacity(0.12),
                                in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                VStack(alignment: .leading, spacing: 1) {
                    Text(action.tileTitle)
                        .font(.system(size: 13, weight: .semibold))
                    Text(action.subtitle)
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 6)
                if let combo = ShortcutStore.combo(for: action) {
                    KeyCaps(combo: combo)
                }
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
        }
        .buttonStyle(TileButtonStyle())
        .help(action.subtitle)
        .accessibilityLabel(action.title)
        .accessibilityHint(action.subtitle)
        .id(version)
    }
}

/// Hover and pressed states for Home tiles. The press scale is skipped with Reduce Motion.
private struct TileButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovering = false

    func makeBody(configuration: Configuration) -> some View {
        let shape = Page.tile
        let fill = configuration.isPressed ? 0.11 : (hovering ? 0.07 : 0.035)
        configuration.label
            .contentShape(shape)
            .background(Color.primary.opacity(fill), in: shape)
            .overlay(shape.strokeBorder(Color.primary.opacity(hovering ? 0.14 : 0.07)))
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
            .onHover { hovering = $0 }
            .animation(.easeOut(duration: 0.15), value: hovering)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

/// A shortcut drawn as separate keys, e.g. ⌥ ⇧ ⌘ A.
struct KeyCaps: View {
    let combo: KeyCombo

    private struct Cap: Identifiable {
        let id: Int
        let label: String
    }

    private var caps: [Cap] {
        let text = combo.displayString
        let modifiers = text.prefix { "⌃⌥⇧⌘".contains($0) }
        let key = String(text.dropFirst(modifiers.count))
        let labels = modifiers.map(String.init) + (key.isEmpty ? [] : [key])
        return labels.enumerated().map { Cap(id: $0.offset, label: $0.element) }
    }

    var body: some View {
        HStack(spacing: 3) {
            ForEach(caps) { cap in
                Text(cap.label)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 18, minHeight: 18)
                    .padding(.horizontal, cap.label.count > 1 ? 4 : 0)
                    .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.1)))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Shortcut \(combo.displayString)")
    }
}

private struct PermissionBanner: View {
    let fix: @MainActor () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 18))
                .foregroundStyle(.orange)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("Screen Recording isn't allowed yet").font(.system(size: 13, weight: .semibold))
                Text("Screenshots of other apps, recordings and Measure need it. Already on in System Settings? Fix Permissions on the next page clears old entries.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Button("Fix…", action: fix).glassButtonStyle(prominent: true)
        }
        .pageCard(tint: .orange, padding: 16)
    }
}
