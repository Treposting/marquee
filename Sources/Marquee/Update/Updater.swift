import AppKit
import SwiftUI

/// What GitHub's "latest release" API returns (the fields Marquee uses).
struct ReleaseInfo: Decodable {
    struct Asset: Decodable {
        let name: String
        let browserDownloadUrl: URL
        let size: Int
    }

    let tagName: String
    let name: String?
    let body: String?
    let htmlUrl: URL
    let assets: [Asset]
}

/// Checks GitHub Releases for a newer Marquee, downloads it, and installs it on restart.
@MainActor
final class Updater: ObservableObject {
    static let shared = Updater()
    static let repository = "Treposting/marquee"

    enum State: Equatable {
        case idle
        case checking
        case upToDate
        case available
        case downloading(Double)
        case readyToInstall
        case failed(String)
    }

    @Published private(set) var state: State = .idle {
        didSet { onStateChange?() }
    }
    @Published private(set) var release: ReleaseInfo?
    private(set) var latestVersion: AppVersion?
    private var stagedApp: URL?
    private var window: NSWindow?
    private var timer: Timer?

    /// Lets the menu switch between "Check for Updates…" and "Restart to Update".
    var onStateChange: (() -> Void)?

    var currentVersion: String { AppVersion.current?.description ?? "?" }
    var isReadyToInstall: Bool { state == .readyToInstall }
    /// A newer version is waiting: the menu bar icon shows a red dot and the menu offers it.
    var hasUpdate: Bool { state == .available || state == .readyToInstall }

    /// How often to look for a new release. GitHub answers "not modified" cheaply (ETag), so
    /// checking hourly costs almost nothing and new versions show up the same day.
    private static let checkInterval: TimeInterval = 60 * 60
    private var wakeObserver: NSObjectProtocol?

    // MARK: - Checking

    func startAutomaticChecks() {
        guard timer == nil else { return }
        runAfter(20) { [weak self] in
            guard Preferences.autoCheckUpdates else { return }
            self?.check(userInitiated: false)
        }
        let timer = Timer(timeInterval: Self.checkInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard Preferences.autoCheckUpdates else { return }
                self?.check(userInitiated: false)
            }
        }
        timer.tolerance = 5 * 60
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        // A Mac that slept through the hourly check looks again shortly after it wakes.
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                runAfter(30) {
                    guard Preferences.autoCheckUpdates else { return }
                    self?.check(userInitiated: false)
                }
            }
        }
    }

    func check(userInitiated: Bool) {
        switch state {
        case .checking, .downloading:
            if userInitiated { showWindow() }
            return
        case .readyToInstall:
            showWindow()
            return
        default:
            break
        }
        state = .checking
        if userInitiated { showWindow() }

        Task {
            do {
                let info = try await fetchLatestRelease()
                guard let latest = AppVersion(info.tagName), let current = AppVersion.current else {
                    throw UpdateError.badResponse
                }
                release = info
                latestVersion = latest
                if latest > current {
                    if !userInitiated && Preferences.skippedVersion == latest.description {
                        state = .idle
                        return
                    }
                    state = .available
                    if userInitiated {
                        showWindow()
                    } else {
                        // Found in the background: a red dot and a notification, not a window
                        // popping up in the middle of your work.
                        UpdateNotifier.announce(version: latest.description)
                    }
                } else {
                    state = .upToDate
                }
            } catch {
                state = .failed(error.localizedDescription)
            }
        }
    }

    private static let etagKey = "updateReleaseETag"
    private static let cachedReleaseKey = "updateReleaseCache"

    private func fetchLatestRelease() async throws -> ReleaseInfo {
        guard let url = URL(string: "https://api.github.com/repos/\(Self.repository)/releases/latest") else {
            throw UpdateError.badResponse
        }
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Marquee/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 20
        // With the last answer's ETag, GitHub replies 304 when nothing changed. Those replies
        // don't count against its rate limit, which keeps hourly checks free.
        let defaults = UserDefaults.standard
        let cached = defaults.data(forKey: Self.cachedReleaseKey)
        if cached != nil, let etag = defaults.string(forKey: Self.etagKey) {
            request.setValue(etag, forHTTPHeaderField: "If-None-Match")
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        let http = response as? HTTPURLResponse
        let body: Data
        switch http?.statusCode {
        case 200:
            body = data
            defaults.set(data, forKey: Self.cachedReleaseKey)
            defaults.set(http?.value(forHTTPHeaderField: "ETag"), forKey: Self.etagKey)
        case 304:
            guard let cached else { throw UpdateError.badResponse }
            body = cached
        default:
            throw UpdateError.badResponse
        }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(ReleaseInfo.self, from: body)
    }

    // MARK: - Installing

    func install() {
        guard let release else { return }
        guard let asset = release.assets.first(where: { $0.name.hasPrefix("Marquee") && $0.name.hasSuffix(".zip") }) else {
            state = .failed(UpdateError.noDownload.localizedDescription)
            return
        }
        state = .downloading(0)
        let expected = latestVersion
        Task {
            do {
                let zip = try await UpdateDownloader.download(asset.browserDownloadUrl) { fraction in
                    Task { @MainActor in
                        if case .downloading = Updater.shared.state {
                            Updater.shared.state = .downloading(fraction)
                        }
                    }
                }
                stagedApp = try await UpdateInstaller.stage(zip: zip, expectedVersion: expected)
                state = .readyToInstall
            } catch {
                state = .failed(error.localizedDescription)
            }
        }
    }

    func restartToUpdate() {
        guard let stagedApp else { return }
        do {
            try UpdateInstaller.replaceAndRelaunch(with: stagedApp)
            NSApp.terminate(nil)
        } catch {
            state = .failed(error.localizedDescription)
            showWindow()
        }
    }

    func skipThisVersion() {
        Preferences.skippedVersion = latestVersion?.description
        state = .idle
        window?.close()
    }

    func later() {
        if state != .readyToInstall { state = .idle }
        window?.close()
    }

    func openReleasePage() {
        let page = release?.htmlUrl ?? URL(string: "https://github.com/\(Self.repository)/releases/latest")
        if let page { NSWorkspace.shared.open(page) }
    }

    // MARK: - Window

    func showWindow() {
        if window == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 480, height: 360),
                styleMask: [.titled, .closable, .fullSizeContentView],
                backing: .buffered, defer: false
            )
            window.title = "Software Update"
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.isMovableByWindowBackground = true
            window.isReleasedWhenClosed = false
            window.contentViewController = NSHostingController(rootView: UpdateView(updater: self))
            self.window = window
        }
        if window?.isVisible == false { window?.centerOnActiveScreen() }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func closeWindow() {
        window?.close()
    }
}

