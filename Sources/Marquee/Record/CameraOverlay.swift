import AppKit
import AVFoundation
import SwiftUI

/// How the camera bubble looks and where it starts. Stored in UserDefaults, so the recording
/// toolbar menu and Settings → Recording share it.
enum CameraStyle {
    enum Shape: String, CaseIterable, Identifiable {
        case circle, rounded, square, portrait
        var id: String { rawValue }
        var title: String {
            switch self {
            case .circle: return "Circle"
            case .rounded: return "Rounded"
            case .square: return "Square"
            case .portrait: return "Portrait"
            }
        }
        var symbol: String {
            switch self {
            case .circle: return "circle"
            case .rounded: return "app"
            case .square: return "square"
            case .portrait: return "rectangle.portrait"
            }
        }
        /// Width ÷ height.
        var aspect: CGFloat { self == .portrait ? 3.0 / 4.0 : 1 }
        func cornerRadius(for size: CGSize) -> CGFloat {
            switch self {
            case .circle: return min(size.width, size.height) / 2
            case .rounded, .portrait: return min(size.width, size.height) * 0.22
            case .square: return 6
            }
        }
    }

    enum Size: String, CaseIterable, Identifiable {
        case small, medium, large
        var id: String { rawValue }
        var title: String { rawValue.capitalized }
        /// Height in points.
        var points: CGFloat {
            switch self {
            case .small: return 120
            case .medium: return 170
            case .large: return 240
            }
        }
    }

    enum Position: String, CaseIterable, Identifiable {
        case topLeft, topRight, bottomLeft, bottomRight
        var id: String { rawValue }
        var title: String {
            switch self {
            case .topLeft: return "Top Left"
            case .topRight: return "Top Right"
            case .bottomLeft: return "Bottom Left"
            case .bottomRight: return "Bottom Right"
            }
        }
        var symbol: String {
            switch self {
            case .topLeft: return "arrow.up.left"
            case .topRight: return "arrow.up.right"
            case .bottomLeft: return "arrow.down.left"
            case .bottomRight: return "arrow.down.right"
            }
        }
        var isLeft: Bool { self == .topLeft || self == .bottomLeft }
        var isTop: Bool { self == .topLeft || self == .topRight }
    }

    enum Border: String, CaseIterable, Identifiable {
        case none, white, yellow, yellowGlow, blueGlow, pinkGlow, rainbow
        var id: String { rawValue }
        var title: String {
            switch self {
            case .none: return "None"
            case .white: return "White"
            case .yellow: return "Yellow"
            case .yellowGlow: return "Yellow Glow"
            case .blueGlow: return "Blue Glow"
            case .pinkGlow: return "Pink Glow"
            case .rainbow: return "Rainbow"
            }
        }
        /// The ring's color; nil for no ring. Rainbow draws a color wheel instead.
        var color: NSColor? {
            switch self {
            case .none: return nil
            case .white: return .white
            case .yellow, .yellowGlow: return NSColor(calibratedRed: 1, green: 0.81, blue: 0.1, alpha: 1)
            case .blueGlow: return NSColor(calibratedRed: 0.25, green: 0.62, blue: 1, alpha: 1)
            case .pinkGlow: return NSColor(calibratedRed: 1, green: 0.3, blue: 0.62, alpha: 1)
            case .rainbow: return NSColor(calibratedRed: 0.75, green: 0.45, blue: 1, alpha: 1)
            }
        }
        /// Glowing styles draw a soft halo in the ring's color around the bubble.
        var glows: Bool {
            switch self {
            case .yellowGlow, .blueGlow, .pinkGlow, .rainbow: return true
            default: return false
            }
        }
        var lineWidth: CGFloat {
            switch self {
            case .none: return 0
            case .white, .yellow: return 3
            default: return 3.5
            }
        }
        static let rainbowColors: [NSColor] = [.systemRed, .systemOrange, .systemYellow, .systemGreen,
                                               .systemTeal, .systemBlue, .systemPurple, .systemPink, .systemRed]
    }

