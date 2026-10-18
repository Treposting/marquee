import AppKit
import SwiftUI

@MainActor
final class AnnotationDocument: ObservableObject {
    let baseImage: NSImage
    let pixelated: NSImage
    let blurred: NSImage

    @Published var annotations: [Annotation] = []
    @Published var current: Annotation?
    @Published var tool: AnnotationTool = .arrow {
        didSet { if tool != .select && tool != .pixelate { selectedID = nil } }
    }
    @Published var color: Color = .red
    @Published var lineWidth: CGFloat = 5
    @Published var redactStyle: RedactStyle = .pixelate {
        didSet { restyleSelectedRedaction() }
    }
    /// The shape picked with the select tool (or a redaction picked with the redact tool).
    @Published var selectedID: UUID?
    @Published private var undoStack: [[Annotation]] = []
    @Published private var redoStack: [[Annotation]] = []

    /// What the current drag is doing.
    private enum Interaction {
        /// Pressed on empty space with the select tool: nothing to do.
        case idle
        case draw
        case move(id: UUID, original: Annotation, from: CGPoint)
        case resize(id: UUID, anchor: CGPoint)
    }
    private var interaction: Interaction?

    init(image: NSImage) {
        baseImage = image
        pixelated = AnnotationRenderer.pixelate(image)
        blurred = AnnotationRenderer.blur(image)
    }

    var size: CGSize { baseImage.size }
    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }
    var selected: Annotation? { annotations.first { $0.id == selectedID } }

    /// Everything that should be drawn right now, including the shape being dragged.
    var visibleAnnotations: [Annotation] {
        current.map { annotations + [$0] } ?? annotations
    }

    var hidden: AnnotationRenderer.Hidden {
        AnnotationRenderer.Hidden(pixelated: Image(nsImage: pixelated), blurred: Image(nsImage: blurred))
    }

    // MARK: - Gestures (image coordinates)

    func dragChanged(from start: CGPoint, to location: CGPoint) {
        if interaction == nil { interaction = beginInteraction(at: start) }
        switch interaction {
        case .move(let id, let original, let from)?:
            var moved = original
            moved.move(by: CGSize(width: location.x - from.x, height: location.y - from.y))
            replace(id, with: moved)
        case .resize(let id, let anchor)?:
            guard var shape = annotations.first(where: { $0.id == id }) else { return }
            shape.points = [anchor, location]
            replace(id, with: shape)
        case .draw?, nil:
            draw(from: start, to: location)
        case .idle?:
            return
        }
    }

    func dragEnded(at location: CGPoint) {
        defer { interaction = nil }
        switch interaction {
        case .move?, .resize?, .idle?:
            return
        default:
            break
        }
        switch tool {
        case .select:
            return
        case .counter:
            let next = (annotations.filter { $0.tool == .counter }.map(\.number).max() ?? 0) + 1
            append(Annotation(tool: .counter, color: color, lineWidth: lineWidth, points: [location], number: next))
        case .text:
            // Run the modal prompt outside the gesture callback.
            runAfter(0) { [weak self] in
                guard let self, let text = Self.promptForText() else { return }
                self.append(Annotation(tool: .text, color: self.color, lineWidth: self.lineWidth,
                                       points: [location], text: text))
            }
        default:
            if let shape = current, shape.rect.width > 2 || shape.rect.height > 2 || shape.tool == .pen {
                append(shape)
                if shape.tool == .pixelate { selectedID = shape.id }
            }
            current = nil
        }
    }

    /// The select tool picks up any shape; the redact tool picks up redactions, so they can be
    /// moved or resized after they're placed. Corners of box shapes resize them.
    private func beginInteraction(at point: CGPoint) -> Interaction {
        guard tool == .select || tool == .pixelate else { return .draw }
        let candidates = annotations.reversed().filter { tool == .select || $0.tool == .pixelate }
        let reach: CGFloat = max(8, min(size.width, size.height) * 0.012)
        if let shape = candidates.first(where: { $0.isBoxShaped && Self.corner(of: $0.rect, near: point, within: reach) != nil }),
           let corner = Self.corner(of: shape.rect, near: point, within: reach) {
            snapshot()
            selectedID = shape.id
            let r = shape.rect
            // The opposite corner stays put.
            let anchor = CGPoint(x: corner.x == r.minX ? r.maxX : r.minX, y: corner.y == r.minY ? r.maxY : r.minY)
            return .resize(id: shape.id, anchor: anchor)
        }
        if let shape = candidates.first(where: { $0.bounds.insetBy(dx: -reach, dy: -reach).contains(point) }) {
            snapshot()
            selectedID = shape.id
            return .move(id: shape.id, original: shape, from: point)
        }
        selectedID = nil
        return tool == .select ? .idle : .draw
    }

    private static func corner(of rect: CGRect, near point: CGPoint, within reach: CGFloat) -> CGPoint? {
        let corners = [CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.minY),
                       CGPoint(x: rect.minX, y: rect.maxY), CGPoint(x: rect.maxX, y: rect.maxY)]
        return corners.first { hypot($0.x - point.x, $0.y - point.y) <= reach }
    }

    private func draw(from start: CGPoint, to location: CGPoint) {
        switch tool {
        case .text, .counter, .select:
            return
        case .pen:
            if current == nil {
                current = Annotation(tool: tool, color: color, lineWidth: lineWidth, points: [start])
            }
            current?.points.append(location)
        default:
            current = Annotation(tool: tool, color: color, lineWidth: lineWidth, points: [start, location], redact: redactStyle)
        }
    }

    /// Changing the redact style restyles the selected redaction too.
    private func restyleSelectedRedaction() {
        guard let shape = selected, shape.tool == .pixelate, shape.redact != redactStyle else { return }
        snapshot()
        var restyled = shape
        restyled.redact = redactStyle
        replace(shape.id, with: restyled)
    }

    func deleteSelected() {
        guard let selectedID else { return }
        snapshot()
        annotations.removeAll { $0.id == selectedID }
        self.selectedID = nil
    }

    private func replace(_ id: UUID, with shape: Annotation) {
        guard let index = annotations.firstIndex(where: { $0.id == id }) else { return }
        annotations[index] = shape
    }

    private func append(_ a: Annotation) {
        snapshot()
        annotations.append(a)
    }

    // MARK: - Undo (whole snapshots, so moves and deletes undo too)

    private func snapshot() {
        undoStack.append(annotations)
        redoStack.removeAll()
    }

    func undo() {
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(annotations)
        annotations = previous
        selectedID = nil
    }

    func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(annotations)
        annotations = next
        selectedID = nil
    }

    // MARK: - Export

    func render() -> NSImage {
        let size = self.size
        let base = baseImage
        let hidden = self.hidden
        let annotations = self.annotations
        let view = Canvas { ctx, _ in
            ctx.draw(Image(nsImage: base), in: CGRect(origin: .zero, size: size))
            AnnotationRenderer.draw(annotations, in: ctx, imageSize: size, hidden: hidden)
        }
        .frame(width: size.width, height: size.height)

        let renderer = ImageRenderer(content: view)
        renderer.scale = base.pixelScale
        guard let output = renderer.nsImage else { return base }
        return output
    }

    private static func promptForText() -> String? {
        let alert = NSAlert()
        alert.messageText = "Add Text"
        alert.addButton(withTitle: "Add")
        alert.addButton(withTitle: "Cancel")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        let text = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }
}
