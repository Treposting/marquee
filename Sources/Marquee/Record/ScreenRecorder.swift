import AppKit
import ScreenCaptureKit

/// Screen recording with ScreenCaptureKit (macOS 12.3+), the same framework
/// CleanShot X, QuickTime and OBS use on modern macOS.
@MainActor
final class ScreenRecorder {
    private var stream: SCStream?
    private var output: RecordingOutput?
    private var microphone: MicrophoneCapture?
    private var borderWindow: NSWindow?

    private(set) var startDate: Date?
    var isRecording: Bool { stream != nil }
    /// Save the microphone as its own audio file when the recording stops.
    private var separateVoice = false
    /// When the voice was saved separately: the folder holding the video and the voice.
    private(set) var voiceFolder: URL?

    /// Called when the stream stops on its own (display disconnected, permission revoked…).
    var onUnexpectedStop: (() -> Void)?

    /// - Parameters:
    ///   - desktopAudio: record what the Mac plays (other apps' sound).
    ///   - microphone: an already-running microphone to record, or nil for none.
    ///   - includingWindows: Marquee windows that belong in the video (the camera bubble).
    ///   - separateVoice: also save the microphone as its own .m4a file.
    func start(screen: NSScreen, rect: CGRect, desktopAudio: Bool, microphone: MicrophoneCapture?,
               includingWindows: [CGWindowID] = [], separateVoice: Bool = false) async throws {
        guard !isRecording else { throw RecorderError.alreadyRecording }

        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let displayID = screen.displayID,
              let display = content.displays.first(where: { $0.displayID == displayID }) else {
            throw RecorderError.displayNotFound
        }

        // Keep Marquee's own windows (selection border, overlays) out of the video, except the
        // ones asked for, like the camera bubble.
        let pid = ProcessInfo.processInfo.processIdentifier
        let ownApps = content.applications.filter { $0.processID == pid }
        let kept = content.windows.filter { includingWindows.contains($0.windowID) }
        let filter = SCContentFilter(display: display, excludingApplications: ownApps, exceptingWindows: kept)

        // ScreenCaptureKit wants the source rect in display-local points with a top-left origin.
        let local = CGRect(
            x: rect.minX - screen.frame.minX,
            y: screen.frame.maxY - rect.maxY,
            width: rect.width,
            height: rect.height
        ).integral

        let (width, height) = Self.outputSize(for: local.size, backingScale: screen.backingScaleFactor,
                                              resolution: Preferences.recordResolution)
        let fps = Preferences.recordFPS
        let captureAudio = desktopAudio

        let config = SCStreamConfiguration()
        config.sourceRect = local
        config.width = width
        config.height = height
        config.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(fps))
        config.showsCursor = Preferences.recordShowCursor
        config.pixelFormat = kCVPixelFormatType_32BGRA
        // Untagged frames come in the display's space (often P3), so players show them washed out.
        config.colorSpaceName = CGColorSpace.sRGB
        config.queueDepth = 6
        config.capturesAudio = captureAudio
        config.excludesCurrentProcessAudio = true
        config.sampleRate = 48_000
        config.channelCount = 2

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("Marquee-\(UUID().uuidString).mp4")
        let output = try RecordingOutput(
            url: url, width: width, height: height, fps: fps,
            captureAudio: captureAudio, captureMicrophone: microphone != nil
        )
        output.onStreamError = { [weak self] error in
            NSLog("Marquee: recording stream stopped: \(error)")
            Task { @MainActor in self?.onUnexpectedStop?() }
        }

        let stream = SCStream(filter: filter, configuration: config, delegate: output)
        try stream.addStreamOutput(output, type: .screen, sampleHandlerQueue: output.queue)
        if captureAudio {
            try stream.addStreamOutput(output, type: .audio, sampleHandlerQueue: output.queue)
        }
        try await stream.startCapture()

