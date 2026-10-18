import AppKit

/// One screenshot or screen recording that is alive in the Quick Access overlay / editor.
@MainActor
final class Capture: ObservableObject, Identifiable {
    enum Kind {
        case image
        case video
    }

    let id = UUID()
    let kind: Kind
    let url: URL
    let date = Date()
    /// The screenshot itself, or a poster frame for videos.
    @Published private(set) var image: NSImage

    init(url: URL, image: NSImage, kind: Kind = .image) {
        self.url = url
        self.image = image
        self.kind = kind
    }

    var isVideo: Bool { kind == .video }

    /// Replace the image (e.g. after annotating) and keep the temp file in sync so
    /// drag & drop hands out the edited version.
    func update(image: NSImage) {
        self.image = image
        if let data = image.pngData {
            try? data.write(to: url, options: .atomic)
        }
    }

    func copyToPasteboard() {
        switch kind {
        case .image:
            image.copyToPasteboard()
        case .video:
            // Copy the file itself, so pasting into Finder, Slack, Mail... attaches the video.
            let pb = NSPasteboard.general
            pb.clearContents()
            pb.writeObjects([url as NSURL])
        }
    }

    /// Saves into the configured screenshots folder and returns the destination.
    @discardableResult
    func save() -> URL? {
        let folder = Preferences.saveFolder
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let ext = isVideo ? "mp4" : "png"
        let dest = Capture.uniqueURL(in: folder, date: date, ext: ext)
        do {
            if isVideo {
                try FileManager.default.copyItem(at: url, to: dest)
            } else {
                guard let data = image.pngData else { return nil }
                try data.write(to: dest, options: .atomic)
            }
            return dest
        } catch {
            NSLog("Marquee: save failed: \(error)")
            return nil
        }
    }

    nonisolated static func fileName(for date: Date, suffix: String = "", ext: String = "png") -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        let prefix: String
        switch ext {
        case "png": prefix = "Marquee"
        case "m4a": prefix = "Marquee Voice"
        default: prefix = "Marquee Recording"
        }
        return "\(prefix) \(f.string(from: date))\(suffix).\(ext)"
    }

    /// A file URL in `folder` that does not exist yet ("… (2).png" etc.).
    static func uniqueURL(in folder: URL, date: Date, ext: String) -> URL {
        var dest = folder.appendingPathComponent(fileName(for: date, ext: ext))
        var n = 2
        while FileManager.default.fileExists(atPath: dest.path) {
            dest = folder.appendingPathComponent(fileName(for: date, suffix: " (\(n))", ext: ext))
            n += 1
        }
        return dest
    }
}

extension NSImage {
    var pngData: Data? {
        guard let tiff = tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }

    /// Ratio between pixels and points (2 on Retina screenshots).
    var pixelScale: CGFloat {
        guard size.width > 0, let rep = representations.first, rep.pixelsWide > 0 else { return 1 }
        return max(1, CGFloat(rep.pixelsWide) / size.width)
    }

    func copyToPasteboard() {
        let pb = NSPasteboard.general
        pb.clearContents()
        if let png = pngData { pb.setData(png, forType: .png) }
        if let tiff = tiffRepresentation { pb.setData(tiff, forType: .tiff) }
    }
}
