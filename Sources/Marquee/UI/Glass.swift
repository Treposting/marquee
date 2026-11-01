import SwiftUI

// Liquid Glass on macOS 26 (Tahoe) and later, with the closest older look as a fallback.
// macOS 27's Liquid Glass transparency setting applies to these surfaces automatically.
//
// Glass is for the functional layer only: floating controls, toolbars, HUDs, panels and page
// header controls. Content (cards, tiles, list items, captures, clipboard cards) uses
// `contentSurface`, so it stays calm under the glass (HIG: Materials, Liquid Glass).

@available(macOS 26.0, *)
private func makeGlass(tint: Color?, interactive: Bool) -> Glass {
    var glass = Glass.regular
    if let tint { glass = glass.tint(tint) }
    if interactive { glass = glass.interactive() }
    return glass
}

extension View {
    /// A floating surface: Liquid Glass on macOS 26+, a material with a hairline edge before that.
    @ViewBuilder
    func glassSurface<S: Shape>(_ shape: S, tint: Color? = nil, interactive: Bool = false) -> some View {
        if #available(macOS 26.0, *) {
            self.glassEffect(makeGlass(tint: tint, interactive: interactive), in: shape)
        } else {
            self
                .background(.regularMaterial, in: shape)
                .overlay(shape.stroke(Color.primary.opacity(0.12), lineWidth: 1))
        }
    }

    /// Dark floating HUD (capture and recording toolbars): dark-tinted Liquid Glass on
    /// macOS 26+, a dark material panel before that. Readable over any screen content.
    @ViewBuilder
    func hudSurface(cornerRadius: CGFloat = 18) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        if #available(macOS 26.0, *) {
            self.glassEffect(.regular.tint(Color.black.opacity(0.4)), in: shape)
        } else {
            self
                .background(shape.fill(.ultraThinMaterial))
                .background(shape.fill(Color.black.opacity(0.55)))
                .overlay(shape.strokeBorder(Color.white.opacity(0.12)))
                .shadow(color: .black.opacity(0.35), radius: 16, y: 6)
        }
    }

    /// A content-layer surface for cards, tiles and list items: a quiet fill and a hairline
    /// edge, like a grouped box in System Settings. `solid` gives an opaque card for content
    /// that sits on glass (the clipboard panel), so glass is never stacked on glass.
    /// `highlight` brightens it for hover and press; `tint` washes it with a color.
    func contentSurface<S: InsettableShape>(
        _ shape: S, tint: Color? = nil, highlight: Double = 0, solid: Bool = false
    ) -> some View {
        modifier(ContentSurface(shape: shape, tint: tint, highlight: highlight, solid: solid))
    }

    /// Glass buttons on macOS 26+, bordered buttons before that.
    @ViewBuilder
    func glassButtonStyle(prominent: Bool = false) -> some View {
        if #available(macOS 26.0, *) {
            if prominent {
                self.buttonStyle(.glassProminent)
            } else {
                self.buttonStyle(.glass)
            }
        } else {
            if prominent {
                self.buttonStyle(.borderedProminent)
            } else {
                self.buttonStyle(.bordered)
            }
        }
    }
}

/// See `View.contentSurface`. With Increase Contrast on, the edge is drawn stronger.
private struct ContentSurface<S: InsettableShape>: ViewModifier {
    let shape: S
    let tint: Color?
    let highlight: Double
    let solid: Bool
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        content
            .background {
                ZStack {
                    if solid {
                        shape.fill(Color(nsColor: .controlBackgroundColor))
                    } else {
                        shape.fill(Color.primary.opacity(0.045))
                    }
                    if let tint { shape.fill(tint) }
                    if highlight > 0 { shape.fill(Color.primary.opacity(highlight)) }
                }
            }
            .overlay(shape.strokeBorder(Color.primary.opacity(contrast == .increased ? 0.35 : 0.09), lineWidth: 1))
    }
}

/// Groups glass elements so they render together and blend when close (macOS 26+).
struct GlassGroup<Content: View>: View {
    var spacing: CGFloat = 8
    @ViewBuilder var content: Content

    var body: some View {
        if #available(macOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) { content }
        } else {
            content
        }
    }
}
