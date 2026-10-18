import AppKit
import AVFoundation
import AVKit
import SwiftUI

/// Exports an edited recording: trimmed, with sections cut out, text on top, without sound,
/// or smaller.
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

        /// Preset when nothing is drawn on the video. Original keeps the recorded H.264 and AAC
        /// as they are: fast, no quality loss.
        var preset: String {
            switch self {
            case .original: return AVAssetExportPresetPassthrough
            case .hd1080: return AVAssetExportPreset1920x1080
            case .hd720: return AVAssetExportPreset1280x720
            }
        }
    }

    enum ExportError: LocalizedError {
        case noVideo, nothingLeft, cannotExport, failed
        var errorDescription: String? {
            switch self {
            case .noVideo: return "This recording has no video track."
            case .nothingLeft: return "Every part of the recording was cut out."
            case .cannotExport: return "This recording can't be exported in that format."
            case .failed: return "The export didn't finish."
            }
        }
    }

    private static func time(_ seconds: Double) -> CMTime { CMTime(seconds: seconds, preferredTimescale: 600) }

    /// Writes the kept parts of `source`, one after another, to `destination` as MP4.
    static func export(_ source: URL, edit: VideoEdit, size: Size, muted: Bool, to destination: URL) async throws {
        let asset = AVURLAsset(url: source)
        guard let videoTrack = try await asset.loadTracks(withMediaType: .video).first else { throw ExportError.noVideo }
        let audioTracks = muted ? [] : try await asset.loadTracks(withMediaType: .audio)
        let segments = edit.keptSegments
        guard !segments.isEmpty else { throw ExportError.nothingLeft }

        let composition = AVMutableComposition()
        guard let video = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)
        else { throw ExportError.cannotExport }
        video.preferredTransform = try await videoTrack.load(.preferredTransform)
        let audio = audioTracks.compactMap { _ in
            composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
        }
        var cursor = CMTime.zero
        for piece in segments {
            let range = CMTimeRange(start: time(piece.lowerBound), end: time(piece.upperBound))
            try video.insertTimeRange(range, of: videoTrack, at: cursor)
            for (copy, track) in zip(audio, audioTracks) {
                try copy.insertTimeRange(range, of: track, at: cursor)
            }
            cursor = cursor + range.duration
        }

        // Text is drawn into the frames, which means re-encoding instead of passthrough.
        var videoComposition: AVVideoComposition?
        if !edit.texts.isEmpty {
            videoComposition = try await overlayComposition(for: composition, edit: edit)
        }
        let preset = videoComposition != nil && size == .original ? AVAssetExportPresetHighestQuality : size.preset

        try? FileManager.default.removeItem(at: destination)
        guard let session = AVAssetExportSession(asset: composition, presetName: preset) else {
            throw ExportError.cannotExport
        }
        session.outputURL = destination
        session.outputFileType = .mp4
        session.shouldOptimizeForNetworkUse = true
        session.videoComposition = videoComposition
        await session.export()
        guard session.status == .completed else { throw session.error ?? ExportError.failed }
    }

    /// A video composition that draws each text overlay on top of the video for its time.
    private static func overlayComposition(for composition: AVComposition, edit: VideoEdit) async throws -> AVVideoComposition {
        let videoComposition = try await AVMutableVideoComposition.videoComposition(withPropertiesOf: composition)
        let size = videoComposition.renderSize
        let parent = CALayer()
        parent.frame = CGRect(origin: .zero, size: size)
        let videoLayer = CALayer()
        videoLayer.frame = parent.frame
        parent.addSublayer(videoLayer)
        for text in edit.texts {
            guard let layer = textLayer(for: text, in: size) else { continue }
            if let start = text.start, let end = text.end {
                // Shown only between its start and end, counted in the edited video's time.
                let from = edit.editedTime(for: start), to = edit.editedTime(for: end)
                guard to > from else { continue }
                layer.opacity = 0
                let show = CABasicAnimation(keyPath: "opacity")
                show.fromValue = 1
                show.toValue = 1
                show.beginTime = from > 0 ? from : AVCoreAnimationBeginTimeAtZero
                show.duration = to - from
                show.isRemovedOnCompletion = true
                layer.add(show, forKey: "show")
            }
            parent.addSublayer(layer)
        }
        videoComposition.animationTool = AVVideoCompositionCoreAnimationTool(postProcessingAsVideoLayer: videoLayer, in: parent)
        return videoComposition
    }

    /// One overlay as layers sized to the video. Layer coordinates start at the bottom left.
    static func textLayer(for overlay: TextOverlay, in size: CGSize) -> CALayer? {
        let text = overlay.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, size.width > 0, size.height > 0 else { return nil }
        let look = TextLook(overlay.style)
        let fontSize = (size.height * look.scale).rounded()
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let string = NSAttributedString(string: text, attributes: [
            .font: NSFont.systemFont(ofSize: fontSize, weight: look.weight),
            .foregroundColor: look.foreground,
            .paragraphStyle: paragraph,
        ])
        let maxWidth = size.width * 0.86
        let bounds = string.boundingRect(with: CGSize(width: maxWidth, height: .greatestFiniteMagnitude),
                                         options: [.usesLineFragmentOrigin, .usesFontLeading])
        let padX = look.background == nil ? 0 : fontSize * 0.6
        let padY = look.background == nil ? 0 : fontSize * 0.3
        let box = CGSize(width: ceil(bounds.width) + padX * 2, height: ceil(bounds.height) + padY * 2)
        let margin = size.height * 0.07
        let y: CGFloat
        switch overlay.position {
        case .top: y = size.height - margin - box.height
        case .middle: y = (size.height - box.height) / 2
        case .bottom: y = margin
        }

        // CATextLayer doesn't draw during an offline export, so the box and text are drawn
        // into an image that becomes the layer's contents.
        let shadow = look.background == nil ? fontSize * 0.25 : 0
        let canvas = CGSize(width: ceil(box.width + shadow * 2), height: ceil(box.height + shadow * 2))
        let image = NSImage(size: canvas, flipped: false) { _ in
            let rect = CGRect(x: shadow, y: shadow, width: box.width, height: box.height)
            if let background = look.background {
                background.setFill()
                NSBezierPath(roundedRect: rect, xRadius: fontSize * 0.35, yRadius: fontSize * 0.35).fill()
            } else {
                let glow = NSShadow()
                glow.shadowColor = NSColor.black.withAlphaComponent(0.75)
                glow.shadowBlurRadius = fontSize * 0.14
                glow.shadowOffset = CGSize(width: 0, height: -fontSize * 0.04)
                glow.set()
            }
            string.draw(with: CGRect(x: rect.minX + padX, y: rect.minY + padY, width: ceil(bounds.width), height: ceil(bounds.height)),
                        options: [.usesLineFragmentOrigin, .usesFontLeading])
            return true
        }
        var proposed = CGRect(origin: .zero, size: canvas)
        guard let cgImage = image.cgImage(forProposedRect: &proposed, context: nil, hints: nil) else { return nil }
        let container = CALayer()
        container.frame = CGRect(x: ((size.width - canvas.width) / 2).rounded(), y: (y - shadow).rounded(),
                                 width: canvas.width, height: canvas.height)
        container.contents = cgImage
        container.contentsGravity = .resize
        return container
    }

    /// "0:07.4" for short clips, "1:23" otherwise.
    static func format(_ seconds: Double) -> String {
        let s = max(0, seconds)
        if s < 60 { return String(format: "0:%04.1f", s) }
        return String(format: "%d:%02d", Int(s) / 60, Int(s) % 60)
    }
}

