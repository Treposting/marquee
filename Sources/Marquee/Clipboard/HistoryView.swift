import AppKit
import SwiftUI

/// The panel's outline: it sits on the bottom edge of the screen, so only the top corners
/// are rounded. The border follows the same outline.
struct TopRoundedRectangle: Shape {
    var radius: CGFloat

    func path(in rect: CGRect) -> Path {
        let r = min(radius, rect.width / 2, rect.height)
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + r))
        path.addArc(tangent1End: CGPoint(x: rect.minX, y: rect.minY),
                    tangent2End: CGPoint(x: rect.minX + r, y: rect.minY), radius: r)
        path.addLine(to: CGPoint(x: rect.maxX - r, y: rect.minY))
        path.addArc(tangent1End: CGPoint(x: rect.maxX, y: rect.minY),
                    tangent2End: CGPoint(x: rect.maxX, y: rect.minY + r), radius: r)
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

/// The ⇧⌘V panel: search, filters and categories on top, cards below.
@MainActor
struct HistoryView: View {
    @ObservedObject var model: HistoryViewModel
    let thumbnails: ThumbnailCache
    var onPaste: (ClipItem) -> Void
    var onTogglePin: (ClipItem) -> Void
    var onDelete: (ClipItem) -> Void

    @FocusState var searchFocused: Bool

    var body: some View {
        let items = model.visibleItems
        VStack(alignment: .leading, spacing: 12) {
            header(count: items.count)
            if items.isEmpty {
                emptyState
            } else {
                cards(items)
            }
        }
        .padding(.top, 16)
        .padding(.bottom, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .glassSurface(TopRoundedRectangle(radius: 26))
        // A barely-there fill so every point of the panel takes clicks and scrolls.
        .background(Color.black.opacity(0.001), in: TopRoundedRectangle(radius: 26))
        .onAppear { searchFocused = true }
        .onReceive(model.$focusToken) { _ in searchFocused = true }
        .onChange(of: model.draft == nil) { closed in
            if closed { searchFocused = true }
        }
    }

    private func header(count: Int) -> some View {
        HStack(spacing: 12) {
            HStack(spacing: 7) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                TextField("Search", text: $model.query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .focused($searchFocused)
            }
            .padding(.horizontal, 12)
            .frame(width: 230, height: 30)
            .background(Color.primary.opacity(0.07), in: Capsule())

            if model.draft != nil {
                CategoryEditor(draft: $model.draft, store: model.store) { category in
                    model.filter = .category(category.id)
                }
            } else {
                ClipFilterBar(selection: $model.filter, store: model.store, draft: $model.draft)
            }

            Spacer(minLength: 8)

            Text("\(count) items  ·  click or ↩ to paste  ·  ⌘1–9 quick paste  ·  ⌘P pin")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .fixedSize()
        }
        .padding(.horizontal, 20)
    }

    private func thumbnail(for item: ClipItem) -> NSImage? {
        guard item.kind == .image, let url = model.store.imageURL(for: item) else { return nil }
        return thumbnails.thumbnail(for: url)
    }

    private var emptyMessage: String {
        if !model.query.isEmpty { return "No matches" }
        if case .category = model.filter {
            return "Nothing in this category yet.\nRight-click an item and choose Add to Category."
        }
        if model.store.items.isEmpty && PasteboardAccess.status != .allowed {
            return "macOS is limiting Marquee's clipboard access, so copies may not be recorded.\nAllow it in Settings → Clipboard."
        }
        return "Copy something and it shows up here"
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "doc.on.clipboard").font(.system(size: 30))
            Text(emptyMessage)
                .multilineTextAlignment(.center)
        }
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func cards(_ items: [ClipItem]) -> some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 14) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        ClipCard(
                            item: item,
                            index: index,
                            selected: index == model.selection,
                            thumbnail: thumbnail(for: item),
                            appIcon: thumbnails.appIcon(bundleID: item.sourceBundleID),
                            appColor: thumbnails.appColor(bundleID: item.sourceBundleID),
                            fileIcon: item.filePaths?.first.map { thumbnails.fileIcon(path: $0) },
                            category: model.store.category(for: item)
                        )
                        .id(item.id)
                        .onTapGesture { onPaste(item) }
                        .help("Click to paste")
                        .contextMenu {
                            Button("Paste") { onPaste(item) }
                            Button(item.pinned ? "Unpin" : "Pin") { onTogglePin(item) }
                            CategoryMenu(item: item, store: model.store, draft: $model.draft)
                            IgnoreAppMenu(item: item, store: model.store)
                            Divider()
                            Button("Delete", role: .destructive) { onDelete(item) }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 6)
            }
            .onChange(of: model.selection) { newValue in
                guard items.indices.contains(newValue) else { return }
                withAnimation(.easeOut(duration: 0.15)) {
                    proxy.scrollTo(items[newValue].id, anchor: .center)
                }
            }
        }
    }
}

@MainActor
struct ClipCard: View {
    let item: ClipItem
    let index: Int
    let selected: Bool
    let thumbnail: NSImage?
    let appIcon: NSImage?
    /// The source app's icon color; the header uses it, or the item kind's color without one.
    let appColor: PickedColor?
    let fileIcon: NSImage?
    var category: ClipCategory? = nil

