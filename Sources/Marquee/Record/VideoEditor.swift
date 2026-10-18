import AppKit
import AVFoundation
import AVKit
import SwiftUI

/// Exports a recording: optionally trimmed, without sound, or smaller.
enum VideoExport {
    enum Size: String, CaseIterable, Identifiable {
        case original, hd1080, hd720
        var id: String { rawValue }

        var title: String {
            switch self {
            case .original: return "Original Size"
            case .hd1080: return "1080p"
            case .hd720: return "720p"
            }
        }

        var preset: String {
            switch self {
            // Keeps the recorded H.264 and AAC as they are: fast, no quality loss.
            case .original: return AVAssetExportPresetPassthrough
            case .hd1080: return AVAssetExportPreset1920x1080
            case .hd720: return AVAssetExportPreset1280x720
            }
        }
    }

    enum ExportError: LocalizedError {
        case noVideo, cannotExport, failed
        var errorDescription: String? {
            switch self {
            case .noVideo: return "This recording has no video track."
            case .cannotExport: return "This recording can't be exported in that format."
            case .failed: return "The export didn't finish."
            }
        }
    }

    /// Writes `range` of `source` to `destination` as MP4.
    static func export(_ source: URL, range: CMTimeRange?, size: Size, muted: Bool, to destination: URL) async throws {
        let asset = AVURLAsset(url: source)
        let duration = try await asset.load(.duration)
        let range = range ?? CMTimeRange(start: .zero, duration: duration)
        let composition = AVMutableComposition()

        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        guard !videoTracks.isEmpty else { throw ExportError.noVideo }
        for track in videoTracks {
            guard let copy = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)
            else { continue }
            try copy.insertTimeRange(range, of: track, at: .zero)
            copy.preferredTransform = try await track.load(.preferredTransform)
        }
        if !muted {
            for track in try await asset.loadTracks(withMediaType: .audio) {
                guard let copy = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
                else { continue }
                try copy.insertTimeRange(range, of: track, at: .zero)
            }
        }

        try? FileManager.default.removeItem(at: destination)
        guard let session = AVAssetExportSession(asset: composition, presetName: size.preset) else {
            throw ExportError.cannotExport
        }
        session.outputURL = destination
        session.outputFileType = .mp4
        session.shouldOptimizeForNetworkUse = true
        await session.export()
        guard session.status == .completed else { throw session.error ?? ExportError.failed }
    }

    /// "0:07.4" for short clips, "1:23" otherwise.
    static func format(_ seconds: Double) -> String {
        let s = max(0, seconds)
        let minutes = Int(s) / 60
        if s < 60 { return String(format: "0:%04.1f", s) }
        return String(format: "%d:%02d", minutes, Int(s) % 60)
    }
}

/// State shown by the video editor's toolbar.
@MainActor
final class VideoEditorModel: ObservableObject {
    @Published var muted = false
    @Published var trimming = false
    /// The kept part of the recording; nil means all of it.
    @Published var range: CMTimeRange?
    @Published var duration: Double = 0
    @Published var busy: String?

    var keptSeconds: Double { range.map { $0.duration.seconds } ?? duration }
}

/// Plays a recording and edits it: trim with QuickTime's own trim bar, mute, and export as
/// MP4 (original size, 1080p or 720p) or GIF, or copy the result.
@MainActor
final class VideoEditorController: NSObject, NSWindowDelegate {
    private static var open: [VideoEditorController] = []

    private let source: URL
    private let model = VideoEditorModel()
    private let playerView = AVPlayerView()
    private var window: NSWindow?