/// How each text style looks; shared by the export and the live preview.
struct TextLook {
    let foreground: NSColor
    let background: NSColor?
    let weight: NSFont.Weight
    /// Font size as a share of the video's height.
    let scale: CGFloat

    init(_ style: TextOverlay.Style) {
        switch style {
        case .caption:
            self.init(foreground: .white, background: NSColor.black.withAlphaComponent(0.62), weight: .semibold, scale: 0.05)
        case .bold:
            self.init(foreground: .white, background: nil, weight: .heavy, scale: 0.08)
        case .highlight:
            self.init(foreground: NSColor(calibratedWhite: 0.11, alpha: 1),
                      background: NSColor(calibratedRed: 1, green: 0.81, blue: 0.1, alpha: 1), weight: .bold, scale: 0.055)
        }
    }

    private init(foreground: NSColor, background: NSColor?, weight: NSFont.Weight, scale: CGFloat) {
        self.foreground = foreground
        self.background = background
        self.weight = weight
        self.scale = scale
    }
}

/// State shared by the video editor's controls.
@MainActor
final class VideoEditorModel: ObservableObject {
    @Published var edit = VideoEdit(duration: 0)
    @Published var muted = false
    @Published var trimming = false
    @Published var busy: String?
    /// Playhead, in seconds of the original recording.
    @Published var currentTime: Double = 0
    @Published var markIn: Double?
    @Published var markOut: Double?
    /// The video's pixel size, for placing the text preview.
    @Published var videoSize: CGSize = .zero
    /// The text being added or edited.
    @Published var draft: TextOverlay?

