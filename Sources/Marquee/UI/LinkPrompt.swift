import AppKit
import SwiftUI

/// After Copy Text finds links: a small glass panel that says the text was copied and offers
/// to open each link. Return opens the first, Esc closes it, and it closes by itself when you
/// click elsewhere or leave it for a while.
@MainActor
enum LinkPrompt {
    private static var panel: KeyablePanel?
    private static var model: LinkPromptModel?
    private static var resignObserver: NSObjectProtocol?
    private static let lifetime: TimeInterval = 15

    static func show(links: [URL], characters: Int) {
        close(animated: false)
        let model = LinkPromptModel(links: links, characters: characters)
        let host = NSHostingView(rootView: LinkPromptView(model: model))
        // Measure first: with sizingOptions emptied, a borderless panel would be zero-sized.
        let size = host.fittingSize
        host.sizingOptions = []

        let p = KeyablePanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false
        )
        p.isReleasedWhenClosed = false
        p.level = .statusBar
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.contentView = host

        // Where the toasts appear: low and centered on the display you're using.
        let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }
            ?? NSScreen.main
        if let frame = screen?.visibleFrame {
            p.setFrameOrigin(NSPoint(x: frame.midX - size.width / 2, y: frame.minY + 64))
        }
        // Takes the keyboard without bringing Marquee forward, so Return and Esc work.
        p.makeKeyAndOrderFront(nil)
        panel = p
        Self.model = model

        resignObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification, object: p, queue: .main
        ) { _ in
            Task { @MainActor in close() }
        }

        let title = links.count == 1 ? "Text copied. Found a link: \(LinkFinder.displayText(links[0]))"
            : "Text copied. Found \(links.count) links."
        NSAccessibility.post(
            element: NSApp as Any,
            notification: .announcementRequested,
            userInfo: [.announcement: title, .priority: NSAccessibilityPriorityLevel.high.rawValue]
        )
        scheduleTimeout(for: model)
    }

    /// Closes after `lifetime`, but not while the pointer rests on it.
    private static func scheduleTimeout(for model: LinkPromptModel) {
        runAfter(lifetime) {
            guard Self.model === model else { return }
            if model.hovering { scheduleTimeout(for: model) } else { close() }
        }
    }

    static func open(_ url: URL) {
        NSWorkspace.shared.open(url)
        close()
    }

    static func close(animated: Bool = true) {
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
        resignObserver = nil
        guard let p = panel, let model else { return }
        panel = nil
        Self.model = nil
        guard animated else {
            p.orderOut(nil)
            return
        }
        model.leaving = true
        runAfter(0.2) { p.orderOut(nil) }
    }
}

@MainActor
final class LinkPromptModel: ObservableObject {
    let links: [URL]
    let characters: Int
    @Published var leaving = false
    var hovering = false

    init(links: [URL], characters: Int) {
        self.links = links
        self.characters = characters
    }
}

private struct LinkPromptView: View {
    @ObservedObject var model: LinkPromptModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    private var visible: Bool { appeared && !model.leaving }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            if model.links.count == 1, let url = model.links.first {
                single(url)
            } else {
                list
            }
        }
        .padding(18)
        .frame(width: 380, alignment: .leading)
        .glassSurface(RoundedRectangle(cornerRadius: 24, style: .continuous))
        // Room for the glass's shadow and the entrance movement.
        .padding(24)
        .opacity(visible ? 1 : 0)
        .scaleEffect(visible || reduceMotion ? 1 : 0.94, anchor: .bottom)
        .offset(y: visible || reduceMotion ? 0 : 12)
        .onHover { model.hovering = $0 }
        .onAppear {
            withAnimation(reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.38, dampingFraction: 0.82)) {
                appeared = true
            }
        }
        .animation(reduceMotion ? .easeIn(duration: 0.12) : .easeIn(duration: 0.18), value: model.leaving)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "link")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(Circle().fill(Color.accentColor.gradient))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(model.links.count == 1 ? "Open this link?" : "Open a link?")
                    .font(.headline)
                Text("Text copied (\(model.characters) characters)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Button {
                LinkPrompt.close()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 24)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help("Close (Esc)")
            .accessibilityLabel("Close")
        }
    }

    private func single(_ url: URL) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(LinkFinder.displayText(url))
                .font(.system(.callout, design: .rounded).weight(.medium))
                .lineLimit(2)
                .truncationMode(.middle)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.primary.opacity(0.06)))
            HStack(spacing: 10) {
                Spacer()
                Button("Close") { LinkPrompt.close() }
                    .keyboardShortcut(.cancelAction)
                    .glassButtonStyle()
                    .controlSize(.large)
                Button(url.scheme?.lowercased() == "mailto" ? "New Email" : "Open Link") { LinkPrompt.open(url) }
                    .keyboardShortcut(.defaultAction)
                    .glassButtonStyle(prominent: true)
                    .controlSize(.large)
            }
        }
    }

    private var list: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(model.links.enumerated().map { LinkRow(index: $0.offset, url: $0.element) }) { row in
                let index = row.index, url = row.url
                HStack(spacing: 10) {
                    Image(systemName: url.scheme?.lowercased() == "mailto" ? "envelope" : "globe")
                        .foregroundStyle(.secondary)
                        .frame(width: 18)
                        .accessibilityHidden(true)
                    Text(LinkFinder.displayText(url))
                        .font(.system(.callout, design: .rounded).weight(.medium))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button("Open") { LinkPrompt.open(url) }
                        .glassButtonStyle(prominent: index == 0)
                        .modifier(DefaultActionIf(index == 0))
                        .accessibilityLabel("Open \(LinkFinder.displayText(url))")
                }
                .padding(.leading, 10)
                .padding(.trailing, 6)
                .padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.primary.opacity(0.06)))
            }
            HStack {
                Spacer()
                Button("Close") { LinkPrompt.close() }
                    .keyboardShortcut(.cancelAction)
                    .glassButtonStyle()
            }
            .padding(.top, 4)
        }
    }
}

/// One link in the list; a small struct rather than a tuple key path for ForEach.
private struct LinkRow: Identifiable {
    let index: Int
    let url: URL
    var id: String { url.absoluteString }
}

/// Return opens the first link in the list.
private struct DefaultActionIf: ViewModifier {
    let enabled: Bool
    init(_ enabled: Bool) { self.enabled = enabled }

    func body(content: Content) -> some View {
        if enabled { content.keyboardShortcut(.defaultAction) } else { content }
    }
}