    /// Transparent room around the bubble for its shadow or glow.
    static let halo: CGFloat = 22

    private static var defaults: UserDefaults { .standard }

    static var shape: Shape {
        get { Shape(rawValue: defaults.string(forKey: Preferences.Key.cameraShape.rawValue) ?? "") ?? .circle }
        set { defaults.set(newValue.rawValue, forKey: Preferences.Key.cameraShape.rawValue) }
    }
    static var size: Size {
        get { Size(rawValue: defaults.string(forKey: Preferences.Key.cameraSize.rawValue) ?? "") ?? .medium }
        set { defaults.set(newValue.rawValue, forKey: Preferences.Key.cameraSize.rawValue) }
    }
    static var position: Position {
        get { Position(rawValue: defaults.string(forKey: Preferences.Key.cameraPosition.rawValue) ?? "") ?? .bottomLeft }
        set { defaults.set(newValue.rawValue, forKey: Preferences.Key.cameraPosition.rawValue) }
    }
    static var border: Border {
        get { Border(rawValue: defaults.string(forKey: Preferences.Key.cameraBorder.rawValue) ?? "") ?? .white }
        set { defaults.set(newValue.rawValue, forKey: Preferences.Key.cameraBorder.rawValue) }
    }
    static var mirror: Bool {
        get { defaults.object(forKey: Preferences.Key.cameraMirror.rawValue) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Preferences.Key.cameraMirror.rawValue) }
    }

    /// The bubble's size in points for the current shape and size.
    static var bubbleSize: CGSize {
        let height = size.points
        return CGSize(width: (height * shape.aspect).rounded(), height: height)
    }

    /// A bubble resized in place: it keeps its distance from the corner of `area` it's closest
    /// to (so it doesn't grow off an edge), then is kept inside `area`.
    static func resized(_ bubble: CGRect, to size: CGSize, in area: CGRect) -> CGRect {
        let left = bubble.midX < area.midX
        let bottom = bubble.midY < area.midY
        let x = left ? bubble.minX : bubble.maxX - size.width
        let y = bottom ? bubble.minY : bubble.maxY - size.height
        return clamped(CGRect(origin: CGPoint(x: x, y: y), size: size), in: area)
    }

    /// The bubble moved back inside `area` if any part of it sticks out.
    static func clamped(_ bubble: CGRect, in area: CGRect) -> CGRect {
        guard area.width >= bubble.width, area.height >= bubble.height else {
            return CGRect(x: area.midX - bubble.width / 2, y: area.midY - bubble.height / 2,
                          width: bubble.width, height: bubble.height)
        }
        var rect = bubble
        rect.origin.x = min(max(rect.minX, area.minX), area.maxX - rect.width)
        rect.origin.y = min(max(rect.minY, area.minY), area.maxY - rect.height)
        return rect
    }

    /// Where the bubble goes inside `area` (global AppKit coordinates).
    static func frame(in area: CGRect, size: CGSize, position: Position, margin: CGFloat = 24) -> CGRect {
        let x = position.isLeft ? area.minX + margin : area.maxX - margin - size.width
        let y = position.isTop ? area.maxY - margin - size.height : area.minY + margin
        return CGRect(origin: CGPoint(x: x, y: y), size: size)
    }
}

/// Every camera connected to the Mac: built-in, USB webcams and capture cards, virtual cameras
/// (OBS, Camo and other camera extensions), iPhone through Continuity Camera, and Desk View.
enum CameraDevices {
    struct Device: Identifiable, Hashable {
        let id: String
        let name: String
        let isBuiltIn: Bool
    }

    /// Posted when a camera is connected or disconnected.
    static let didChange = Notification.Name("MarqueeCamerasDidChange")
    nonisolated(unsafe) private static var observers: [NSObjectProtocol] = []