    private static let corner: CGFloat = 16

    /// Text that is just a color (#FFCF1A, rgb(…), hsl(…)) gets a small swatch in front of it.
    private var color: PickedColor? {
        item.kind == .text ? item.text.flatMap(PickedColor.init(parsing:)) : nil
    }

    private var headerForeground: Color {
        guard let appColor, appColor.luminance > 0.45 else { return .white }
        return Color.black.opacity(0.8)
    }

    var body: some View {
        let color = self.color
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(headerLabel).font(.system(size: 13, weight: .semibold))
                    // Minutes, hours or days; refreshed once a minute.
                    TimelineView(.periodic(from: .now, by: 60)) { context in
                        Text(CopiedAge.text(since: item.date, now: context.date))
                    }
                    .font(.system(size: 10))
                    .opacity(0.85)
                }
                Spacer()
                if let appIcon {
                    Image(nsImage: appIcon).resizable().frame(width: 30, height: 30)
                }
            }
            .foregroundStyle(headerForeground)
            .padding(10)
            .background(appColor.map { Color(nsColor: $0.nsColor).gradient } ?? item.kind.color.gradient)

            Group {
                if let color {
                    ColorLine(color: color, text: item.text ?? "")
                } else {
                    content
                }
            }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(10)

            HStack(spacing: 6) {
                if item.pinned {
                    Image(systemName: "pin.fill")
                }
                if let category {
                    HStack(spacing: 4) {
                        Circle().fill(category.tint.color).frame(width: 7, height: 7)
                        Text(category.name).lineLimit(1)
                    }
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(category.tint.color.opacity(0.18), in: Capsule())
                    .accessibilityLabel("Category \(category.name)")
                }
                Text(footer).lineLimit(1)
                Spacer()
                if index < 9 {
                    Text("⌘\(index + 1)")
                }
            }
            .font(.system(size: 10))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .padding(.bottom, 8)
        }
        .frame(width: 230, height: 236)
        .clipShape(RoundedRectangle(cornerRadius: Self.corner, style: .continuous))
        .glassSurface(RoundedRectangle(cornerRadius: Self.corner, style: .continuous))
        // Only the selected card gets a ring; the glass has its own edge.
        .overlay {
            if selected {
                RoundedRectangle(cornerRadius: Self.corner, style: .continuous)
                    .strokeBorder(Color.accentColor, lineWidth: 2.5)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch item.kind {
        case .text:
            Text(item.text ?? "")
                .font(.system(size: 12))
                .lineLimit(9)
        case .link:
            if let text = item.text, let url = URL(string: text) {
                LinkCardContent(url: url, text: text)
            } else {
                Text(item.text ?? "")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.accentColor)
                    .lineLimit(6)
            }
        case .image:
            if let thumbnail {
                Image(nsImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Image(systemName: "photo").font(.largeTitle).foregroundStyle(.secondary)
            }
        case .file:
            if let url = item.fileURLs.first, let media = FileMedia(url) {
                VStack(alignment: .leading, spacing: 6) {
                    FilePreview(url: url, media: media, fallbackIcon: fileIcon)
                    Text(item.fileURLs.count > 1
                         ? "\(url.lastPathComponent) +\(item.fileURLs.count - 1) more"
                         : url.lastPathComponent)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            } else {
                fileList
            }
        }
    }

    private var fileList: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let fileIcon {
                Image(nsImage: fileIcon).resizable().frame(width: 56, height: 56)
            }
            ForEach(item.fileURLs.prefix(4), id: \.self) { url in
                Text(url.lastPathComponent).font(.system(size: 12)).lineLimit(1)
            }
            if item.fileURLs.count > 4 {
                Text("+\(item.fileURLs.count - 4) more").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    /// "Image" or "Video" for a copied media file, otherwise the kind's own label.
    private var headerLabel: String {
        if color != nil { return "Color" }
        if item.kind == .file, let url = item.fileURLs.first, let media = FileMedia(url) {
            return media == .video ? "Video" : "Image"
        }
        return item.kind.label
    }

    private var footer: String {
        if let color {
            let text = (item.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return text.hasPrefix("#") ? color.rgb : color.hex
        }
        switch item.kind {
        case .link:
            let host = item.text.flatMap { URL(string: $0)?.host }
            return host.map { $0.hasPrefix("www.") ? String($0.dropFirst(4)) : $0 } ?? "Link"
        case .text:
            return "\(item.text?.count ?? 0) characters"
        case .image:
            return item.sourceAppName ?? "Image"
        case .file:
            let n = item.filePaths?.count ?? 0
            return n == 1 ? "1 file" : "\(n) files"
        }
    }
}

/// A copied color: a small swatch in front of the text.
private struct ColorLine: View {
    let color: PickedColor
    let text: String

    var body: some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(Color(nsColor: color.nsColor))
                .overlay(RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.2), lineWidth: 0.5))
                .frame(width: 12, height: 12)
                .accessibilityHidden(true)
            Text(text.trimmingCharacters(in: .whitespacesAndNewlines))
                .font(.system(size: 12))
                .lineLimit(2)
        }
        .accessibilityElement(children: .combine)
    }
}
