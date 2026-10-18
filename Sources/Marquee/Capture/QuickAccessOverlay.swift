import AppKit
import SwiftUI

/// The floating thumbnail that appears in the corner after every capture
/// (CleanShot calls it the "Quick Access Overlay"). Several can stack up.
@MainActor
final class QuickAccessManager {
    static let shared = QuickAccessManager()

    private var panels: [(capture: Capture, panel: NSPanel)] = []
    private var editors: [AnnotationWindowController] = []

    private static let width: CGFloat = 260
    private let margin: CGFloat = 18
    private let spacing: CGFloat = 12

    /// The panel follows the capture's shape: 260 pt wide, between 130 and 230 pt tall.
    private static func size(for capture: Capture) -> NSSize {
        let image = capture.image.size
        let aspect = image.height > 0 ? image.width / image.height : 16.0 / 10
        return NSSize(width: width, height: min(230, max(130, width / aspect)))
    }

    func show(_ capture: Capture) {
        let size = Self.size(for: capture)
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false
        )
        panel.isReleasedWhenClosed = false
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = NSHostingView(rootView: QuickAccessView(capture: capture, size: size) { [weak self] action in
            self?.perform(action, on: capture)
        })

        panels.append((capture, panel))
        layout()
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { $0.duration = 0.18; panel.animator().alphaValue = 1 }

        let timeout = Preferences.overlayTimeout
        if timeout > 0 {
            runAfter(Double(timeout)) { [weak self] in
                self?.dismiss(capture)
            }
        }
    }

    func dismiss(_ capture: Capture) {
        guard let index = panels.firstIndex(where: { $0.capture === capture }) else { return }
        let panel = panels.remove(at: index).panel
        NSAnimationContext.runAnimationGroup({ $0.duration = 0.15; panel.animator().alphaValue = 0 }) {
            Task { @MainActor in panel.orderOut(nil) }
        }
        layout()
    }

    private func layout() {
        let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }
            ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return }
        var y = visible.minY + margin
        for entry in panels.reversed() {
            let size = entry.panel.frame.size
            entry.panel.setFrame(NSRect(origin: NSPoint(x: visible.minX + margin, y: y), size: size),
                                 display: true, animate: true)
            y += size.height + spacing
        }
    }

    private func perform(_ action: QuickAccessAction, on capture: Capture) {
        switch action {
        case .copy:
            capture.copyToPasteboard()
            Sounds.play(.copy)
            Toast.show("Copied to clipboard")
            dismiss(capture)
        case .save:
            if let url = capture.save() {
                Toast.show("Saved to \(url.deletingLastPathComponent().lastPathComponent)")
            }
            dismiss(capture)
        case .annotate:
            openEditor(for: capture)
        case .pin:
            PinnedImageWindow.pin(capture.image)
            dismiss(capture)
        case .open:
            NSWorkspace.shared.open(capture.url)
        case .editVideo:
            VideoEditorController.edit(capture.url)
            dismiss(capture)
        case .saveGIF:
            exportGIF(capture)
        case .close:
            dismiss(capture)
        }
    }

    private func exportGIF(_ capture: Capture) {
        let folder = Preferences.saveFolder
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let dest = Capture.uniqueURL(in: folder, date: capture.date, ext: "gif")
        let source = capture.url
        Toast.show("Creating GIF…", duration: 30)
        Task {
            do {
                try await VideoTools.exportGIF(from: source, to: dest)
                Toast.show("Saved \(dest.lastPathComponent)")
                NSWorkspace.shared.activateFileViewerSelecting([dest])
            } catch {
                Toast.show(error.localizedDescription)
            }
        }
    }

    func openEditor(for capture: Capture) {
        let editor = AnnotationWindowController(image: capture.image) { [weak capture] edited in
            capture?.update(image: edited)
        }
        editor.onClose = { [weak self, weak editor] in
            self?.editors.removeAll { $0 === editor }
        }
        editors.append(editor)
        editor.present()
    }
}

enum QuickAccessAction {
    case copy, save, annotate, pin, open, saveGIF, editVideo, close
}

/// The capture as a thumbnail. Hovering dims it and shows the actions around it: close and
/// pin (or GIF) in the top corners, save and annotate (or open) in the bottom corners, and
/// Copy in the middle. Drag the thumbnail into any app.
@MainActor
struct QuickAccessView: View {
    @ObservedObject var capture: Capture
    let size: NSSize
    var onAction: (QuickAccessAction) -> Void
    @State private var hovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)

    var body: some View {
        ZStack {
            Image(nsImage: capture.image)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fill)
                .frame(width: size.width, height: size.height)
                .clipped()
                .onDrag { NSItemProvider(contentsOf: capture.url) ?? NSItemProvider() }
                .accessibilityLabel(capture.isVideo ? "Recording" : "Screenshot")

            // Dims the image so the controls read on any capture.
            LinearGradient(colors: [.black.opacity(0.45), .black.opacity(0.25), .black.opacity(0.5)],
                           startPoint: .top, endPoint: .bottom)
                .opacity(hovering ? 1 : 0)
                .allowsHitTesting(false)

            if capture.isVideo && !hovering {
                Image(systemName: "play.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .hudSurface(cornerRadius: 19)
                    .allowsHitTesting(false)
            }

            if hovering {
                Button { onAction(.copy) } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .frame(height: 34)
                        .hudSurface(cornerRadius: 17)
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .help("Copy to clipboard")
                .transition(.opacity.combined(with: .scale(scale: 0.9)))
            }

            VStack {
                HStack {
                    CornerButton(symbol: "xmark", help: "Close") { onAction(.close) }
                        .opacity(hovering ? 1 : 0.85)
                    Spacer()
                    if hovering {
                        if capture.isVideo {
                            CornerButton(symbol: "photo.stack", help: "Save as GIF") { onAction(.saveGIF) }
                        } else {
                            CornerButton(symbol: "pin", help: "Pin to screen") { onAction(.pin) }
                        }
                    }
                }
                Spacer()
                if hovering {
                    HStack {
                        CornerButton(symbol: "square.and.arrow.down", help: "Save") { onAction(.save) }
                        Spacer()
                        if capture.isVideo {
                            CornerButton(symbol: "scissors", help: "Edit: trim, mute, export") { onAction(.editVideo) }
                        } else {
                            CornerButton(symbol: "pencil.tip.crop.circle", help: "Annotate") { onAction(.annotate) }
                        }
                    }
                }
            }
            .padding(8)
            .transition(.opacity)
        }
        .frame(width: size.width, height: size.height)
        .clipShape(shape)
        .overlay(shape.strokeBorder(.white.opacity(0.55), lineWidth: 1.5))
        .overlay(shape.strokeBorder(.black.opacity(0.18), lineWidth: 0.5))
        .contentShape(shape)
        .onHover { inside in
            if reduceMotion {
                hovering = inside
            } else {
                withAnimation(.easeOut(duration: 0.15)) { hovering = inside }
            }
        }
        .accessibilityElement(children: .contain)
    }
}

/// A round dark-glass button for a corner of the Quick Access thumbnail.
private struct CornerButton: View {
    let symbol: String
    let help: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .hudSurface(cornerRadius: 15)
                .scaleEffect(hovering ? 1.08 : 1)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
        .help(help)
        .accessibilityLabel(help)
    }
}
