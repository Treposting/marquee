import AppKit
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class AnnotationWindowController: NSObject, NSWindowDelegate {
    private let document: AnnotationDocument
    private let onDone: (NSImage) -> Void
    private var window: NSWindow?
    var onClose: (() -> Void)?

    init(image: NSImage, onDone: @escaping (NSImage) -> Void) {
        self.document = AnnotationDocument(image: image)
        self.onDone = onDone
        super.init()
    }

    func present() {
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let width = min(max(document.size.width + 80, 940), screen.width * 0.88)
        let height = min(max(document.size.height + 150, 560), screen.height * 0.88)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: width, height: height),
            styleMask: [.titled, .closable, .resizable, .miniaturizable, .fullSizeContentView],
            backing: .buffered, defer: false
        )
        window.title = "Annotate"
        // The floating glass toolbar takes the place of a title bar.
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.minSize = NSSize(width: 940, height: 520)
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentViewController = NSHostingController(rootView: AnnotationEditorView(
            document: document,
            onCopy: { [weak self] in self?.copy() },
            onSave: { [weak self] in self?.saveAs() },
            onDone: { [weak self] in self?.finish() }
        ))
        window.setContentSize(NSSize(width: width, height: height))
        window.center()
        self.window = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func copy() {
        let image = document.render()
        image.copyToPasteboard()
        onDone(image)
        Sounds.play(.copy)
        Toast.show("Copied to clipboard")
    }

    private func saveAs() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = Capture.fileName(for: Date())
        panel.directoryURL = Preferences.saveFolder
        guard let window else { return }
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK else { return }
            Task { @MainActor in
                guard let self, let url = panel.url else { return }
                let image = self.document.render()
                try? image.pngData?.write(to: url, options: .atomic)
                self.onDone(image)
            }
        }
    }

    private func finish() {
        onDone(document.render())
        window?.close()
    }

    func windowWillClose(_ notification: Notification) {
        onClose?()
    }
}

@MainActor
struct AnnotationEditorView: View {
    @ObservedObject var document: AnnotationDocument
    var onCopy: () -> Void
    var onSave: () -> Void
    var onDone: () -> Void

    private struct Swatch: Identifiable {
        let name: String
        let color: Color
        var id: String { name }
    }

    private static let swatches: [Swatch] = [
        Swatch(name: "Red", color: .red), Swatch(name: "Orange", color: .orange),
        Swatch(name: "Yellow", color: .yellow), Swatch(name: "Green", color: .green),
        Swatch(name: "Blue", color: .blue), Swatch(name: "Purple", color: .purple),
        Swatch(name: "Black", color: .black), Swatch(name: "White", color: .white),
    ]

    /// Stroke sizes offered as three dots.
    private static let widths: [CGFloat] = [3, 6, 11]

    /// Room above the canvas for the floating toolbar.
    private static let toolbarClearance: CGFloat = 72

    var body: some View {
        // The canvas fills the window; the controls float over it on glass, as in macOS 26/27.
        ZStack(alignment: .top) {
            GeometryReader { geo in
                let size = document.size
                let available = CGSize(width: geo.size.width - 64, height: geo.size.height - Self.toolbarClearance - 64)
                let scale = max(min(1, available.width / size.width, available.height / size.height), 0.05)
                ZStack {
                    canvas(scale: scale)
                        .frame(width: size.width * scale, height: size.height * scale)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(.black.opacity(0.12)))
                        .shadow(color: .black.opacity(0.22), radius: 18, y: 6)
                        .position(x: geo.size.width / 2,
                                  y: Self.toolbarClearance + (geo.size.height - Self.toolbarClearance - 40) / 2)

                    Text("\(Int(size.width)) × \(Int(size.height))  ·  \(Int((scale * 100).rounded()))%")
                        .font(.system(size: 11, weight: .medium).monospacedDigit())
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 12)
                        .frame(height: 24)
                        .glassSurface(Capsule())
                        .position(x: geo.size.width / 2, y: geo.size.height - 22)
                        .accessibilityLabel("Image \(Int(size.width)) by \(Int(size.height)), shown at \(Int((scale * 100).rounded())) percent")
                }
            }
            .background(
                LinearGradient(colors: [Color(nsColor: .underPageBackgroundColor), Color(nsColor: .windowBackgroundColor)],
                               startPoint: .top, endPoint: .bottom)
            )