    private static var deviceTypes: [AVCaptureDevice.DeviceType] {
        if #available(macOS 14.0, *) {
            return [.builtInWideAngleCamera, .external, .continuityCamera, .deskViewCamera]
        }
        // On macOS 13 USB, capture-card, virtual and iPhone cameras are all "external unknown".
        return [.builtInWideAngleCamera, .externalUnknown, .deskViewCamera]
    }

    private static func captureDevices() -> [AVCaptureDevice] {
        var seen = Set<String>()
        return AVCaptureDevice.DiscoverySession(deviceTypes: deviceTypes, mediaType: .video, position: .unspecified)
            .devices
            .filter { $0.isConnected && !$0.isSuspended && seen.insert($0.uniqueID).inserted }
    }

    /// Connected cameras, built-in first, then by name.
    static func all() -> [Device] {
        captureDevices()
            .map { Device(id: $0.uniqueID, name: $0.localizedName, isBuiltIn: $0.deviceType == .builtInWideAngleCamera) }
            .sorted { a, b in
                a.isBuiltIn != b.isBuiltIn ? a.isBuiltIn : a.name.localizedStandardCompare(b.name) == .orderedAscending
            }
    }

    /// The chosen camera if it's connected, otherwise the system default, otherwise any camera.
    static func device(id: String?) -> AVCaptureDevice? {
        if let id, let device = AVCaptureDevice(uniqueID: id), device.isConnected { return device }
        if let device = AVCaptureDevice.default(for: .video), device.isConnected { return device }
        return captureDevices().first
    }

    /// Starts forwarding AVFoundation's connect and disconnect notifications as `didChange`.
    static func startWatching() {
        guard observers.isEmpty else { return }
        for name in [AVCaptureDevice.wasConnectedNotification, AVCaptureDevice.wasDisconnectedNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { note in
                NotificationCenter.default.post(name: didChange, object: note.object)
            })
        }
    }
}

/// Runs the camera. Starting and stopping block, so they happen on a private queue.
final class CameraFeed: @unchecked Sendable {
    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "Marquee.camera")
    private(set) var deviceName: String?
    private(set) var deviceID: String?

    func start(deviceID: String?) throws {
        guard let device = CameraDevices.device(id: deviceID) else { throw MicrophoneCapture.CaptureError.noDevice }
        let input = try AVCaptureDeviceInput(device: device)
        session.beginConfiguration()
        session.inputs.forEach { session.removeInput($0) }
        if session.canSetSessionPreset(.high) { session.sessionPreset = .high }
        guard session.canAddInput(input) else {
            session.commitConfiguration()
            throw MicrophoneCapture.CaptureError.cannotUse(device.localizedName)
        }
        session.addInput(input)
        session.commitConfiguration()
        self.deviceName = device.localizedName
        self.deviceID = device.uniqueID
        queue.async { [session] in
            if !session.isRunning { session.startRunning() }
        }
    }

    func stop() {
        queue.async { [session] in
            if session.isRunning { session.stopRunning() }
        }
    }
}

/// The floating camera bubble. It sits inside the recording area and is recorded with it;
/// drag it anywhere. Its look follows `CameraStyle` and updates when settings change.
@MainActor
final class CameraBubble {
    private var panel: NSPanel?
    private var view: CameraBubbleView?
    private let feed = CameraFeed()
    private var area: CGRect = .zero
    private var defaultsObserver: NSObjectProtocol?
    private var camerasObserver: NSObjectProtocol?
    /// The corner last applied, so a change in Settings moves the bubble right away.
    private var appliedPosition: CameraStyle.Position?

    /// Called when the camera in use was unplugged: with the new camera's name, or nil if
    /// there's none left and the bubble was hidden.
    var onCameraLost: ((String?) -> Void)?

    /// The bubble's window number, so the recorder can include it in the video.
    var windowID: CGWindowID? { panel.map { CGWindowID($0.windowNumber) } }
    var isVisible: Bool { panel != nil }
    var deviceName: String? { feed.deviceName }
    var deviceID: String? { feed.deviceID }