    var duration: Double { edit.duration }
    var hasMarks: Bool { markIn != nil && markOut != nil }
}

/// Plays a recording and edits it: trim the ends (QuickTime's trim bar), cut sections out of
/// the middle, add text, mute, and export as MP4 (original size, 1080p or 720p) or GIF, or copy.
@MainActor
final class VideoEditorController: NSObject, NSWindowDelegate {
    private static var open: [VideoEditorController] = []

    private let source: URL
    private let model = VideoEditorModel()
    private let playerView = AVPlayerView()
    private var window: NSWindow?
    private var timeObserver: Any?

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
        let player = AVPlayer(url: source)
        playerView.player = player
        playerView.controlsStyle = .inline
        playerView.showsFullScreenToggleButton = true
        playerView.allowsPictureInPicturePlayback = false
        Task { [weak self] in
            let asset = AVURLAsset(url: source)
            let seconds = (try? await asset.load(.duration).seconds) ?? 0
            let track = try? await asset.loadTracks(withMediaType: .video).first
            let natural = (try? await track?.load(.naturalSize)) ?? .zero
            self?.model.edit = VideoEdit(duration: seconds.isFinite ? seconds : 0)
            self?.model.videoSize = natural
        }
        // Follows the playhead, and skips the sections that were cut while previewing.
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(value: 1, timescale: 20), queue: .main) { [weak self] time in
            Task { @MainActor in
                guard let self else { return }
                let seconds = time.seconds
                self.model.currentTime = seconds.isFinite ? seconds : 0
                if let cut = self.model.edit.cut(containing: self.model.currentTime), player.rate != 0 {
                    player.seek(to: CMTime(seconds: cut.upperBound, preferredTimescale: 600),
                                toleranceBefore: .zero, toleranceAfter: .zero)
                }
            }
        }
    }

    private func present() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1000, height: 720),
            styleMask: [.titled, .closable, .resizable, .miniaturizable, .fullSizeContentView],
            backing: .buffered, defer: false
        )
        window.title = "Edit Recording"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.minSize = NSSize(width: 860, height: 560)
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentView = NSHostingView(rootView: VideoEditorView(
            model: model,
            playerView: playerView,
            actions: VideoEditorView.Actions(
                trim: { [weak self] in self?.trim() },
                seek: { [weak self] seconds in self?.seek(to: seconds) },
                removeSection: { [weak self] in self?.removeSection() },
                copy: { [weak self] in self?.copy() },
                export: { [weak self] size in self?.export(size) },
                exportGIF: { [weak self] in self?.exportGIF() }
            )
        ))
        window.centerOnActiveScreen()
        self.window = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        playerView.player?.pause()
        if let timeObserver { playerView.player?.removeTimeObserver(timeObserver) }
        timeObserver = nil
        Self.open.removeAll { $0 === self }
    }

    // MARK: - Editing

    private func seek(to seconds: Double) {
        playerView.player?.seek(to: CMTime(seconds: max(0, min(seconds, model.duration)), preferredTimescale: 600),
                                toleranceBefore: .zero, toleranceAfter: .zero)
        model.currentTime = seconds
    }

    /// Shows QuickTime's trim bar. Trim keeps the part between the yellow handles.
    private func trim() {
        guard playerView.canBeginTrimming else { return }
        model.trimming = true
        playerView.beginTrimming { [weak self] result in
            Task { @MainActor in
                guard let self else { return }
                self.model.trimming = false
                guard result == .okButton, let item = self.playerView.player?.currentItem else { return }
                let start = item.reversePlaybackEndTime.isValid ? item.reversePlaybackEndTime.seconds : 0
                let end = item.forwardPlaybackEndTime.isValid ? item.forwardPlaybackEndTime.seconds : self.model.duration
                guard end > start else { return }
                self.model.edit.trim = start...end
            }
        }
    }

    /// Cuts out the part between the two marks.
    private func removeSection() {
        guard let a = model.markIn, let b = model.markOut else { return }
        model.edit.remove(from: a, to: b)
        model.markIn = nil
        model.markOut = nil
    }

    // MARK: - Output

    private func copy() {
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("Marquee Recording \(UUID().uuidString.prefix(6)).mp4")
        let edit = model.edit, muted = model.muted
        run("Preparing…") { [source] in
            try await VideoExport.export(source, edit: edit, size: .original, muted: muted, to: destination)
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
        let edit = model.edit, muted = model.muted
        run("Exporting…") { [source] in
            try await VideoExport.export(source, edit: edit, size: size, muted: muted, to: destination)
        } then: {
            Toast.show("Saved \(destination.lastPathComponent)")
            NSWorkspace.shared.activateFileViewerSelecting([destination])
        }
    }

    private func exportGIF() {
        let folder = Preferences.saveFolder
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let destination = Capture.uniqueURL(in: folder, date: Date(), ext: "gif")
        let edited = FileManager.default.temporaryDirectory.appendingPathComponent("Marquee-gif-\(UUID().uuidString).mp4")
        let edit = model.edit
        run("Making GIF…") { [source] in
            // GIFs have no sound; cuts and text are applied first.
            try await VideoExport.export(source, edit: edit, size: .original, muted: true, to: edited)
            try await VideoTools.exportGIF(from: edited, to: destination)
            try? FileManager.default.removeItem(at: edited)
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

/// The editor: the player with a text preview on top, a timeline, and glass toolbars.
private struct VideoEditorView: View {
    struct Actions {
        let trim: @MainActor () -> Void
        let seek: @MainActor (Double) -> Void
        let removeSection: @MainActor () -> Void
        let copy: @MainActor () -> Void
        let export: @MainActor (VideoExport.Size) -> Void
        let exportGIF: @MainActor () -> Void
    }

    @ObservedObject var model: VideoEditorModel
    let playerView: AVPlayerView
    let actions: Actions

    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                PlayerHost(playerView: playerView)
                TextPreview(model: model)
                    .allowsHitTesting(false)
            }
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .padding(.top, 36)

            Timeline(model: model, seek: actions.seek)
                .frame(height: 34)

            if !model.edit.removed.isEmpty || !model.edit.texts.isEmpty {
                EditChips(model: model)
            }

            toolbar
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
        .background(Color(nsColor: .underPageBackgroundColor))
        .frame(minWidth: 860, minHeight: 560)
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            GlassGroup(spacing: 8) {
                HStack(spacing: 8) {
                    Button(action: actions.trim) { Label("Trim", systemImage: "arrow.left.and.right.square") }
                        .glassButtonStyle(prominent: model.edit.trim != nil)
                        .keyboardShortcut("t", modifiers: .command)
                        .help("Trim the start and end (⌘T)")
                        .disabled(model.trimming)
                    Button { model.markIn = model.currentTime } label: { Label("Start", systemImage: "chevron.left.to.line") }
                        .glassButtonStyle(prominent: model.markIn != nil)
                        .keyboardShortcut("i", modifiers: [])
                        .help("Mark where a section starts, at the playhead (I)")
                    Button { model.markOut = model.currentTime } label: { Label("End", systemImage: "chevron.right.to.line") }
                        .glassButtonStyle(prominent: model.markOut != nil)
                        .keyboardShortcut("o", modifiers: [])
                        .help("Mark where a section ends, at the playhead (O)")
                    Button(action: actions.removeSection) { Label("Remove Section", systemImage: "scissors") }
                        .glassButtonStyle()
                        .disabled(!model.hasMarks)
                        .keyboardShortcut(.delete, modifiers: [])
                        .help("Cut out the part between the marks (⌫)")
                    Button { model.draft = TextOverlay(text: "") } label: { Label("Add Text", systemImage: "textformat") }
                        .glassButtonStyle()
                        .help("Put text on the video")
                        .popover(isPresented: Binding(get: { model.draft != nil }, set: { if !$0 { model.draft = nil } }),
                                 arrowEdge: .top) {
                            TextEditorPopover(model: model)
                        }
                    Toggle(isOn: $model.muted) { Label("Mute", systemImage: model.muted ? "speaker.slash.fill" : "speaker.wave.2") }
                        .toggleStyle(.button)
                        .glassButtonStyle(prominent: model.muted)
                        .help(model.muted ? "The export has no sound" : "Remove the sound from the export")
                }
                .labelStyle(.titleAndIcon)
            }

            Spacer(minLength: 8)

            Text(lengthText)
                .font(.system(size: 12, weight: .medium).monospacedDigit())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .fixedSize()

            if let busy = model.busy {
                ProgressView().controlSize(.small)
                Text(busy).font(.system(size: 12)).foregroundStyle(.secondary).fixedSize()
            }

            GlassGroup(spacing: 8) {
                HStack(spacing: 8) {
                    Button(action: actions.copy) { Image(systemName: "doc.on.doc") }
                        .glassButtonStyle()
                        .keyboardShortcut("c", modifiers: .command)
                        .help("Copy the edited recording (⌘C)")
                        .accessibilityLabel("Copy")
                    Menu {
                        ForEach(VideoExport.Size.allCases) { size in
                            Button("MP4 — \(size.title)") { actions.export(size) }
                        }
                        Divider()
                        Button("GIF") { actions.exportGIF() }
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
    }

    private var lengthText: String {
        let kept = VideoExport.format(model.edit.keptDuration)
        guard model.duration > 0, abs(model.edit.keptDuration - model.duration) > 0.05 else { return kept }
        return "\(kept) of \(VideoExport.format(model.duration))"
    }
}

/// A strip for the whole recording: trimmed-off ends dimmed, cut sections in red, the marks
/// in yellow and the playhead. Click or drag to move the playhead.
private struct Timeline: View {
    @ObservedObject var model: VideoEditorModel
    let seek: @MainActor (Double) -> Void

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let total = max(model.duration, 0.001)
            let x = { (t: Double) in CGFloat(t / total) * width }
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.08))
                if let trim = model.edit.trim {
                    Rectangle().fill(Color.primary.opacity(0.18)).frame(width: x(trim.lowerBound))
                    Rectangle().fill(Color.primary.opacity(0.18))
                        .frame(width: max(0, width - x(trim.upperBound)))
                        .offset(x: x(trim.upperBound))
                }
                ForEach(Array(model.edit.removed.enumerated()), id: \.offset) { _, cut in
                    Rectangle()
                        .fill(Color.red.opacity(0.45))
                        .overlay(Rectangle().strokeBorder(Color.red.opacity(0.8), lineWidth: 1))
                        .frame(width: max(2, x(cut.upperBound) - x(cut.lowerBound)))
                        .offset(x: x(cut.lowerBound))
                }
                if let a = model.markIn, let b = model.markOut {
                    Rectangle().fill(Color.yellow.opacity(0.3))
                        .frame(width: abs(x(b) - x(a)))
                        .offset(x: min(x(a), x(b)))
                }
                ForEach([model.markIn, model.markOut].compactMap { $0 }, id: \.self) { mark in
                    Rectangle().fill(Color.yellow).frame(width: 2).offset(x: x(mark) - 1)
                }
                Rectangle().fill(Color.accentColor).frame(width: 2)
                    .offset(x: x(model.currentTime) - 1)
                    .shadow(color: .black.opacity(0.3), radius: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                seek(Double(max(0, min(value.location.x, width)) / width) * total)
            })
        }
        .accessibilityElement()
        .accessibilityLabel("Timeline")
        .accessibilityValue("\(VideoExport.format(model.currentTime)) of \(VideoExport.format(model.duration))")
    }
}