            HStack(alignment: .center, spacing: 12) {
                // Room for the window's close, minimize and zoom buttons.
                Color.clear.frame(width: 64, height: 1)
                Spacer(minLength: 0)
                tools
                Spacer(minLength: 0)
                actions
            }
            .padding(.top, 12)
            .padding(.horizontal, 14)
        }
        .frame(minWidth: 940, minHeight: 520)
    }

    /// Tools, colors, stroke sizes and undo, on one glass capsule.
    private var tools: some View {
        HStack(spacing: 10) {
            HStack(spacing: 2) {
                ForEach(AnnotationTool.allCases) { tool in
                    ToolButton(tool: tool, selected: document.tool == tool) { document.tool = tool }
                }
            }
            divider
            HStack(spacing: 5) {
                ForEach(Self.swatches) { swatch in
                    Button { document.color = swatch.color } label: {
                        Circle()
                            .fill(swatch.color)
                            .frame(width: 16, height: 16)
                            .overlay(Circle().strokeBorder(.black.opacity(0.18), lineWidth: 0.5))
                            .padding(3)
                            .overlay(Circle().strokeBorder(Color.accentColor, lineWidth: document.color == swatch.color ? 2 : 0))
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .help(swatch.name)
                    .accessibilityLabel(swatch.name)
                    .accessibilityAddTraits(document.color == swatch.color ? .isSelected : [])
                }
                ColorPicker("Custom color", selection: $document.color)
                    .labelsHidden()
                    .frame(width: 26)
                    .help("Custom color")
            }
            divider
            HStack(spacing: 2) {
                ForEach(Self.widths, id: \.self) { width in
                    let selected = abs(document.lineWidth - width) < 0.5
                    Button { document.lineWidth = width } label: {
                        Circle()
                            .fill(Color.primary.opacity(selected ? 0.9 : 0.45))
                            .frame(width: 4 + width * 0.9, height: 4 + width * 0.9)
                            .frame(width: 26, height: 30)
                            .background(Circle().fill(Color.accentColor.opacity(selected ? 0.2 : 0)).frame(width: 26, height: 26))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(width < 4 ? "Thin" : width < 8 ? "Medium" : "Thick")
                    .accessibilityLabel(width < 4 ? "Thin" : width < 8 ? "Medium" : "Thick")
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
            divider
            HStack(spacing: 2) {
                IconButton(symbol: "arrow.uturn.backward", help: "Undo (⌘Z)") { document.undo() }
                    .keyboardShortcut("z", modifiers: .command)
                    .disabled(!document.canUndo)
                IconButton(symbol: "arrow.uturn.forward", help: "Redo (⇧⌘Z)") { document.redo() }
                    .keyboardShortcut("z", modifiers: [.command, .shift])
                    .disabled(!document.canRedo)
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 46)
        .glassSurface(Capsule())
    }

    /// Copy, Save… and Done.
    private var actions: some View {
        GlassGroup(spacing: 8) {
            HStack(spacing: 8) {
                Button(action: onCopy) { Label("Copy", systemImage: "doc.on.doc") }
                    .keyboardShortcut("c", modifiers: .command)
                    .glassButtonStyle()
                    .help("Copy the annotated image (⌘C)")
                Button(action: onSave) { Label("Save…", systemImage: "square.and.arrow.down") }
                    .keyboardShortcut("s", modifiers: .command)
                    .glassButtonStyle()
                    .help("Save as PNG (⌘S)")
                Button("Done", action: onDone)
                    .keyboardShortcut(.return, modifiers: .command)
                    .glassButtonStyle(prominent: true)
                    .help("Keep the changes and close (⌘↩)")
            }
            .labelStyle(.iconOnly)
            .controlSize(.large)
        }
    }

    private var divider: some View {
        Rectangle().fill(Color.primary.opacity(0.14)).frame(width: 1, height: 22)
    }

    private func canvas(scale: CGFloat) -> some View {
        let size = document.size
        let base = Image(nsImage: document.baseImage)
        let pixelated = Image(nsImage: document.pixelated)
        let annotations = document.visibleAnnotations
        return Canvas { ctx, _ in
            ctx.scaleBy(x: scale, y: scale)
            ctx.draw(base, in: CGRect(origin: .zero, size: size))
            AnnotationRenderer.draw(annotations, in: ctx, imageSize: size, pixelated: pixelated)
        }
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    document.dragChanged(from: value.startLocation.scaled(1 / scale),
                                         to: value.location.scaled(1 / scale))
                }
                .onEnded { value in
                    document.dragEnded(at: value.location.scaled(1 / scale))
                }
        )
    }
}

private extension CGPoint {
    func scaled(_ s: CGFloat) -> CGPoint { CGPoint(x: x * s, y: y * s) }
}

extension AnnotationTool {
    /// Single-key shortcut while the editor is open.
    var key: Character {
        switch self {
        case .arrow: return "a"
        case .rectangle: return "r"
        case .ellipse: return "o"
        case .pen: return "p"
        case .highlight: return "h"
        case .text: return "t"
        case .counter: return "n"
        case .pixelate: return "x"
        }
    }
}

/// One tool in the annotation toolbar; the selected tool is filled with the accent color.
private struct ToolButton: View {
    let tool: AnnotationTool
    let selected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: tool.symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(selected ? Color.white : Color.primary)
                .frame(width: 32, height: 32)
                .background(Circle().fill(selected ? Color.accentColor : Color.primary.opacity(hovering ? 0.1 : 0)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .keyboardShortcut(KeyEquivalent(tool.key), modifiers: [])
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
        .animation(.easeOut(duration: 0.15), value: selected)
        .help("\(tool.title) (\(String(tool.key).uppercased()))")
        .accessibilityLabel(tool.title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// A small round icon button for the toolbar.
private struct IconButton: View {
    let symbol: String
    let help: String
    let action: () -> Void
    @State private var hovering = false
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 30, height: 30)
                .background(Circle().fill(Color.primary.opacity(hovering && isEnabled ? 0.1 : 0)))
                .opacity(isEnabled ? 1 : 0.35)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(help)
        .accessibilityLabel(help)
    }
}
