import AppKit
import ImageIO
import SwiftUI

@MainActor
struct LibraryView: View {
    @ObservedObject var library = CaptureLibrary.shared
    @AppStorage(Preferences.Key.keepLibrary.rawValue) private var keepLibrary = true
    @State private var filter: Filter = .all
    @State private var confirmClear = false

    enum Filter: String, CaseIterable, Identifiable {
        case all = "All", screenshots = "Screenshots", recordings = "Recordings"
        var id: String { rawValue }
    }

    private var subtitle: String {
        let shots = library.items.filter { !$0.isVideo }.count
        let videos = library.items.count - shots
        if library.items.isEmpty { return keepLibrary ? "Your recent captures" : "Off" }
        return "\(shots) screenshot\(shots == 1 ? "" : "s") · \(videos) recording\(videos == 1 ? "" : "s")"
    }

    private var items: [LibraryItem] {
        switch filter {
        case .all: return library.items
        case .screenshots: return library.items.filter { !$0.isVideo }
        case .recordings: return library.items.filter(\.isVideo)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            PageHeader(title: "Library", subtitle: subtitle) {
                Picker("Show", selection: $filter) {
                    ForEach(Filter.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 280)
                GlassMenuButton(label: "Library options") {
                    Toggle("Keep new captures in the Library", isOn: $keepLibrary)
                    Button("Show Library in Finder") { NSWorkspace.shared.open(library.directory) }
                    Divider()
                    Button("Clear Library…", role: .destructive) { confirmClear = true }
                        .disabled(library.items.isEmpty)
                }
            }

            if items.isEmpty {
                EmptyLibrary(keepLibrary: keepLibrary)
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 210), spacing: 18)], spacing: 20) {
                        ForEach(items) { item in
                            LibraryTile(item: item, revision: library.revision)
                        }
                    }
                    .padding(.horizontal, Page.gutter)
                    .padding(.bottom, Page.gutter)
                }
            }
        }
        .confirmationDialog("Delete every capture in the Library?", isPresented: $confirmClear) {
            Button("Delete All", role: .destructive) { library.clear() }
        } message: {
            Text("Files you saved to your screenshots folder aren't affected.")
        }
    }
}

private struct LibraryTile: View {
    let item: LibraryItem
    let revision: Int
    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .bottomLeading) {
                LibraryThumbnail(item: item, revision: revision)
                    .frame(maxWidth: .infinity)
                    .aspectRatio(16 / 10, contentMode: .fit)
                    .background(Color.primary.opacity(0.04))
                    .clipShape(Page.tile)
                    .overlay(Page.tile.strokeBorder(Color.primary.opacity(hovering ? 0.25 : 0.1)))
                    .shadow(color: .black.opacity(hovering ? 0.14 : 0.06), radius: hovering ? 8 : 3, y: hovering ? 3 : 1)
                    .animation(.easeOut(duration: 0.15), value: hovering)
                if item.isVideo {
                    Label("Recording", systemImage: "play.fill")
                        .font(.system(size: 10, weight: .semibold))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(.black.opacity(0.6), in: Capsule())
                        .foregroundStyle(.white)
                        .padding(8)
                }
            }
            HStack {
                Text(item.date.formatted(date: .abbreviated, time: .shortened))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Spacer()
                if hovering {
                    Button { CaptureLibrary.shared.copy(item) } label: { Image(systemName: "doc.on.doc") }
                        .buttonStyle(.borderless)
                        .help("Copy")
                        .accessibilityLabel("Copy")
                    Menu { LibraryItemMenu(item: item) } label: { Image(systemName: "ellipsis") }
                        .menuStyle(.borderlessButton)
                        .menuIndicator(.hidden)
                        .fixedSize()
                        .accessibilityLabel("More")
                }
            }
            .frame(height: 18)
        }
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture(count: 2) { CaptureLibrary.shared.open(item) }
        .contextMenu { LibraryItemMenu(item: item) }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(item.isVideo ? "Recording" : "Screenshot")
    }
}

/// The same actions in context menus and the "…" menu.
struct LibraryItemMenu: View {
    let item: LibraryItem

    var body: some View {
        let library = CaptureLibrary.shared
        Button("Open") { library.open(item) }
        Button("Copy") { library.copy(item) }
        if item.isVideo {
            Button("Edit…") { VideoEditorController.edit(library.fileURL(for: item)) }
        } else {
            Button("Annotate…") { library.annotate(item) }
        }
        Button("Show in Finder") { library.reveal(item) }
        Button("Save to Screenshots Folder") { library.saveToFolder(item) }
        Divider()
        Button("Delete", role: .destructive) { library.remove(item) }
    }
}

/// Loads a small preview off the main thread (ImageIO thumbnail, max 480 px).
struct LibraryThumbnail: View {
    let item: LibraryItem
    let revision: Int
    @State private var image: NSImage?

    var body: some View {
        ZStack {
            Rectangle().fill(Color.primary.opacity(0.06))
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                Image(systemName: item.isVideo ? "film" : "photo")
                    .font(.system(size: 22))
                    .foregroundStyle(.tertiary)
            }
        }
        .task(id: "\(item.id)-\(revision)") {
            guard let url = CaptureLibrary.shared.previewURL(for: item) else { return }
            image = await Self.thumbnail(at: url)
        }
    }

    private static func thumbnail(at url: URL) async -> NSImage? {
        let cg = await Task.detached(priority: .utility) { () -> CGImage? in
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: 480,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCache: false,
            ]
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
            return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        }.value
        guard let cg else { return nil }
        return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
    }
}

private struct EmptyLibrary: View {
    let keepLibrary: Bool

    var body: some View {
        PageEmptyState(
            symbol: keepLibrary ? "photo.on.rectangle.angled" : "tray",
            title: keepLibrary ? "Your screenshots and recordings show up here" : "The Library is turned off",
            message: keepLibrary
                ? "Take a capture and it's kept here, so you can copy, annotate or save it later."
                : "Turn on \u{201C}Keep new captures in the Library\u{201D} from the \u{2026} menu."
        ) {
            if keepLibrary {
                Button("Capture an Area") { AppModel.shared.perform(.captureArea) }
                    .glassButtonStyle(prominent: true)
                    .controlSize(.large)
            }
        }
    }
}
