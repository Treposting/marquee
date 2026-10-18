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
        // Later layers sit on top; hidden ones are left out.
        for text in edit.texts where !text.hidden {
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
        let origin = overlay.origin(for: box, in: size)

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
        container.frame = CGRect(x: (origin.x - shadow).rounded(), y: (origin.y - shadow).rounded(),
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
    /// The text layer picked in the layers panel or on the video.
    @Published var selectedTextID: UUID?

    var duration: Double { edit.duration }
    var hasMarks: Bool { markIn != nil && markOut != nil }

    /// Moves a text (a saved layer or the one being written) after it's dragged on the video.
    func setCenter(_ center: CGPoint, for id: UUID) {
        if draft?.id == id {
            draft?.center = center
        } else if let index = edit.texts.firstIndex(where: { $0.id == id }) {
            edit.texts[index].center = center
        }
    }

    func deleteText(_ id: UUID) {
        edit.texts.removeAll { $0.id == id }
        if selectedTextID == id { selectedTextID = nil }
    }
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
            contentRect: NSRect(x: 0, y: 0, width: 1140, height: 760),
            styleMask: [.titled, .closable, .resizable, .miniaturizable, .fullSizeContentView],
            backing: .buffered, defer: false
        )
        window.title = "Edit Recording"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.minSize = NSSize(width: 1000, height: 600)
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
            HStack(alignment: .top, spacing: 12) {
                VStack(spacing: 10) {
                    ZStack {
                        PlayerHost(playerView: playerView)
                        TextPreview(model: model)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                    Timeline(model: model, seek: actions.seek)

                    if !model.edit.removed.isEmpty {
                        CutChips(model: model)
                    }
                }
                LayersPanel(model: model)
                    .frame(width: 230)
            }
            .padding(.top, 36)

            toolbar
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
        .background(Color(nsColor: .underPageBackgroundColor))
        .frame(minWidth: 1000, minHeight: 600)
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
                    Button {
                        if model.hasMarks { actions.removeSection() } else if let id = model.selectedTextID { model.deleteText(id) }
                    } label: { Label("Remove Section", systemImage: "scissors") }
                        .glassButtonStyle()
                        .disabled(!model.hasMarks && model.selectedTextID == nil)
                        .keyboardShortcut(.delete, modifiers: [])
                        .help("Cut out the part between the marks (⌫). With no marks, ⌫ deletes the selected text layer.")
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
/// in yellow and the playhead. Click or drag to move the playhead. Under it, one lane per text
/// layer shows when that text is on screen.
private struct Timeline: View {
    @ObservedObject var model: VideoEditorModel
    let seek: @MainActor (Double) -> Void

    var body: some View {
        VStack(spacing: 4) {
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
            .frame(height: 34)
            .accessibilityElement()
            .accessibilityLabel("Timeline")
            .accessibilityValue("\(VideoExport.format(model.currentTime)) of \(VideoExport.format(model.duration))")

            // Lanes, in the same order as the layers panel (top layer first).
            ForEach(model.edit.texts.reversed()) { overlay in
                GeometryReader { geo in
                    let total = max(model.duration, 0.001)
                    let start = overlay.start ?? 0
                    let end = overlay.end ?? model.duration
                    let x0 = CGFloat(start / total) * geo.size.width
                    let x1 = CGFloat(end / total) * geo.size.width
                    let selected = model.selectedTextID == overlay.id
                    Capsule()
                        .fill(Color.accentColor.opacity(overlay.hidden ? 0.15 : (selected ? 0.85 : 0.45)))
                        .frame(width: max(4, x1 - x0), height: 6)
                        .offset(x: x0, y: 1)
                        .onTapGesture { model.selectedTextID = overlay.id }
                }
                .frame(height: 8)
                .help("“\(overlay.text)”")
            }
        }
    }
}

/// Cut sections as chips; ✕ puts a section back.
private struct CutChips: View {
    @ObservedObject var model: VideoEditorModel

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(Array(model.edit.removed.enumerated()), id: \.offset) { _, cut in
                    HStack(spacing: 6) {
                        Image(systemName: "scissors").font(.system(size: 10, weight: .semibold)).foregroundStyle(.red)
                        Text("Cut \(VideoExport.format(cut.lowerBound))–\(VideoExport.format(cut.upperBound))")
                            .font(.system(size: 11.5, weight: .medium))
                        Button { model.edit.restore(cut) } label: {
                            Image(systemName: "xmark").font(.system(size: 9, weight: .bold))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .help("Put this section back")
                        .accessibilityLabel("Put back the cut at \(VideoExport.format(cut.lowerBound))")
                    }
                    .padding(.horizontal, 10)
                    .frame(height: 26)
                    .background(Color.red.opacity(0.12), in: Capsule())
                }
            }
        }
    }
}

