import AppKit
import CoreImage
import SwiftUI

enum AnnotationTool: String, CaseIterable, Identifiable {
    case select, arrow, rectangle, ellipse, pen, highlight, text, counter, pixelate

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .select: return "cursorarrow"
        case .arrow: return "arrow.up.right"
        case .rectangle: return "rectangle"
        case .ellipse: return "circle"
        case .pen: return "scribble"
        case .highlight: return "highlighter"
        case .text: return "textformat"
        case .counter: return "1.circle"
        case .pixelate: return "mosaic"
        }
    }

    var title: String {
        switch self {
        case .select: return "Select and move"
        case .arrow: return "Arrow"
        case .rectangle: return "Rectangle"
        case .ellipse: return "Ellipse"
        case .pen: return "Pen"
        case .highlight: return "Highlight"
        case .text: return "Text"
        case .counter: return "Step counter"
        case .pixelate: return "Redact (hide sensitive info)"
        }
    }
}

/// How the redact tool hides what's under it.
enum RedactStyle: String, CaseIterable, Identifiable {
    case pixelate, blur, solid
    var id: String { rawValue }

    var title: String {
        switch self {
        case .pixelate: return "Pixelate"
        case .blur: return "Smooth Blur"
        case .solid: return "Secure"
        }
    }

    var help: String {
        switch self {
        case .pixelate: return "Pixelate: blocky, the classic look"
        case .blur: return "Smooth blur: soft and unobtrusive"
        case .solid: return "Secure: a solid block, nothing can be recovered from it"
        }
    }

    var symbol: String {
        switch self {
        case .pixelate: return "mosaic"
        case .blur: return "drop"
        case .solid: return "rectangle.fill"
        }
    }
}

/// A single shape. Points are in image coordinates (points, top-left origin).
struct Annotation: Identifiable, Equatable {
    let id = UUID()
    var tool: AnnotationTool
    var color: Color
    var lineWidth: CGFloat
    var points: [CGPoint]
    var text: String = ""
    var number: Int = 0
    var redact: RedactStyle = .pixelate

    var rect: CGRect {
        guard let a = points.first, let b = points.last else { return .zero }
        return CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y))
    }

    /// Shapes defined by a box, which can be resized from their corners.
    var isBoxShaped: Bool { [.rectangle, .ellipse, .highlight, .pixelate].contains(tool) }

    /// The area it covers, for selecting and outlining it.
    var bounds: CGRect {
        switch tool {
        case .pen, .arrow:
            let xs = points.map(\.x), ys = points.map(\.y)
            guard let minX = xs.min(), let maxX = xs.max(), let minY = ys.min(), let maxY = ys.max() else { return .zero }
            return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
        case .text:
            guard let p = points.first else { return .zero }
            let size = 10 + lineWidth * 3
            return CGRect(x: p.x, y: p.y, width: max(size, CGFloat(text.count) * size * 0.6), height: size * 1.3)
        case .counter:
            guard let p = points.first else { return .zero }
            let r = 10 + lineWidth * 1.5
            return CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)
        default:
            return rect
        }
    }

    mutating func move(by delta: CGSize) {
        points = points.map { CGPoint(x: $0.x + delta.width, y: $0.y + delta.height) }
    }
}

/// Draws annotations into a SwiftUI GraphicsContext. Used both for the live
/// editor canvas and for the final export so they always match.
enum AnnotationRenderer {
    /// Fully pixelated and blurred copies of the image; redactions reveal them through a clip.
    struct Hidden {
        let pixelated: Image
        let blurred: Image
    }

    static func draw(_ annotations: [Annotation], in ctx: GraphicsContext, imageSize: CGSize, hidden: Hidden) {
        for a in annotations {
            draw(a, in: ctx, imageSize: imageSize, hidden: hidden)
        }
    }

