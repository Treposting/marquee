import SwiftUI

// Shared look for the pages of the Marquee window, following the macOS 26/27 design:
// content stays calm (soft cards with matching corners), and the controls in each page
// header sit together on Liquid Glass. Glass comes from UI/Glass.swift, so older systems
// get the material fallbacks.

/// Spacing and corner sizes shared by every page.
enum Page {
    /// Side margin of page content.
    static let gutter: CGFloat = 28
    /// Corner radius of cards; tiles inside a card use `tileRadius`, so corners stay concentric.
    static let cardRadius: CGFloat = 18
    static let tileRadius: CGFloat = 12
    static let maxWidth: CGFloat = 1040

    static var card: RoundedRectangle { RoundedRectangle(cornerRadius: cardRadius, style: .continuous) }
    static var tile: RoundedRectangle { RoundedRectangle(cornerRadius: tileRadius, style: .continuous) }
}

/// A page's title, a short line under it, and the page's controls grouped on glass.
struct PageHeader<Controls: View>: View {
    let title: String
    var subtitle: String? = nil
    var icon: NSImage? = nil
    @ViewBuilder var controls: Controls

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            if let icon {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 40, height: 40)
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 26, weight: .bold))
                    .accessibilityAddTraits(.isHeader)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 12)
            GlassGroup(spacing: 8) {
                HStack(spacing: 8) { controls }
            }
        }
        .padding(.horizontal, Page.gutter)
        .padding(.top, 22)
        .padding(.bottom, 14)
    }
}

extension PageHeader where Controls == EmptyView {
    init(title: String, subtitle: String? = nil, icon: NSImage? = nil) {
        self.init(title: title, subtitle: subtitle, icon: icon) { EmptyView() }
    }
}

/// A capsule search field on glass.
struct GlassSearchField: View {
    @Binding var text: String
    var prompt = "Search"
    var width: CGFloat = 240

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
            TextField(prompt, text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 12)
        .frame(width: width, height: 32)
        .glassSurface(Capsule(), interactive: true)
    }
}

/// The "…" options menu for a page, as a round glass button.
struct GlassMenuButton<Content: View>: View {
    var label = "Options"
    @ViewBuilder var content: Content

    var body: some View {
        Menu {
            content
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 14, weight: .semibold))
                .frame(width: 32, height: 32)
                .contentShape(Circle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .glassSurface(Circle(), interactive: true)
        .help(label)
        .accessibilityLabel(label)
    }
}

extension View {
    /// A content card on Liquid Glass with the shared corner radius, lightly tinted if asked.
    func pageCard(tint: Color? = nil, padding: CGFloat = 16) -> some View {
        self
            .padding(padding)
            .glassSurface(Page.card, tint: tint?.opacity(0.16))
    }

    /// Standard section title inside a page ("Recent", "Capture", …).
    func pageSectionTitle() -> some View {
        self
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.secondary)
            .accessibilityAddTraits(.isHeader)
    }
}

/// A centered empty state: symbol, title, a line of help and an optional action.
struct PageEmptyState<Action: View>: View {
    let symbol: String
    let title: String
    let message: String
    @ViewBuilder var action: Action

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(.secondary)
                .frame(width: 76, height: 76)
                .glassSurface(Circle())
            Text(title).font(.system(size: 15, weight: .semibold))
            Text(message)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 400)
            action
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(Page.gutter)
    }
}

extension PageEmptyState where Action == EmptyView {
    init(symbol: String, title: String, message: String) {
        self.init(symbol: symbol, title: title, message: message) { EmptyView() }
    }
}