@MainActor
struct UpdateView: View {
    @ObservedObject var updater: Updater

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 14) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 64, height: 64)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 20, weight: .bold))
                        .accessibilityAddTraits(.isHeader)
                    Text(subtitle)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            content

            GlassGroup(spacing: 8) {
                HStack(spacing: 8) {
                    leadingButtons
                    Spacer()
                    trailingButtons
                }
            }
            .controlSize(.large)
        }
        .padding(.horizontal, 24)
        .padding(.top, 34)
        .padding(.bottom, 22)
        .frame(width: 500)
    }

    private var title: String {
        switch updater.state {
        case .idle, .checking: return "Checking for updates…"
        case .upToDate: return "You're up to date"
        case .available: return "Marquee \(updater.latestVersion?.description ?? "") is available"
        case .downloading: return "Downloading Marquee \(updater.latestVersion?.description ?? "")…"
        case .readyToInstall: return "Ready to install"
        case .failed: return "Couldn't update"
        }
    }

    private var subtitle: String {
        switch updater.state {
        case .upToDate: return "Marquee \(updater.currentVersion) is the latest version."
        case .readyToInstall: return "Restart Marquee to finish installing \(updater.latestVersion?.description ?? "the update")."
        case .failed(let message): return message
        default: return "You have version \(updater.currentVersion)."
        }
    }

    @ViewBuilder
    private var content: some View {
        switch updater.state {
        case .checking, .idle:
            ProgressView().controlSize(.small)
        case .available:
            ScrollView {
                Text(notes)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding(10)
            }
            .frame(height: 170)
            .background(Color.primary.opacity(0.04), in: Page.tile)
            .overlay(Page.tile.strokeBorder(Color.primary.opacity(0.08)))
        case .downloading(let fraction):
            ProgressView(value: fraction)
        default:
            EmptyView()
        }
    }

    private var notes: AttributedString {
        let body = updater.release?.body ?? "No release notes."
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: body, options: options)) ?? AttributedString(body)
    }

    @ViewBuilder
    private var leadingButtons: some View {
        switch updater.state {
        case .available:
            Button("Skip This Version") { updater.skipThisVersion() }.glassButtonStyle()
        case .failed:
            Button("Open Releases Page") { updater.openReleasePage() }.glassButtonStyle()
        default:
            EmptyView()
        }
    }

    @ViewBuilder
    private var trailingButtons: some View {
        switch updater.state {
        case .available:
            Button("Later") { updater.later() }.glassButtonStyle()
            Button("Install Update") { updater.install() }
                .keyboardShortcut(.defaultAction)
                .glassButtonStyle(prominent: true)
        case .readyToInstall:
            Button("Later") { updater.later() }.glassButtonStyle()
            Button("Restart to Update") { updater.restartToUpdate() }
                .keyboardShortcut(.defaultAction)
                .glassButtonStyle(prominent: true)
        case .failed:
            Button("Close") { updater.later() }.glassButtonStyle()
            Button("Try Again") { updater.check(userInitiated: true) }
                .keyboardShortcut(.defaultAction)
                .glassButtonStyle(prominent: true)
        case .upToDate:
            Button("OK") { updater.later() }
                .keyboardShortcut(.defaultAction)
                .glassButtonStyle(prominent: true)
        default:
            Button("Close") { updater.closeWindow() }.glassButtonStyle()
        }
    }
}
