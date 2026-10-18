import CoreGraphics
import Foundation

/// Text shown on top of a recording.
struct TextOverlay: Identifiable, Equatable {
    enum Position: String, CaseIterable, Identifiable {
        case top, middle, bottom
        var id: String { rawValue }
        var title: String { rawValue.capitalized }
    }

    enum Style: String, CaseIterable, Identifiable {
        /// White text on a dark rounded box, like a subtitle.
        case caption
        /// Large white text with a shadow.
        case bold
        /// Dark text on Marquee yellow.
        case highlight
        var id: String { rawValue }
        var title: String { rawValue.capitalized }
    }

    var id = UUID()
    var text: String
    var position: Position = .bottom
    var style: Style = .caption
    /// When it shows, in seconds of the original recording; nil means the whole video.
    var start: Double?
    var end: Double?
    /// Where its middle sits after dragging, as a fraction of the video (0…1, from the top
    /// left), so it lands in the same spot at any export size. Nil uses `position`.
    var center: CGPoint?
    /// Hidden layers stay in the editor but aren't exported.
    var hidden = false

    var isWholeVideo: Bool { start == nil || end == nil }

    func isVisible(at time: Double) -> Bool {
        guard !hidden else { return false }
        guard let start, let end else { return true }
        return time >= start && time < end
    }

    /// Bottom-left corner of a `box`-sized overlay inside a video of `size` (origin bottom
    /// left, as layers use), kept fully inside the video.
    func origin(for box: CGSize, in size: CGSize) -> CGPoint {
        let margin = size.height * 0.07
        var x = (size.width - box.width) / 2
        var y: CGFloat
        if let center {
            x = center.x * size.width - box.width / 2
            y = (1 - center.y) * size.height - box.height / 2
        } else {
            switch position {
            case .top: y = size.height - margin - box.height
            case .middle: y = (size.height - box.height) / 2
            case .bottom: y = margin
            }
        }
        x = min(max(0, x), max(0, size.width - box.width))
        y = min(max(0, y), max(0, size.height - box.height))
        return CGPoint(x: x, y: y)
    }
}

/// The edits made to a recording: a trimmed start and end, sections cut out of the middle,
/// and text on top. Times are seconds of the original recording. Pure value logic, unit tested.
struct VideoEdit: Equatable {
    var duration: Double
    /// The part kept by trimming; nil keeps the whole recording.
    var trim: ClosedRange<Double>?
    /// Sections cut out, sorted and never overlapping.
    private(set) var removed: [ClosedRange<Double>] = []
    var texts: [TextOverlay] = []

    /// Pieces shorter than this are dropped rather than exported as a few stray frames.
    private static let minimumPiece = 0.05

    var isEmpty: Bool { trim == nil && removed.isEmpty && texts.isEmpty }

    /// Cuts the section between two marks (in either order) out of the recording, merging it
    /// with cuts it touches.
    mutating func remove(from a: Double, to b: Double) {
        let lower = max(0, min(a, b))
        let upper = min(duration, max(a, b))
        guard upper - lower >= Self.minimumPiece else { return }
        var merged = lower...upper
        var others: [ClosedRange<Double>] = []
        for cut in removed {
            if cut.upperBound >= merged.lowerBound && cut.lowerBound <= merged.upperBound {
                merged = min(cut.lowerBound, merged.lowerBound)...max(cut.upperBound, merged.upperBound)
            } else {
                others.append(cut)
            }
        }
        removed = (others + [merged]).sorted { $0.lowerBound < $1.lowerBound }
    }

    mutating func restore(_ range: ClosedRange<Double>) {
        removed.removeAll { $0 == range }
    }

    /// The parts that end up in the video, in order.
    var keptSegments: [ClosedRange<Double>] {
        let bounds = trim ?? 0...duration
        var pieces: [ClosedRange<Double>] = []
        var cursor = bounds.lowerBound
        for cut in removed where cut.upperBound > bounds.lowerBound && cut.lowerBound < bounds.upperBound {
            if cut.lowerBound - cursor >= Self.minimumPiece { pieces.append(cursor...cut.lowerBound) }
            cursor = max(cursor, cut.upperBound)
        }
        if bounds.upperBound - cursor >= Self.minimumPiece { pieces.append(cursor...bounds.upperBound) }
        return pieces
    }

    var keptDuration: Double { keptSegments.reduce(0) { $0 + ($1.upperBound - $1.lowerBound) } }

    /// Where a moment of the original lands in the edited video. Moments that were cut map to
    /// where the cut was, so text keeps its timing around cuts.
    func editedTime(for time: Double) -> Double {
        var total = 0.0
        for piece in keptSegments {
            if time <= piece.lowerBound { return total }
            if time < piece.upperBound { return total + (time - piece.lowerBound) }
            total += piece.upperBound - piece.lowerBound
        }
        return total
    }

    /// The cut containing `time`, for skipping it while previewing.
    func cut(containing time: Double) -> ClosedRange<Double>? {
        removed.first { time >= $0.lowerBound && time < $0.upperBound }
    }
}
