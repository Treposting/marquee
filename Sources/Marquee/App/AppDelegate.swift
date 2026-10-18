import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var mainMenu = NSMenu()
    private let captureService = CaptureService()
    private let store = ClipboardStore()
    private lazy var monitor = ClipboardMonitor(store: store)
    private lazy var historyPanel = HistoryPanelController(store: store, monitor: monitor)
    private var recordingTimer: Timer?
    private var recordingDotVisible = true

    func applicationDidFinishLaunching(_ notification: Notification) {
        Preferences.migrateLegacySettings()
        Preferences.registerDefaults()
        setupStatusItem()
        registerHotKeys()
        observeShortcutChanges()
        monitor.start()
        let recording = RecordingController.shared
        recording.onRecordingChanged = { [weak self] active in self?.setRecordingUI(active) }
        recording.onFinished = { [weak self] url in self?.deliverRecording(url) }
        recording.onError = { [weak self] error in self?.showRecordingError(error) }
        ScrollCaptureController.shared.onFinished = { [weak self] url in self?.handleCapture(at: url) }
        Updater.shared.onStateChange = { [weak self] in self?.rebuildMenu() }
        Updater.shared.startAutomaticChecks()

        installMainMenu()
        AppModel.shared.configure(store: store, monitor: monitor) { [weak self] action in self?.perform(action) }
        AllInOneController.shared.onChoice = { [weak self] choice, screen, rect in
            self?.handleAllInOne(choice, screen: screen, rect: rect)
        }
        if !Preferences.hasCompletedOnboarding {
            WindowManager.shared.showOnboarding()
        }
    }

    /// Opening Marquee again (Finder, Spotlight, Dock) shows its window.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        WindowManager.shared.showMain()
        return true
    }

    // MARK: - Hotkeys

    private func registerHotKeys() {
        HotKeyCenter.shared.unregisterAll()
        for action in ShortcutAction.allCases {
            guard let combo = ShortcutStore.combo(for: action) else { continue }
            HotKeyCenter.shared.register(combo) { [weak self] in self?.perform(action) }
        }
    }

    private func observeShortcutChanges() {
        let center = NotificationCenter.default
        center.addObserver(forName: ShortcutStore.didChange, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                self?.registerHotKeys()
                self?.rebuildMenu()
            }
        }
        // While the user is typing a new shortcut, global hotkeys must not swallow it.
        center.addObserver(forName: ShortcutStore.recordingWillBegin, object: nil, queue: .main) { _ in
            Task { @MainActor in HotKeyCenter.shared.unregisterAll() }
        }
        center.addObserver(forName: ShortcutStore.recordingDidEnd, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.registerHotKeys() }
        }
        center.addObserver(forName: MenuBarIcon.didChange, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self, !RecordingController.shared.isRecording else { return }
                self.statusItem.button?.image = Self.idleIcon
            }
        }
    }

    private func perform(_ action: ShortcutAction) {
        switch action {
        case .allInOne: startAllInOne()
        case .pickColor: ColorPickerController.shared.pick()
        case .captureArea: capture(.area)
        case .captureWindow: capture(.window)
        case .captureFullscreen: capture(.fullscreen)
        case .captureTimed: capture(.timedFullscreen)
        case .captureText: capture(.text)
        case .captureScrolling: captureScrolling()
        case .recordArea: toggleRecording(selectArea: true)
        case .recordScreen: toggleRecording(selectArea: false)
        case .measure: MeasureController.shared.toggle()
        case .clipboardHistory: historyPanel.toggle()
        }
    }

    // MARK: - Menu bar

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = Self.idleIcon
        rebuildMenu()
    }

    private static var idleIcon: NSImage? { MenuBarIcon.current }

    /// The menu-bar menu keeps the quick actions; everything else is in the Marquee window.
    private func rebuildMenu() {
        let menu = NSMenu()
        menu.addItem(item("Open Marquee", #selector(openMainWindow)))
        menu.addItem(.separator())
        for action: ShortcutAction in [.allInOne, .captureArea, .captureWindow, .captureFullscreen, .captureScrolling] {
            menu.addItem(actionItem(action))
        }
        menu.addItem(.separator())
        menu.addItem(actionItem(.recordArea))
        menu.addItem(actionItem(.measure))
        menu.addItem(actionItem(.pickColor))
        menu.addItem(actionItem(.clipboardHistory))
        menu.addItem(.separator())
        menu.addItem(item("Settings…", #selector(openSettings), key: ","))
        menu.addItem(item("About Marquee", #selector(showAbout)))
        menu.addItem(item("Buy Me a Coffee…", #selector(buyMeACoffee)))
        if Updater.shared.isReadyToInstall {
            menu.addItem(item("Restart to Update", #selector(restartToUpdate)))
        } else {
            menu.addItem(item("Check for Updates…", #selector(checkForUpdates)))
        }
        menu.addItem(.separator())
        menu.addItem(item("Quit Marquee", #selector(quit), key: "q"))
        mainMenu = menu
        if !RecordingController.shared.isRecording {
            statusItem.menu = menu
        }
    }

    private func actionItem(_ action: ShortcutAction) -> NSMenuItem {
        let item = NSMenuItem(title: action.title, action: #selector(menuAction(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = action.rawValue
        if let combo = ShortcutStore.combo(for: action), let key = combo.menuKeyEquivalent {
            item.keyEquivalent = key
            item.keyEquivalentModifierMask = combo.eventModifierFlags
        }
        return item
    }

    private func item(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    @objc private func menuAction(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let action = ShortcutAction(rawValue: raw) else { return }
        perform(action)
    }

    @objc private func openMainWindow() {
        WindowManager.shared.showMain()
    }

    @objc private func openSettings() {
        WindowManager.shared.showMain(.settings)
    }

    @objc private func buyMeACoffee() {
        NSWorkspace.shared.open(AppInfo.buyMeACoffee)
    }

    @objc private func showAbout() {
        AppInfo.showAboutPanel()
    }

    @objc private func quit() { NSApp.terminate(nil) }
    @objc private func checkForUpdates() { Updater.shared.check(userInitiated: true) }
    @objc private func restartToUpdate() { Updater.shared.restartToUpdate() }

    // MARK: - Screenshot flow

    private func capture(_ mode: CaptureMode) {
        guard !RecordingController.shared.isBusy, !MeasureController.shared.isActive else { return }
        captureService.capture(mode) { [weak self] url in
            guard let self, let url else { return }
            if mode == .text {
                self.recognizeText(at: url)
            } else {
                self.handleCapture(at: url)
            }
        }
    }

    /// Select the part that scrolls, then scroll it; the stitched image arrives in `handleCapture`.
    private func captureScrolling() {
        guard !RecordingController.shared.isBusy, !MeasureController.shared.isActive,
              !ScrollCaptureController.shared.isActive else { return }
        AreaSelector.select(hint: "Drag over the part that scrolls  ·  Return: whole screen  ·  Esc: cancel") { selection in
            guard let (screen, rect) = selection else { return }
            ScrollCaptureController.shared.start(screen: screen, rect: rect)
        }
    }

    private func recognizeText(at url: URL) {
        TextRecognizer.recognize(imageAt: url) { text in
            try? FileManager.default.removeItem(at: url)
            guard !text.isEmpty else {
                Toast.show("No text found")
                return
            }
            let pb = NSPasteboard.general
            pb.clearContents()
            pb.setString(text, forType: .string)
            Sounds.play(.copy)
            Toast.show("Copied text (\(text.count) characters)")
        }
    }

    private func handleCapture(at url: URL) {
        guard let image = NSImage(contentsOf: url) else { return }
        deliver(Capture(url: url, image: image))
    }

    /// Applies the "after capture" preferences to a new screenshot or recording.
    private func deliver(_ capture: Capture) {
        CaptureLibrary.shared.add(capture)
        if Preferences.copyAfterCapture { capture.copyToPasteboard() }
        if Preferences.saveAfterCapture { capture.save() }
        if Preferences.showOverlay {
            QuickAccessManager.shared.show(capture)
        } else if Preferences.copyAfterCapture {
            Toast.show(capture.isVideo ? "Recording copied" : "Screenshot copied")
        }
    }

    // MARK: - All-in-One

    private func startAllInOne() {
        guard !RecordingController.shared.isBusy, !MeasureController.shared.isActive else { return }
        AllInOneController.shared.start()
    }

    private func handleAllInOne(_ choice: AllInOneController.Choice, screen: NSScreen, rect: CGRect) {
        switch choice {
        case .screenshot(.scrolling):
            ScrollCaptureController.shared.start(screen: screen, rect: rect)
        case .screenshot(.window):
            // The native window picker: click a window, Esc cancels.
            captureService.capture(.window) { [weak self] url in
                guard let url else { return }
                self?.handleCapture(at: url)
            }
        case .screenshot:
            captureService.capture(.region(rect)) { [weak self] url in
                guard let url else { return }
                self?.handleCapture(at: url)
            }
        case .copy:
            captureService.capture(.region(rect)) { url in
                guard let url, let image = NSImage(contentsOf: url) else { return }
                let capture = Capture(url: url, image: image)
                capture.copyToPasteboard()
                CaptureLibrary.shared.add(capture)
                Sounds.play(.copy)
                Toast.show("Copied to clipboard")
            }
        case .copyText:
            captureService.capture(.region(rect)) { [weak self] url in
                guard let url else { return }
                self?.recognizeText(at: url)
            }
        case .pin:
            captureService.capture(.region(rect)) { url in
                guard let url, let image = NSImage(contentsOf: url) else { return }
                PinnedImageWindow.pin(image)
            }
        case .record(.window):
            WindowPicker.pick { selection in
                guard let selection else { return }
                RecordingController.shared.prepare(screen: selection.0, rect: selection.1)
            }
        case .record:
            RecordingController.shared.prepare(screen: screen, rect: rect)
        case .pickColor:
            ColorPickerController.shared.pick()
        case .settings:
            WindowManager.shared.showMain(.settings)
        }
    }

    // MARK: - App menu

    /// A standard app menu. Besides showing while the Marquee window is open, it routes
    /// ⌘C, ⌘V, ⌘A and ⌘Z to text fields everywhere in the app.
    private func installMainMenu() {
        let main = NSMenu()

        let appMenu = NSMenu(title: "Marquee")
        appMenu.addItem(item("About Marquee", #selector(showAbout)))
        appMenu.addItem(.separator())
        appMenu.addItem(item("Settings…", #selector(openSettings), key: ","))
        appMenu.addItem(item("Check for Updates…", #selector(checkForUpdates)))
        appMenu.addItem(.separator())
        appMenu.addItem(NSMenuItem(title: "Hide Marquee", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h"))
        let hideOthers = NSMenuItem(title: "Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(hideOthers)
        appMenu.addItem(NSMenuItem(title: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: ""))
        appMenu.addItem(.separator())
        appMenu.addItem(item("Quit Marquee", #selector(quit), key: "q"))
        main.addItem(submenu(appMenu))

        let fileMenu = NSMenu(title: "File")
        fileMenu.addItem(item("Open Marquee", #selector(openMainWindow), key: "o"))
        fileMenu.addItem(NSMenuItem(title: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w"))
        main.addItem(submenu(fileMenu))

        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(NSMenuItem(title: "Undo", action: Selector(("undo:")), keyEquivalent: "z"))
        let redo = NSMenuItem(title: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(redo)
        editMenu.addItem(.separator())
        editMenu.addItem(NSMenuItem(title: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
        editMenu.addItem(NSMenuItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
        editMenu.addItem(NSMenuItem(title: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
        editMenu.addItem(NSMenuItem(title: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))
        main.addItem(submenu(editMenu))

        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(NSMenuItem(title: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m"))
        windowMenu.addItem(NSMenuItem(title: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: ""))
        windowMenu.addItem(.separator())
        windowMenu.addItem(NSMenuItem(title: "Bring All to Front", action: #selector(NSApplication.arrangeInFront(_:)), keyEquivalent: ""))
        main.addItem(submenu(windowMenu))
        NSApp.windowsMenu = windowMenu

        NSApp.mainMenu = main
    }

    private func submenu(_ menu: NSMenu) -> NSMenuItem {
        let item = NSMenuItem(title: menu.title, action: nil, keyEquivalent: "")
        item.submenu = menu
        return item
    }

    // MARK: - Recording flow

    private func toggleRecording(selectArea: Bool) {
        guard !MeasureController.shared.isActive else { return }
        RecordingController.shared.toggle(selectArea: selectArea)
    }

    @objc private func stopRecording() {
        RecordingController.shared.stop()
    }

    private func deliverRecording(_ url: URL) {
        Task {
            let poster = await VideoTools.thumbnail(for: url)
                ?? NSImage(systemSymbolName: "film", accessibilityDescription: nil)
                ?? NSImage()
            deliver(Capture(url: url, image: poster, kind: .video))
        }
    }

    /// While recording, the menu-bar item becomes a blinking red dot and the elapsed time
    /// ("12s", then "4:05", then "1:04:05"). Clicking it stops the recording.
    private func setRecordingUI(_ recording: Bool) {
        guard let button = statusItem.button else { return }
        recordingTimer?.invalidate()
        recordingTimer = nil
        if recording {
            statusItem.menu = nil
            recordingDotVisible = true
            button.image = Self.recordingDot(visible: true)
            button.imagePosition = .imageLeading
            button.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .medium)
            button.title = " " + ElapsedTime.format(0)
            button.toolTip = "Recording. Click to stop."
            button.target = self
            button.action = #selector(stopRecording)
            let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.updateRecordingTime() }
            }
            RunLoop.main.add(timer, forMode: .common)
            recordingTimer = timer
        } else {
            button.image = Self.idleIcon
            button.title = ""
            button.toolTip = nil
            button.action = nil
            button.target = nil
            statusItem.menu = mainMenu
        }
    }

    private func updateRecordingTime() {
        guard let button = statusItem.button, let start = RecordingController.shared.startDate else { return }
        recordingDotVisible.toggle()
        button.image = Self.recordingDot(visible: recordingDotVisible)
        button.title = " " + ElapsedTime.format(Date().timeIntervalSince(start))
    }

    private static func recordingDot(visible: Bool) -> NSImage {
        let image = NSImage(size: NSSize(width: 12, height: 12), flipped: false) { rect in
            NSColor.systemRed.withAlphaComponent(visible ? 1 : 0.25).setFill()
            NSBezierPath(ovalIn: rect.insetBy(dx: 1.5, dy: 1.5)).fill()
            return true
        }
        image.isTemplate = false
        return image
    }

    private func showRecordingError(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = "Couldn't start recording"
        alert.informativeText = """
        \(error.localizedDescription)

        Marquee needs the Screen Recording permission. If it's already on in System Settings, \
        use Fix Permissions on the Permissions page, then restart Marquee.
        """
        alert.addButton(withTitle: "Open Permissions")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            WindowManager.shared.showMain(.permissions)
        }
    }
}
