import AppKit
import SwiftUI

@MainActor
struct ColorsView: View {
    @ObservedObject var picker = ColorPickerController.shared
    @State private var confirmClear = false

    var body: some View {
        VStack(spacing: 0) {
            PageHeader(title: "Colors",
                       subtitle: picker.history.isEmpty ? "Pick any color on screen" : "\(picker.history.count) picked") {
                Picker("Copy as", selection: $picker.format) {
                    ForEach(ColorFormat.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 300)
                .help("Format used when you pick or click a color")
                Button {
                    AppModel.shared.perform(.pickColor)
                } label: {
                    Label("Pick Color", systemImage: "eyedropper")
                }
                .glassButtonStyle(prominent: true)
                .controlSize(.large)
                .keyboardShortcut("p", modifiers: .command)
            }

            if let latest = picker.history.first {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        LatestColorCard(color: latest)
                            .pageCard(padding: 18)
                        if picker.history.count > 1 {
                            VStack(alignment: .leading, spacing: 10) {
                                HStack {
                                    Text("Recent")
                                        .pageSectionTitle()
                                    Spacer()
                                    Button("Clear…") { confirmClear = true }.buttonStyle(.link)
                                }
                                LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 12)], spacing: 14) {
                                    ForEach(picker.history.dropFirst()) { color in
                                        Swatch(color: color)
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, Page.gutter)
                    .padding(.bottom, Page.gutter)
                    .frame(maxWidth: Page.maxWidth, alignment: .leading)
                }
            } else {
                PageEmptyState(
                    symbol: "eyedropper.halffull",
                    title: "Pick any color on your screen",
                    message: "A magnifier follows the pointer. Click to pick; the color is copied as \(picker.format.rawValue)."
                ) {
                    Button("Pick Color") { AppModel.shared.perform(.pickColor) }
                        .glassButtonStyle(prominent: true)
                        .controlSize(.large)
                }
            }
        }
        .confirmationDialog("Clear all picked colors?", isPresented: $confirmClear) {
            Button("Clear", role: .destructive) { picker.clear() }
        }
    }
}

private struct LatestColorCard: View {
    let color: PickedColor

    var body: some View {
        HStack(alignment: .top, spacing: 20) {
            Page.tile
                .fill(Color(nsColor: color.nsColor))
                .frame(width: 140, height: 140)
                .overlay(Page.tile.strokeBorder(Color.primary.opacity(0.12)))
                .shadow(color: Color(nsColor: color.nsColor).opacity(0.35), radius: 10, y: 4)
                .accessibilityLabel("Color \(color.hex)")
            VStack(alignment: .leading, spacing: 8) {
                ForEach(ColorFormat.allCases) { format in
                    HStack(spacing: 10) {
                        Text(format.rawValue)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 54, alignment: .leading)
                        Text(color.string(in: format))
                            .font(.system(size: 13, design: .monospaced))
                            .textSelection(.enabled)
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        Button {
                            ColorPickerController.shared.copy(color, as: format)
                        } label: {
                            Image(systemName: "doc.on.doc")
                        }
                        .buttonStyle(.borderless)
                        .help("Copy \(format.rawValue)")
                        .accessibilityLabel("Copy \(format.rawValue)")
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(Color.primary.opacity(0.05), in: Capsule())
                }
            }
            .frame(maxWidth: 460)
        }
    }
}

private struct Swatch: View {
    let color: PickedColor
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovering = false

    var body: some View {
        Button {
            ColorPickerController.shared.copy(color)
        } label: {
            VStack(spacing: 6) {
                Page.tile
                    .fill(Color(nsColor: color.nsColor))
                    .frame(height: 64)
                    .overlay(Page.tile.strokeBorder(Color.primary.opacity(hovering ? 0.3 : 0.1), lineWidth: hovering ? 2 : 1))
                    .scaleEffect(hovering && !reduceMotion ? 1.03 : 1)
                    .animation(.easeOut(duration: 0.15), value: hovering)
                Text(color.hex)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help("Click to copy")
        .contextMenu {
            ForEach(ColorFormat.allCases) { format in
                Button("Copy \(format.rawValue)") { ColorPickerController.shared.copy(color, as: format) }
            }
            Divider()
            Button("Delete", role: .destructive) { ColorPickerController.shared.remove(color) }
        }
        .accessibilityLabel("Color \(color.hex)")
        .accessibilityHint("Copies the color")
    }
}
