import AppKit
import Combine
import SwiftUI

/// Borderless panel that can take keyboard focus without activating Marquee,
/// so the app you were typing in stays frontmost and receives the paste.
final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class HistoryViewModel: ObservableObject {
    @Published var query = "" { didSet { selection = 0 } }
    @Published var filter: ClipFilter = .all { didSet { selection = 0 } }
    @Published var selection = 0
    @Published var focusToken = UUID()
    /// A category being made or edited inline; panel shortcuts pause while it's open.
    @Published var draft: CategoryDraft?

    let store: ClipboardStore
    private var cancellable: AnyCancellable?

    init(store: ClipboardStore) {
        self.store = store
        cancellable = store.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }
    }

    var visibleItems: [ClipItem] {
        if case .category(let id) = filter, !store.categories.contains(where: { $0.id == id }) {
            return store.items(matching: .all, query: query)
        }
        return store.items(matching: filter, query: query)
    }

    var selectedItem: ClipItem? {
        let items = visibleItems
        return items.indices.contains(selection) ? items[selection] : nil
    }

    func move(by delta: Int) {
        let count = visibleItems.count
        guard count > 0 else { return }
        selection = min(max(0, selection + delta), count - 1)
    }

    /// Fresh search each time the panel opens; a chosen category stays chosen.
    func reset() {
        query = ""
        if case .category(let id) = filter, store.categories.contains(where: { $0.id == id }) {
            // keep it
        } else {
            filter = .all
        }
        selection = 0
        draft = nil
        focusToken = UUID()
    }
}

@MainActor
final class HistoryPanelController: NSObject, NSWindowDelegate {
    private let store: ClipboardStore
    private let monitor: ClipboardMonitor
    private let model: HistoryViewModel
    private let thumbnails = ThumbnailCache()
    private var panel: KeyablePanel!
    private var keyMonitor: Any?
    private var scrollMonitor: Any?
    private var outsideClickMonitor: Any?

    private let panelHeight: CGFloat = 330

    init(store: ClipboardStore, monitor: ClipboardMonitor) {
        self.store = store
        self.monitor = monitor
        self.model = HistoryViewModel(store: store)
        super.init()
        buildPanel()
    }

    private func buildPanel() {
        let panel = KeyablePanel(
            contentRect: NSRect(x: 0, y: 0, width: 1000, height: panelHeight),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false
        )
        panel.isReleasedWhenClosed = false
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        // Set explicitly so the see-through glass still catches clicks and scrolls; otherwise
        // they fall through to the window underneath (a browser then swipes back or forward).
        panel.ignoresMouseEvents = false
        panel.becomesKeyOnlyIfNeeded = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.delegate = self
        panel.contentView = NSHostingView(rootView: HistoryView(
            model: model,
            thumbnails: thumbnails,
            onPaste: { [weak self] item in self?.paste(item) },
            onTogglePin: { [weak self] item in self?.store.togglePin(item) },
            onDelete: { [weak self] item in self?.store.remove(item) }
        ))
        self.panel = panel
    }

    var isVisible: Bool { panel.isVisible }

    func toggle() {
        isVisible ? hide() : show()
    }