    /// Shows the bubble inside `area` at the chosen corner. Asks for camera access the first time.
    func show(in area: CGRect, deviceID: String?) async throws {
        self.area = area
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            break
        case .notDetermined:
            guard await AVCaptureDevice.requestAccess(for: .video) else { throw CameraError.notAllowed }
        default:
            throw CameraError.notAllowed
        }
        try feed.start(deviceID: deviceID)
        if panel == nil { makePanel() }
        applyStyle(reposition: true)
        panel?.orderFrontRegardless()
        // The video connection (needed for mirroring) appears once the camera is running.
        runAfter(0.5) { [weak self] in self?.applyStyle(reposition: false) }
        if camerasObserver == nil {
            CameraDevices.startWatching()
            camerasObserver = NotificationCenter.default.addObserver(
                forName: CameraDevices.didChange, object: nil, queue: .main
            ) { [weak self] _ in
                Task { @MainActor in self?.cameraListChanged() }
            }
        }
        if defaultsObserver == nil {
            defaultsObserver = NotificationCenter.default.addObserver(
                forName: UserDefaults.didChangeNotification, object: nil, queue: .main
            ) { [weak self] _ in
                Task { @MainActor in self?.applyStyle(reposition: false) }
            }
        }
    }

    /// Switches camera without moving the bubble.
    func switchCamera(to deviceID: String?) throws {
        try feed.start(deviceID: deviceID)
    }

    func hide() {
        appliedPosition = nil
        feed.stop()
        panel?.orderOut(nil)
        panel = nil
        view = nil
        for observer in [defaultsObserver, camerasObserver].compactMap({ $0 }) {
            NotificationCenter.default.removeObserver(observer)
        }
        defaultsObserver = nil
        camerasObserver = nil
    }

    /// If the camera in use went away, switch to another one, or hide when none is left.
    private func cameraListChanged() {
        guard panel != nil, let current = feed.deviceID,
              !CameraDevices.all().contains(where: { $0.id == current }) else { return }
        if CameraDevices.device(id: nil) != nil, (try? feed.start(deviceID: nil)) != nil {
            onCameraLost?(feed.deviceName)
        } else {
            hide()
            onCameraLost?(nil)
        }
    }

    /// Hides or shows the bubble without stopping the camera. A hidden bubble isn't recorded.
    func setHidden(_ hidden: Bool) {
        if hidden { panel?.orderOut(nil) } else { panel?.orderFrontRegardless() }
    }

    /// Moves the bubble to a corner of the recording area.
    func move(to position: CameraStyle.Position) {
        guard let panel else { return }
        let bubble = CameraStyle.frame(in: area, size: CameraStyle.bubbleSize, position: position)
        panel.setFrame(bubble.insetBy(dx: -CameraStyle.halo, dy: -CameraStyle.halo), display: true)
        appliedPosition = position
    }

    private func makePanel() {
        let panel = NSPanel(contentRect: NSRect(origin: .zero, size: CameraStyle.bubbleSize),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        // The view draws its own shadow or glow in the transparent room around the bubble.
        panel.hasShadow = false
        panel.level = .statusBar
        panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        let view = CameraBubbleView(session: feed.session)
        panel.contentView = view
        self.panel = panel
        self.view = view
    }

    /// Applies shape, size, border and mirroring. Size changes keep the bubble's centre unless
    /// it's being placed for the first time.
    /// Applies the current settings right away, also mid-recording: a new corner moves the
    /// bubble there; a new size or shape keeps it in its corner and inside the recording area.
    private func applyStyle(reposition: Bool) {
        guard let panel, let view else { return }
        let halo = CameraStyle.halo
        let size = CameraStyle.bubbleSize
        let position = CameraStyle.position
        let current = panel.frame.insetBy(dx: halo, dy: halo)
        let bubble: CGRect
        if reposition || position != appliedPosition {
            bubble = CameraStyle.frame(in: area, size: size, position: position)
        } else if current.size != size {
            bubble = CameraStyle.resized(current, to: size, in: area)
        } else {
            bubble = CameraStyle.clamped(current, in: area)
        }
        appliedPosition = position
        if bubble != current { panel.setFrame(bubble.insetBy(dx: -halo, dy: -halo), display: true) }
        view.apply(shape: CameraStyle.shape, border: CameraStyle.border, mirror: CameraStyle.mirror)
    }

    enum CameraError: LocalizedError {
        case notAllowed
        var errorDescription: String? {
            "Marquee isn't allowed to use the camera. Allow it in System Settings → Privacy & Security → Camera."
        }
    }
}