    static func draw(_ a: Annotation, in ctx: GraphicsContext, imageSize: CGSize, hidden: Hidden) {
        let shading = GraphicsContext.Shading.color(a.color)
        let stroke = StrokeStyle(lineWidth: a.lineWidth, lineCap: .round, lineJoin: .round)

        switch a.tool {
        case .pen:
            var path = Path()
            path.addLines(a.points)
            ctx.stroke(path, with: shading, style: stroke)

        case .rectangle:
            ctx.stroke(Path(roundedRect: a.rect, cornerRadius: 3), with: shading, style: stroke)

        case .ellipse:
            ctx.stroke(Path(ellipseIn: a.rect), with: shading, style: stroke)

        case .highlight:
            ctx.fill(Path(a.rect), with: .color(a.color.opacity(0.35)))

        case .arrow:
            guard let s = a.points.first, let e = a.points.last else { return }
            let angle = atan2(e.y - s.y, e.x - s.x)
            let head = max(14, a.lineWidth * 4)
            // Stop the shaft inside the head so the tip stays sharp.
            let shaftEnd = CGPoint(x: e.x - cos(angle) * head * 0.6, y: e.y - sin(angle) * head * 0.6)
            var shaft = Path()
            shaft.move(to: s)
            shaft.addLine(to: shaftEnd)
            ctx.stroke(shaft, with: shading, style: stroke)

            var tip = Path()
            tip.move(to: e)
            tip.addLine(to: CGPoint(x: e.x - head * cos(angle - .pi / 7), y: e.y - head * sin(angle - .pi / 7)))
            tip.addLine(to: CGPoint(x: e.x - head * cos(angle + .pi / 7), y: e.y - head * sin(angle + .pi / 7)))
            tip.closeSubpath()
            ctx.fill(tip, with: shading)

        case .text:
            guard let p = a.points.first else { return }
            let text = Text(a.text)
                .font(.system(size: 10 + a.lineWidth * 3, weight: .semibold))
                .foregroundColor(a.color)
            ctx.draw(text, at: p, anchor: .topLeading)

        case .counter:
            guard let p = a.points.first else { return }
            let r = 10 + a.lineWidth * 1.5
            ctx.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)), with: shading)
            let label = Text("\(a.number)")
                .font(.system(size: r, weight: .bold))
                .foregroundColor(.white)
            ctx.draw(label, at: p, anchor: .center)

        case .pixelate:
            switch a.redact {
            case .solid:
                ctx.fill(Path(roundedRect: a.rect, cornerRadius: 2), with: .color(Color(red: 0.11, green: 0.11, blue: 0.12)))
            case .pixelate, .blur:
                var clipped = ctx
                clipped.clip(to: Path(a.rect))
                clipped.draw(a.redact == .blur ? hidden.blurred : hidden.pixelated, in: CGRect(origin: .zero, size: imageSize))
            }

        case .select:
            break
        }
    }

    /// A softly blurred copy of the image for smooth-blur redactions.
    static func blur(_ image: NSImage) -> NSImage {
        guard let tiff = image.tiffRepresentation, let input = CIImage(data: tiff),
              let filter = CIFilter(name: "CIGaussianBlur") else { return image }
        filter.setValue(input.clampedToExtent(), forKey: kCIInputImageKey)
        filter.setValue(max(10, input.extent.width / 90), forKey: kCIInputRadiusKey)
        guard let output = filter.outputImage?.cropped(to: input.extent),
              let cg = CIContext().createCGImage(output, from: input.extent) else { return image }
        return NSImage(cgImage: cg, size: image.size)
    }

    /// A fully pixelated copy of the image; the pixelate tool reveals it through a clip.
    static func pixelate(_ image: NSImage) -> NSImage {
        guard let tiff = image.tiffRepresentation, let input = CIImage(data: tiff),
              let filter = CIFilter(name: "CIPixellate") else { return image }
        filter.setValue(input.clampedToExtent(), forKey: kCIInputImageKey)
        filter.setValue(max(12, input.extent.width / 70), forKey: kCIInputScaleKey)
        guard let output = filter.outputImage?.cropped(to: input.extent),
              let cg = CIContext().createCGImage(output, from: input.extent) else { return image }
        return NSImage(cgImage: cg, size: image.size)
    }
}