    func show() {
        let mouse = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }) ?? NSScreen.main
        else { return }
        // Attached to the bottom edge of the screen (over the Dock), so only its top corners
        // are rounded. Sideways it stays clear of a Dock on the left or right.
        let visible = screen.visibleFrame
        panel.setFrame(NSRect(x: visible.minX, y: screen.frame.minY, width: visible.width, height: panelHeight),
                       display: true)
        model.reset()
        panel.makeKeyAndOrderFront(nil)
        installKeyMonitor()
        installMouseMonitors()
    }

    /// The panel closes on Esc, after pasting, or on a click outside it. Losing focus alone
    /// (switching apps, a notification) leaves it open; click it to type in it again.
    func hide() {
        panel.orderOut(nil)
        for monitor in [keyMonitor, scrollMonitor, outsideClickMonitor].compactMap({ $0 }) {
            NSEvent.removeMonitor(monitor)
        }
        keyMonitor = nil
        scrollMonitor = nil
        outsideClickMonitor = nil
    }

    /// Pastes straight into the app you were using and closes the panel. Pasting copies it
    /// too, so the item moves to the top of history.
    private func paste(_ item: ClipItem) {
        store.writeToPasteboard(item)
        monitor.ignoreCurrentContents()
        store.touch(item)
        hide()
        if Preferences.autoPaste && Paster.isTrusted {
            Sounds.play(.paste)
            Paster.pasteIntoFrontApp()
        } else {
            Sounds.play(.copy)
            if Preferences.autoPaste { Paster.pasteIntoFrontApp() }
        }
    }

    // MARK: - Mouse

    private func installMouseMonitors() {
        if outsideClickMonitor == nil {
            // Clicks in other apps arrive here; clicks in the panel don't.
            outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(
                matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
            ) { [weak self] _ in
                Task { @MainActor in
                    guard let self, self.panel.isVisible,
                          !NSMouseInRect(NSEvent.mouseLocation, self.panel.frame, false) else { return }
                    self.hide()
                }
            }
        }
        if scrollMonitor == nil {
            // Cards scroll sideways, so an up/down scroll (mouse wheel, Magic Mouse) moves them too.
            scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                guard let self, event.window === self.panel,
                      abs(event.scrollingDeltaY) > abs(event.scrollingDeltaX) else { return event }
                return Self.sideways(event) ?? event
            }
        }
    }

    /// The same scroll event with its vertical movement turned into horizontal movement.
    private static func sideways(_ event: NSEvent) -> NSEvent? {
        guard let cg = event.cgEvent?.copy() else { return nil }
        let integerAxes: [(CGEventField, CGEventField)] = [
            (.scrollWheelEventDeltaAxis1, .scrollWheelEventDeltaAxis2),
            (.scrollWheelEventPointDeltaAxis1, .scrollWheelEventPointDeltaAxis2),
        ]
        for (vertical, horizontal) in integerAxes {
            cg.setIntegerValueField(horizontal, value: cg.getIntegerValueField(vertical))
            cg.setIntegerValueField(vertical, value: 0)
        }
        cg.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2,
                               value: cg.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1))
        cg.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1, value: 0)
        return NSEvent(cgEvent: cg)
    }

    // MARK: - Keyboard

    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.panel.isKeyWindow else { return event }
            return self.handle(event) ? nil : event
        }
    }

    /// Returns true when the event was consumed.
    private func handle(_ event: NSEvent) -> Bool {
        let command = event.modifierFlags.contains(.command)
        // While naming a category, keys belong to the editor; Esc closes it.
        if model.draft != nil {
            if event.keyCode == 53 {
                model.draft = nil
                return true
            }
            return false
        }
        switch event.keyCode {
        case 53: // Esc
            hide()
            return true
        case 36, 76: // Return, Enter
            if let item = model.selectedItem { paste(item) }
            return true
        case 123: // ←
            model.move(by: -1)
            return true
        case 124: // →
            model.move(by: 1)
            return true
        case 51 where command: // ⌘⌫
            if let item = model.selectedItem { store.remove(item) }
            return true
        default:
            break
        }

        guard command, let chars = event.charactersIgnoringModifiers?.lowercased() else { return false }
        if let n = Int(chars), (1...9).contains(n) {
            let items = model.visibleItems
            if items.indices.contains(n - 1) { paste(items[n - 1]) }
            return true
        }
        if chars == "p", let item = model.selectedItem {
            store.togglePin(item)
            return true
        }
        return false
    }
}

@MainActor
final class ThumbnailCache {
    private let images = NSCache<NSString, NSImage>()
    private let icons = NSCache<NSString, NSImage>()
    /// Main color of each source app's icon; `nil` entries mean no usable color.
    private var appColors: [String: PickedColor?] = [:]

    func thumbnail(for url: URL) -> NSImage? {
        let key = url.path as NSString
        if let cached = images.object(forKey: key) { return cached }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: 480,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        let image = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
        images.setObject(image, forKey: key)
        return image
    }

    func appIcon(bundleID: String?) -> NSImage? {
        guard let bundleID else { return nil }
        if let cached = icons.object(forKey: bundleID as NSString) { return cached }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        icons.setObject(icon, forKey: bundleID as NSString)
        return icon
    }

    /// The source app's icon color, used to tint its clipboard cards.
    func appColor(bundleID: String?) -> PickedColor? {
        guard let bundleID else { return nil }
        if let cached = appColors[bundleID] { return cached }
        let color = appIcon(bundleID: bundleID).flatMap(IconColor.dominant(in:))
        appColors[bundleID] = color
        return color
    }

    func fileIcon(path: String) -> NSImage {
        NSWorkspace.shared.icon(forFile: path)
    }
}