/// The live camera image clipped to the bubble's shape, with its ring, and a soft shadow or a
/// colored glow drawn in the transparent room around it.
private final class CameraBubbleView: NSView {
    private let glowLayer = CAShapeLayer()
    private let clipLayer = CALayer()
    private let preview: AVCaptureVideoPreviewLayer
    private let ringLayer = CAShapeLayer()
    private let rainbowLayer = CAGradientLayer()
    private let rainbowMask = CAShapeLayer()

    init(session: AVCaptureSession) {
        preview = AVCaptureVideoPreviewLayer(session: session)
        super.init(frame: .zero)
        wantsLayer = true
        layer?.masksToBounds = false
        // Shadow or glow: a filled shape the size of the bubble whose shadow shows around it.
        glowLayer.fillColor = NSColor.black.cgColor
        glowLayer.shadowOffset = .zero
        layer?.addSublayer(glowLayer)
        clipLayer.masksToBounds = true
        preview.videoGravity = .resizeAspectFill
        clipLayer.addSublayer(preview)
        layer?.addSublayer(clipLayer)
        ringLayer.fillColor = nil
        layer?.addSublayer(ringLayer)
        rainbowLayer.type = .conic
        rainbowLayer.startPoint = CGPoint(x: 0.5, y: 0.5)
        rainbowLayer.endPoint = CGPoint(x: 0.5, y: 0)
        rainbowLayer.colors = CameraStyle.Border.rainbowColors.map(\.cgColor)
        rainbowMask.fillColor = nil
        rainbowMask.strokeColor = NSColor.black.cgColor
        rainbowLayer.mask = rainbowMask
        layer?.addSublayer(rainbowLayer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    // Dragging the bubble moves it.
    override var mouseDownCanMoveWindow: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    private var shape: CameraStyle.Shape = .circle
    private var border: CameraStyle.Border = .white

    func apply(shape: CameraStyle.Shape, border: CameraStyle.Border, mirror: Bool) {
        self.shape = shape
        self.border = border
        if let connection = preview.connection, connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = mirror
        }
        needsLayout = true
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let bubble = bounds.insetBy(dx: CameraStyle.halo, dy: CameraStyle.halo)
        let radius = shape.cornerRadius(for: bubble.size)
        let bubblePath = CGPath(roundedRect: bubble, cornerWidth: radius, cornerHeight: radius, transform: nil)

        glowLayer.frame = bounds
        glowLayer.path = bubblePath
        glowLayer.shadowPath = bubblePath
        if border.glows, let color = border.color {
            glowLayer.shadowColor = color.cgColor
            glowLayer.shadowOpacity = 0.95
            glowLayer.shadowRadius = 14
        } else {
            glowLayer.shadowColor = NSColor.black.cgColor
            glowLayer.shadowOpacity = 0.35
            glowLayer.shadowRadius = 8
        }

        clipLayer.frame = bubble
        clipLayer.cornerRadius = radius
        clipLayer.cornerCurve = .continuous
        preview.frame = clipLayer.bounds

        let lineWidth = border.lineWidth
        let ring = bubble.insetBy(dx: lineWidth / 2, dy: lineWidth / 2)
        let ringRadius = max(0, radius - lineWidth / 2)
        let ringPath = CGPath(roundedRect: ring, cornerWidth: ringRadius, cornerHeight: ringRadius, transform: nil)
        let rainbow = border == .rainbow
        ringLayer.frame = bounds
        ringLayer.path = ringPath
        ringLayer.lineWidth = lineWidth
        ringLayer.strokeColor = rainbow ? nil : border.color?.cgColor
        rainbowLayer.isHidden = !rainbow
        rainbowLayer.frame = bounds
        rainbowMask.frame = bounds
        rainbowMask.path = ringPath
        rainbowMask.lineWidth = lineWidth
        CATransaction.commit()
    }
}