    static func edit(_ url: URL) {
        if let existing = open.first(where: { $0.source == url }) {
            existing.window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let editor = VideoEditorController(source: url)
        open.append(editor)
        editor.present()
    }

    private init(source: URL) {
        self.source = source
        super.init()
        playerView.player = AVPlayer(url: source)
        playerView.controlsStyle = .inline
        playerView.showsFullScreenToggleButton = true
        playerView.allowsPictureInPicturePlayback = false
        Task { [weak self] in
            let seconds = (try? await AVURLAsset(url: source).load(.duration).seconds) ?? 0
            self?.model.duration = seconds.isFinite ? seconds : 0
        }
    }

    private func present() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 960, height: 640),
            styleMask: [.titled, .closable, .resizable, .miniaturizable, .fullSizeContentView],
            backing: .buffered, defer: false
        )
        window.title = "Edit Recording"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.minSize = NSSize(width: 720, height: 460)
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentView = NSHostingView(rootView: VideoEditorView(
            model: model,
            playerView: playerView,
            trim: { [weak self] in self?.trim() },
            copy: { [weak self] in self?.copy() },
            export: { [weak self] size in self?.export(size) },
            exportGIF: { [weak self] in self?.exportGIF() }
        ))
        window.center()
        self.window = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        playerView.player?.pause()
        Self.open.removeAll { $0 === self }
    }

    // MARK: - Editing

    /// Shows QuickTime's trim bar. Trim keeps the part between the yellow handles.
    private func trim() {
        guard playerView.canBeginTrimming else { return }
        model.trimming = true
        playerView.beginTrimming { [weak self] result in
            Task { @MainActor in
                guard let self else { return }
                self.model.trimming = false
                guard result == .okButton, let item = self.playerView.player?.currentItem else { return }
                let start = item.reversePlaybackEndTime.isValid ? item.reversePlaybackEndTime : .zero
                let end = item.forwardPlaybackEndTime.isValid ? item.forwardPlaybackEndTime : item.duration
                guard end.isValid, end > start else { return }
                self.model.range = CMTimeRange(start: start, end: end)
            }
        }
    }

    // MARK: - Output

    private func copy() {
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("Marquee Recording \(UUID().uuidString.prefix(6)).mp4")
        let range = model.range, muted = model.muted
        run("Preparing…") { [source] in
            try await VideoExport.export(source, range: range, size: .original, muted: muted, to: destination)
        } then: {
            let pb = NSPasteboard.general
            pb.clearContents()
            pb.writeObjects([destination as NSURL])
            Sounds.play(.copy)
            Toast.show("Recording copied")
        }
    }

    private func export(_ size: VideoExport.Size) {
        let folder = Preferences.saveFolder
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let destination = Capture.uniqueURL(in: folder, date: Date(), ext: "mp4")
        let range = model.range, muted = model.muted
        run("Exporting…") { [source] in
            try await VideoExport.export(source, range: range, size: size, muted: muted, to: destination)
        } then: {
            Toast.show("Saved \(destination.lastPathComponent)")
            NSWorkspace.shared.activateFileViewerSelecting([destination])
        }
    }

    private func exportGIF() {
        let folder = Preferences.saveFolder
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let destination = Capture.uniqueURL(in: folder, date: Date(), ext: "gif")
        let trimmed = FileManager.default.temporaryDirectory.appendingPathComponent("Marquee-gif-\(UUID().uuidString).mp4")
        let range = model.range
        run("Making GIF…") { [source] in
            // GIFs have no sound; only the trimmed part is converted.
            try await VideoExport.export(source, range: range, size: .original, muted: true, to: trimmed)
            try await VideoTools.exportGIF(from: trimmed, to: destination)
            try? FileManager.default.removeItem(at: trimmed)
        } then: {
            Toast.show("Saved \(destination.lastPathComponent)")
            NSWorkspace.shared.activateFileViewerSelecting([destination])
        }
    }

    private func run(_ label: String, _ work: @escaping @Sendable () async throws -> Void,
                     then done: @escaping @MainActor () -> Void) {
        guard model.busy == nil else { return }
        model.busy = label
        Task { [weak self] in
            do {
                try await work()
                self?.model.busy = nil
                done()
            } catch {
                self?.model.busy = nil
                Toast.show(error.localizedDescription, duration: 3)
            }
        }
    }
}

/// The editor: the player fills the window, with a glass toolbar along the bottom.
private struct VideoEditorView: View {
    @ObservedObject var model: VideoEditorModel
    let playerView: AVPlayerView
    let trim: @MainActor () -> Void
    let copy: @MainActor () -> Void
    let export: @MainActor (VideoExport.Size) -> Void
    let exportGIF: @MainActor () -> Void

    var body: some View {
        VStack(spacing: 0) {
            PlayerHost(playerView: playerView)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .padding(.horizontal, 16)
                .padding(.top, 36)
                .padding(.bottom, 12)
            toolbar
                .padding(.bottom, 16)
        }
        .background(Color(nsColor: .underPageBackgroundColor))
        .frame(minWidth: 720, minHeight: 460)
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            GlassGroup(spacing: 8) {
                HStack(spacing: 8) {
                    Button(action: trim) { Label("Trim", systemImage: "scissors") }
                        .glassButtonStyle(prominent: model.range != nil)
                        .keyboardShortcut("t", modifiers: .command)
                        .help("Trim the start and end (⌘T)")
                        .disabled(model.trimming)
                    Toggle(isOn: $model.muted) { Label("Mute", systemImage: model.muted ? "speaker.slash.fill" : "speaker.wave.2") }
                        .toggleStyle(.button)
                        .glassButtonStyle(prominent: model.muted)
                        .help(model.muted ? "The export has no sound" : "Remove the sound from the export")
                }
            }

            Text(lengthText)
                .font(.system(size: 12, weight: .medium).monospacedDigit())
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)

            Spacer(minLength: 8)

            if let busy = model.busy {
                ProgressView().controlSize(.small)
                Text(busy).font(.system(size: 12)).foregroundStyle(.secondary)
            }

            GlassGroup(spacing: 8) {
                HStack(spacing: 8) {
                    Button(action: copy) { Label("Copy", systemImage: "doc.on.doc") }
                        .glassButtonStyle()
                        .keyboardShortcut("c", modifiers: .command)
                        .help("Copy the edited recording (⌘C)")
                    Menu {
                        ForEach(VideoExport.Size.allCases) { size in
                            Button("MP4 — \(size.title)") { export(size) }
                        }
                        Divider()
                        Button("GIF") { exportGIF() }
                    } label: {
                        Label("Export", systemImage: "square.and.arrow.up")
                    }
                    .menuStyle(.button)
                    .glassButtonStyle(prominent: true)
                    .fixedSize()
                    .help("Save the edited recording to your screenshots folder")
                }
            }
            .disabled(model.busy != nil || model.trimming)
        }
        .controlSize(.large)
        .padding(.horizontal, 16)
    }

    private var lengthText: String {
        let kept = VideoExport.format(model.keptSeconds)
        guard model.range != nil, model.duration > 0 else { return kept }
        return "\(kept) of \(VideoExport.format(model.duration))"
    }
}

/// Hosts the AppKit player, which has QuickTime's controls and trim bar.
private struct PlayerHost: NSViewRepresentable {
    let playerView: AVPlayerView
    func makeNSView(context: Context) -> AVPlayerView { playerView }
    func updateNSView(_ nsView: AVPlayerView, context: Context) {}
}
