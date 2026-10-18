import AppKit
import SwiftUI

enum MainSection: String, CaseIterable, Identifiable {
    case home, library, clipboard, colors, permissions, settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: return "Home"
        case .library: return "Library"
        case .clipboard: return "Clipboard"
        case .colors: return "Colors"
        case .permissions: return "Permissions"
        case .settings: return "Settings"
        }
    }

    var symbol: String {
        switch self {
        case .home: return "house"
        case .library: return "photo.on.rectangle"
        case .clipboard: return "list.clipboard"
        case .colors: return "paintpalette"
        case .permissions: return "lock.shield"
        case .settings: return "gearshape"
        }
    }
}

@MainActor
final class MainNavigation: ObservableObject {
    @Published var section: MainSection? = .home
}

/// Owns the Marquee window and onboarding. Marquee shows in the Dock while either is open,
/// and goes back to being a menu-bar-only app when they close.
@MainActor
final class WindowManager: NSObject, NSWindowDelegate {
    static let shared = WindowManager()

    let navigation = MainNavigation()
    private var mainWindow: NSWindow?
    private var onboardingWindow: NSWindow?

    func showMain(_ section: MainSection? = nil) {
        if let section { navigation.section = section }
        if mainWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 1040, height: 700),
                styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                backing: .buffered, defer: false
            )
            window.title = "Marquee"
            // Each page shows its own large title; the floating glass sidebar carries the window.
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.isReleasedWhenClosed = false
            window.minSize = NSSize(width: 860, height: 560)
            window.contentViewController = NSHostingController(rootView: MainView(navigation: navigation))
            window.delegate = self
            mainWindow = window
        }
        // Each time it opens, it opens in the middle of the screen you're on.
        if mainWindow?.isVisible == false { mainWindow?.centerOnActiveScreen() }
        setDockVisible(true)
        NSApp.activate(ignoringOtherApps: true)
        mainWindow?.makeKeyAndOrderFront(nil)
    }

    /// Gets the window out of the way before a capture, recording, measurement or color pick.
    func hideMainWindow() {
        guard let mainWindow, mainWindow.isVisible else { return }
        mainWindow.orderOut(nil)
        updateDock()
    }

    func showOnboarding() {
        if onboardingWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 680, height: 600),
                styleMask: [.titled, .closable, .fullSizeContentView],
                backing: .buffered, defer: false
            )
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.isMovableByWindowBackground = true
            window.isReleasedWhenClosed = false
            window.contentViewController = NSHostingController(rootView:
                OnboardingView { [weak self] openApp in self?.finishOnboarding(openApp: openApp) }
            )
            window.delegate = self
            window.centerOnActiveScreen()
            onboardingWindow = window
        }
        setDockVisible(true)
        NSApp.activate(ignoringOtherApps: true)
        onboardingWindow?.makeKeyAndOrderFront(nil)
    }

    private func finishOnboarding(openApp: Bool) {
        Preferences.hasCompletedOnboarding = true
        onboardingWindow?.close()
        if openApp { showMain(.home) }
    }

    func windowWillClose(_ notification: Notification) {
        if (notification.object as? NSWindow) === onboardingWindow {
            Preferences.hasCompletedOnboarding = true
        }
        // The window is still visible while this runs; check once it's gone.
        runAfter(0.1) { [weak self] in self?.updateDock() }
    }

    private func updateDock() {
        let anyOpen = [mainWindow, onboardingWindow].contains { $0?.isVisible == true }
        setDockVisible(anyOpen)
    }

    private func setDockVisible(_ visible: Bool) {
        let policy: NSApplication.ActivationPolicy = visible ? .regular : .accessory
        if NSApp.activationPolicy() != policy {
            NSApp.setActivationPolicy(policy)
        }
    }
}

@MainActor
struct MainView: View {
    @ObservedObject var navigation: MainNavigation

    private let primary: [MainSection] = [.home, .library, .clipboard, .colors]
    private let secondary: [MainSection] = [.permissions, .settings]

    var body: some View {
        NavigationSplitView {
            List(selection: $navigation.section) {
                Section {
                    ForEach(primary) { section in
                        NavigationLink(value: section) {
                            Label(section.title, systemImage: section.symbol)
                        }
                    }
                }
                Section("App") {
                    ForEach(secondary) { section in
                        NavigationLink(value: section) {
                            Label(section.title, systemImage: section.symbol)
                        }
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 260)
        } detail: {
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch navigation.section ?? .home {
        case .home:
            HomeView(navigation: navigation)
        case .library:
            LibraryView()
        case .clipboard:
            if let store = AppModel.shared.store {
                ClipboardBrowserView(store: store, monitor: AppModel.shared.monitor)
            }
        case .colors:
            ColorsView()
        case .permissions:
            PermissionsPage()
        case .settings:
            SettingsView()
        }
    }
}

@MainActor
private struct PermissionsPage: View {
    @StateObject private var model = PermissionsModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                PageHeader(title: "Permissions",
                           subtitle: "Marquee asks macOS only for what each feature needs. Nothing leaves your Mac.")
                PermissionsList(model: model)
                    .padding(.horizontal, Page.gutter)
                    .padding(.bottom, Page.gutter)
            }
            .frame(maxWidth: 820, alignment: .leading)
        }
    }
}