/// Cut sections and text overlays as chips: click text to edit it, ✕ to remove either.
private struct EditChips: View {
    @ObservedObject var model: VideoEditorModel

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(Array(model.edit.removed.enumerated()), id: \.offset) { _, cut in
                    chip(icon: "scissors", text: "Cut \(VideoExport.format(cut.lowerBound))–\(VideoExport.format(cut.upperBound))",
                         tint: .red, open: nil) { model.edit.restore(cut) }
                }
                ForEach(model.edit.texts) { overlay in
                    chip(icon: "textformat", text: "“\(overlay.text)”", tint: .accentColor,
                         open: { model.draft = overlay }) { model.edit.texts.removeAll { $0.id == overlay.id } }
                }
            }
        }
    }

    private func chip(icon: String, text: String, tint: Color, open: (() -> Void)?, remove: @escaping () -> Void) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon).font(.system(size: 10, weight: .semibold)).foregroundStyle(tint)
            Text(text).font(.system(size: 11.5, weight: .medium)).lineLimit(1).frame(maxWidth: 200)
                .onTapGesture { open?() }
            Button(action: remove) { Image(systemName: "xmark").font(.system(size: 9, weight: .bold)) }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .accessibilityLabel("Remove \(text)")
        }
        .padding(.horizontal, 10)
        .frame(height: 26)
        .background(tint.opacity(0.12), in: Capsule())
    }
}