/// The layers on the video, top first: each text with show/hide, its timing and delete; drag
/// rows to change which text is in front. The recording itself is the bottom layer.
private struct LayersPanel: View {
    @ObservedObject var model: VideoEditorModel

    private var topFirst: [TextOverlay] { model.edit.texts.reversed() }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Layers").font(.system(size: 13, weight: .semibold))
                Spacer()
                Button { model.draft = TextOverlay(text: "") } label: { Image(systemName: "plus") }
                    .buttonStyle(.borderless)
                    .help("Add text")
                    .accessibilityLabel("Add text")
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)

            if model.edit.texts.isEmpty {
                Text("Text you add shows up here. Drag it on the video to place it.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
            }

            List(selection: $model.selectedTextID) {
                ForEach(topFirst) { overlay in
                    row(overlay).tag(overlay.id)
                }
                .onMove { from, to in move(from: from, to: to) }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)

            Divider().padding(.horizontal, 12)
            HStack(spacing: 8) {
                Image(systemName: "film").foregroundStyle(.secondary).frame(width: 18)
                Text("Video").font(.system(size: 12, weight: .medium))
                Spacer()
                Image(systemName: "lock.fill").font(.system(size: 9)).foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Video, bottom layer")
        }
        .frame(maxHeight: .infinity)
        .background(Color.primary.opacity(0.04), in: Page.card)
        .overlay(Page.card.strokeBorder(Color.primary.opacity(0.08)))
    }

    private func row(_ overlay: TextOverlay) -> some View {
        HStack(spacing: 8) {
            Button {
                if let i = model.edit.texts.firstIndex(where: { $0.id == overlay.id }) { model.edit.texts[i].hidden.toggle() }
            } label: {
                Image(systemName: overlay.hidden ? "eye.slash" : "eye")
                    .foregroundStyle(overlay.hidden ? .tertiary : .secondary)
                    .frame(width: 18)
            }
            .buttonStyle(.plain)
            .help(overlay.hidden ? "Show (it will be exported)" : "Hide (it won't be exported)")
            .accessibilityLabel(overlay.hidden ? "Show layer" : "Hide layer")
            VStack(alignment: .leading, spacing: 1) {
                Text(overlay.text.isEmpty ? "Text" : overlay.text)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                    .opacity(overlay.hidden ? 0.5 : 1)
                Text(timing(overlay))
                    .font(.system(size: 10).monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            Button { model.deleteText(overlay.id) } label: {
                Image(systemName: "xmark").font(.system(size: 9, weight: .bold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Delete this layer")
            .accessibilityLabel("Delete \(overlay.text)")
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { model.draft = overlay }
        .contextMenu {
            Button("Edit…") { model.draft = overlay }
            Button(overlay.hidden ? "Show" : "Hide") {
                if let i = model.edit.texts.firstIndex(where: { $0.id == overlay.id }) { model.edit.texts[i].hidden.toggle() }
            }
            Button("Reset Position") {
                if let i = model.edit.texts.firstIndex(where: { $0.id == overlay.id }) { model.edit.texts[i].center = nil }
            }
            Divider()
            Button("Delete", role: .destructive) { model.deleteText(overlay.id) }
        }
    }

    private func timing(_ overlay: TextOverlay) -> String {
        guard let start = overlay.start, let end = overlay.end else { return "Whole video" }
        return "\(VideoExport.format(start))–\(VideoExport.format(end))"
    }

    /// The panel lists the top layer first; texts are stored bottom first.
    private func move(from source: IndexSet, to destination: Int) {
        var list = topFirst
        list.move(fromOffsets: source, toOffset: destination)
        model.edit.texts = list.reversed()
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
                Text("Tip: drag the text on the video to put it anywhere.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Picker("Position", selection: Binding(get: { draft.position }, set: {
                    model.draft?.position = $0
                    model.draft?.center = nil
                })) {
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
        model.selectedTextID = overlay.id
        model.draft = nil
    }
}

/// Shows the text overlays on the player, where and when they'll be in the export. Drag a
/// text to place it anywhere; double-click it to edit it.
private struct TextPreview: View {
    @ObservedObject var model: VideoEditorModel
    @State private var frames: [UUID: CGRect] = [:]
    @State private var dragStart: [UUID: CGPoint] = [:]
    @State private var hovering: UUID?

    private struct FrameKey: PreferenceKey {
        static var defaultValue: [UUID: CGRect] = [:]
        static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
            value.merge(nextValue()) { $1 }
        }
    }

    var body: some View {
        GeometryReader { geo in
            // The video is fitted inside the player; text is placed relative to the video.
            let video = model.videoSize
            let scale = video.width > 0 && video.height > 0
                ? min(geo.size.width / video.width, geo.size.height / video.height) : 0
            let frame = CGSize(width: video.width * scale, height: video.height * scale)
            ZStack {
                ForEach(shown) { overlay in
                    placed(label(overlay, in: frame), overlay: overlay, in: frame)
                }
            }
            .frame(width: frame.width, height: frame.height)
            .coordinateSpace(name: "video")
            .onPreferenceChange(FrameKey.self) { frames = $0 }
            .position(x: geo.size.width / 2, y: geo.size.height / 2)
        }
    }

    private var shown: [TextOverlay] {
        var list = model.edit.texts.filter { $0.isVisible(at: model.currentTime) && $0.id != model.draft?.id }
        if let draft = model.draft { list.append(draft) }
        return list
    }

    private func label(_ overlay: TextOverlay, in frame: CGSize) -> some View {
        let look = TextLook(overlay.style)
        let size = max(frame.height * look.scale, 6)
        let active = hovering == overlay.id || model.selectedTextID == overlay.id || dragStart[overlay.id] != nil
        return Text(overlay.text.isEmpty ? " " : overlay.text)
            .font(.system(size: size, weight: Font.Weight(look.weight)))
            .multilineTextAlignment(.center)
            .foregroundStyle(Color(nsColor: look.foreground))
            .padding(.horizontal, look.background == nil ? 0 : size * 0.6)
            .padding(.vertical, look.background == nil ? 0 : size * 0.3)
            .background(look.background.map { Color(nsColor: $0) } ?? .clear,
                        in: RoundedRectangle(cornerRadius: size * 0.35, style: .continuous))
            .shadow(color: look.background == nil ? .black.opacity(0.7) : .clear, radius: size * 0.12)
            .frame(maxWidth: frame.width * 0.86)
            .fixedSize(horizontal: false, vertical: true)
            .padding(4)
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                .opacity(active ? 1 : 0))
            .background(GeometryReader { g in
                Color.clear.preference(key: FrameKey.self, value: [overlay.id: g.frame(in: .named("video"))])
            })
            .contentShape(Rectangle())
            .onHover { hovering = $0 ? overlay.id : (hovering == overlay.id ? nil : hovering) }
            .onTapGesture(count: 2) { model.draft = overlay }
            .gesture(DragGesture(minimumDistance: 2)
                .onChanged { value in
                    guard frame.width > 0, frame.height > 0 else { return }
                    model.selectedTextID = overlay.id
                    let start = dragStart[overlay.id]
                        ?? frames[overlay.id].map { CGPoint(x: $0.midX, y: $0.midY) }
                        ?? CGPoint(x: frame.width / 2, y: frame.height / 2)
                    if dragStart[overlay.id] == nil { dragStart[overlay.id] = start }
                    let x = min(max(0.03, (start.x + value.translation.width) / frame.width), 0.97)
                    let y = min(max(0.03, (start.y + value.translation.height) / frame.height), 0.97)
                    model.setCenter(CGPoint(x: x, y: y), for: overlay.id)
                }
                .onEnded { _ in dragStart[overlay.id] = nil })
            .help("Drag to move · double-click to edit")
            .accessibilityLabel("Text \(overlay.text)")
    }

    @ViewBuilder
    private func placed(_ label: some View, overlay: TextOverlay, in frame: CGSize) -> some View {
        if let center = overlay.center {
            label.position(x: center.x * frame.width, y: center.y * frame.height)
        } else {
            label
                .padding(.vertical, frame.height * 0.07 - 4)
                .frame(width: frame.width, height: frame.height, alignment: overlay.position.alignment)
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