        microphone?.sink = { [weak output] buffer in
            // CMSampleBuffer isn't Sendable; it's only handed to the writer's own queue.
            nonisolated(unsafe) let buffer = buffer
            output?.queue.async { output?.appendMicrophone(buffer) }
        }
        self.microphone = microphone
        self.separateVoice = separateVoice && microphone != nil
        voiceFolder = nil
        self.stream = stream
        self.output = output
        startDate = Date()
        if rect != screen.frame {
            showBorder(around: rect)
        }
    }

    /// Stops and returns the finished MP4, or nil if nothing was captured.
    func stop() async -> URL? {
        guard let stream, let output else { return nil }
        self.stream = nil
        self.output = nil
        microphone?.sink = nil
        microphone = nil
        startDate = nil
        hideBorder()
        do {
            try await stream.stopCapture()
        } catch {
            NSLog("Marquee: stopCapture failed: \(error)")
        }
        guard let url = await output.finish() else { return nil }
        // The voice comes out before the tracks are mixed, while it's still on its own track.
        var voice: URL?
        if separateVoice {
            let destination = FileManager.default.temporaryDirectory
                .appendingPathComponent("Marquee-voice-\(UUID().uuidString).m4a")
            do {
                try await AudioMixdown.exportMicrophoneTrack(of: url, to: destination)
                voice = destination
            } catch {
                NSLog("Marquee: couldn't save the voice file: \(error)")
            }
        }
        if output.hasTwoAudioTracks {
            do {
                try await AudioMixdown.mixAudioTracks(at: url)
            } catch {
                // The file still plays; it just keeps desktop audio and mic on separate tracks.
                NSLog("Marquee: couldn't mix audio tracks: \(error)")
            }
        }
        if let voice {
            do {
                voiceFolder = try Self.makeVoiceFolder(in: Preferences.saveFolder, date: Date(), video: url, voice: voice)
            } catch {
                NSLog("Marquee: couldn't make the recording folder: \(error)")
            }
        }
        return url
    }

    /// Puts a recording and its separate voice side by side in their own folder, named alike,
    /// so it's clear which voice belongs to which video:
    ///
    ///     Marquee Recording 2026-10-18 at 10.15.00/
    ///         Marquee Recording 2026-10-18 at 10.15.00.mp4
    ///         Marquee Recording 2026-10-18 at 10.15.00 Voice.m4a
    ///
    /// The video is copied (Marquee keeps using the original); the voice is moved.
    nonisolated static func makeVoiceFolder(in parent: URL, date: Date, video: URL, voice: URL) throws -> URL {
        let fm = FileManager.default
        let name = (Capture.fileName(for: date, ext: "mp4") as NSString).deletingPathExtension
        var folder = parent.appendingPathComponent(name, isDirectory: true)
        var n = 2
        while fm.fileExists(atPath: folder.path) {
            folder = parent.appendingPathComponent("\(name) (\(n))", isDirectory: true)
            n += 1
        }
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        try fm.copyItem(at: video, to: folder.appendingPathComponent("\(name).mp4"))
        try fm.moveItem(at: voice, to: folder.appendingPathComponent("\(name) Voice.m4a"))
        return folder
    }

    /// Pixel size of the video: Retina resolution, but kept within H.264's
    /// 4096×2304 hardware-encoder limit, and even in both dimensions.
    /// Also fits the chosen resolution (1080p, 720p); never scales up past Retina size.
    nonisolated static func outputSize(for size: CGSize, backingScale: CGFloat,
                           resolution: RecordResolution = .original) -> (Int, Int) {
        let landscape = size.width >= size.height
        let maxW: CGFloat = landscape ? 4096 : 2304
        let maxH: CGFloat = landscape ? 2304 : 4096
        var scale = min(backingScale, maxW / max(size.width, 1), maxH / max(size.height, 1))
        if let box = resolution.box {
            let boxW = landscape ? box.width : box.height
            let boxH = landscape ? box.height : box.width
            scale = min(scale, boxW / max(size.width, 1), boxH / max(size.height, 1))
        }
        func even(_ v: CGFloat) -> Int { max(2, Int(v) / 2 * 2) }
        return (even(size.width * scale), even(size.height * scale))
    }

    // MARK: - Border around the recorded area

    func showBorder(around rect: CGRect) {
        hideBorder()
        let window = NSWindow(
            contentRect: rect.insetBy(dx: -4, dy: -4),
            styleMask: [.borderless],
            backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        window.isOpaque = false
        window.backgroundColor = .clear
        window.ignoresMouseEvents = true
        window.level = .statusBar
        window.hasShadow = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        window.contentView = RecordingBorderView()
        window.orderFrontRegardless()
        borderWindow = window
    }

    func hideBorder() {
        borderWindow?.orderOut(nil)
        borderWindow = nil
    }
}

private final class RecordingBorderView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(rect: bounds.insetBy(dx: 2, dy: 2))
        path.lineWidth = 2
        NSColor.systemRed.setStroke()
        path.setLineDash([8, 4], count: 2, phase: 0)
        path.stroke()
    }
}

extension NSScreen {
    var displayID: CGDirectDisplayID? {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }

    static var underMouse: NSScreen? {
        let mouse = NSEvent.mouseLocation
        return screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? main
    }
}