/// Add or change one text overlay.
private struct TextEditorPopover: View {
    @ObservedObject var model: VideoEditorModel
    @FocusState private var focused: Bool

    private enum Timing: String, CaseIterable, Identifiable {
        case whole, marks, threeSeconds
        var id: String { rawValue }
        var title: String {
            switch self {
            case .whole: return "Whole video"
            case .marks: return "Between the marks"
            case .threeSeconds: return "3 s from the playhead"
            }
        }
    }

    @State private var timing: Timing = .whole

    var body: some View {
        if let draft = model.draft {
            VStack(alignment: .leading, spacing: 12) {
                Text(model.edit.texts.contains { $0.id == draft.id } ? "Edit Text" : "Add Text")
                    .font(.system(size: 13, weight: .semibold))
                TextField("Text on the video", text: Binding(get: { model.draft?.text ?? "" }, set: { model.draft?.text = $0 }))
                    .textFieldStyle(.roundedBorder)
                    .focused($focused)
                    .frame(width: 300)
                Picker("Position", selection: Binding(get: { draft.position }, set: { model.draft?.position = $0 })) {
                    ForEach(TextOverlay.Position.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                Picker("Style", selection: Binding(get: { draft.style }, set: { model.draft?.style = $0 })) {
                    ForEach(TextOverlay.Style.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                Picker("Show", selection: $timing) {
                    ForEach(Timing.allCases) { option in
                        Text(option.title).tag(option)
                            .disabled(option == .marks && !model.hasMarks)
                    }
                }
                HStack {
                    Spacer()
                    Button("Cancel") { model.draft = nil }
                        .keyboardShortcut(.cancelAction)
                    Button("Done", action: save)
                        .keyboardShortcut(.defaultAction)
                        .buttonStyle(.borderedProminent)
                        .disabled(draft.text.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .padding(16)
            .onAppear {
                focused = true
                if draft.start != nil { timing = .threeSeconds }
            }
        }
    }

    private func save() {
        guard var overlay = model.draft else { return }
        switch timing {
        case .whole:
            overlay.start = nil
            overlay.end = nil
        case .marks:
            if let a = model.markIn, let b = model.markOut {
                overlay.start = min(a, b)
                overlay.end = max(a, b)
            }
        case .threeSeconds:
            if overlay.start == nil || overlay.end == nil {
                overlay.start = model.currentTime
                overlay.end = min(model.duration, model.currentTime + 3)
            }
        }
        if let index = model.edit.texts.firstIndex(where: { $0.id == overlay.id }) {
            model.edit.texts[index] = overlay
        } else {
            model.edit.texts.append(overlay)
        }
        model.draft = nil
    }
}

/// Shows the text overlays on the player, where and when they'll be in the export.
private struct TextPreview: View {
    @ObservedObject var model: VideoEditorModel

    var body: some View {
        GeometryReader { geo in
            // The video is fitted inside the player; text is placed relative to the video.
            let video = model.videoSize
            let scale = video.width > 0 && video.height > 0
                ? min(geo.size.width / video.width, geo.size.height / video.height) : 0
            let frame = CGSize(width: video.width * scale, height: video.height * scale)
            ZStack {
                ForEach(model.edit.texts.filter { $0.isVisible(at: model.currentTime) } + (model.draft.map { [$0] } ?? [])) { overlay in
                    let look = TextLook(overlay.style)
                    let size = frame.height * look.scale
                    Text(overlay.text)
                        .font(.system(size: max(size, 6), weight: Font.Weight(look.weight)))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(Color(nsColor: look.foreground))
                        .padding(.horizontal, look.background == nil ? 0 : size * 0.6)
                        .padding(.vertical, look.background == nil ? 0 : size * 0.3)
                        .background(look.background.map { Color(nsColor: $0) } ?? .clear,
                                    in: RoundedRectangle(cornerRadius: size * 0.35, style: .continuous))
                        .shadow(color: look.background == nil ? .black.opacity(0.7) : .clear, radius: size * 0.12)
                        .frame(maxWidth: frame.width * 0.86)
                        .padding(.vertical, frame.height * 0.07)
                        .frame(width: frame.width, height: frame.height, alignment: overlay.position.alignment)
                }
            }
            .frame(width: frame.width, height: frame.height)
            .position(x: geo.size.width / 2, y: geo.size.height / 2)
        }
    }
}

private extension TextOverlay.Position {
    var alignment: Alignment {
        switch self {
        case .top: return .top
        case .middle: return .center
        case .bottom: return .bottom
        }
    }
}

private extension Font.Weight {
    init(_ weight: NSFont.Weight) {
        switch weight {
        case .heavy: self = .heavy
        case .bold: self = .bold
        case .semibold: self = .semibold
        default: self = .regular
        }
    }
}

/// Hosts the AppKit player, which has QuickTime's controls and trim bar.
private struct PlayerHost: NSViewRepresentable {
    let playerView: AVPlayerView
    func makeNSView(context: Context) -> AVPlayerView { playerView }
    func updateNSView(_ nsView: AVPlayerView, context: Context) {}
}
