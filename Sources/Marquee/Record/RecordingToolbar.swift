import AppKit
import SwiftUI

/// State shared by the recording toolbar and RecordingController.
@MainActor
final class RecordingSession: ObservableObject {
    enum Phase: Equatable {
        case ready
        case countdown(Int)
        case starting
        case recording
        case saving
    }

    @Published var phase: Phase = .ready
    @Published var elapsed: TimeInterval = 0
    @Published var micEnabled: Bool
    @Published var micID: String?
    @Published var micName = "No microphone"
    @Published var micLevel: Float = 0
    @Published var micProblem: String?
    @Published var desktopAudio: Bool
    @Published var separateVoice: Bool
    @Published var cameraEnabled = false
    @Published var cameraName = "No camera"
    @Published var cameraProblem: String?
    /// Mid-recording: the microphone records silence, or the camera bubble is hidden.
    @Published var micMuted = false
    @Published var cameraHidden = false
    let sizeLabel: String

    init(micEnabled: Bool, micID: String?, desktopAudio: Bool, separateVoice: Bool, sizeLabel: String) {
        self.micEnabled = micEnabled
        self.micID = micID
        self.desktopAudio = desktopAudio
        self.separateVoice = separateVoice
        self.sizeLabel = sizeLabel
    }
}

/// The floating bar under the recording area: choose audio sources, start, stop.
@MainActor
struct RecordingToolbar: View {
    struct Actions {
        var start: () -> Void
        var cancel: () -> Void
        var stop: () -> Void
        var discard: () -> Void
        var showMicMenu: () -> Void
        var toggleDesktopAudio: () -> Void
        var showCameraMenu: () -> Void
        var toggleMicMute: () -> Void
        var toggleCamera: () -> Void
    }

    @ObservedObject var session: RecordingSession
    let actions: Actions

    var body: some View {
        HStack(spacing: 6) {
            switch session.phase {
            case .ready:
                readyControls
            case .countdown(let seconds):
                IconButton(symbol: "xmark", help: "Cancel (Esc)", action: actions.cancel)
                    .keyboardShortcut(.cancelAction)
                Text(seconds > 0 ? "Recording in \(seconds)…" : "Go!")
                    .font(.system(size: 13, weight: .medium))
                    .monospacedDigit()
                    .padding(.horizontal, 10)
            case .starting:
                ProgressView().controlSize(.small).padding(.leading, 8)
                Text("Starting…").font(.system(size: 13, weight: .medium)).padding(.trailing, 10)
            case .recording:
                recordingControls
            case .saving:
                ProgressView().controlSize(.small).padding(.leading, 8)
                Text("Saving recording…").font(.system(size: 13, weight: .medium)).padding(.trailing, 10)
            }
        }
        .padding(6)
        .frame(height: 48)
        .toolbarSurface()
        .environment(\.colorScheme, .dark)
        .fixedSize()
        .animation(.easeOut(duration: 0.18), value: session.phase)
    }

    // MARK: Ready

    @ViewBuilder
    private var readyControls: some View {
        IconButton(symbol: "xmark", help: "Cancel (Esc)", action: actions.cancel)
            .keyboardShortcut(.cancelAction)

        Text(session.sizeLabel)
            .font(.system(size: 12, weight: .medium, design: .monospaced))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)

        ToolbarDivider()

        Button(action: actions.showMicMenu) {
            HStack(spacing: 7) {
                Image(systemName: micSymbol)
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 16)
                Text(micTitle)
                    .lineLimit(1)
                    .frame(maxWidth: 170, alignment: .leading)
                if session.micEnabled {
                    LevelMeter(level: session.micLevel)
                }
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .opacity(0.6)
            }
        }
        .buttonStyle(ChipStyle(active: session.micEnabled, warning: session.micProblem != nil))
        .help(session.micProblem ?? "Choose a microphone")

        Button(action: actions.toggleDesktopAudio) {
            HStack(spacing: 7) {
                Image(systemName: session.desktopAudio ? "speaker.wave.2.fill" : "speaker.slash.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 18)
                Text("Desktop audio")
            }
        }
        .buttonStyle(ChipStyle(active: session.desktopAudio))
        .help(session.desktopAudio ? "Recording what your Mac plays. Click to turn off." : "Click to record what your Mac plays")

        Button(action: actions.showCameraMenu) {
            HStack(spacing: 7) {
                Image(systemName: session.cameraProblem != nil ? "video.slash.fill"
                      : (session.cameraEnabled ? "video.fill" : "video.slash.fill"))
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 18)
                Text(session.cameraProblem != nil ? "Camera blocked" : (session.cameraEnabled ? "Camera" : "No camera"))
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .opacity(0.6)
            }
        }
        .buttonStyle(ChipStyle(active: session.cameraEnabled, warning: session.cameraProblem != nil))
        .help(session.cameraProblem ?? "Show your camera in the recording, and choose its shape, size and corner")

        ToolbarDivider()

        Button(action: actions.start) {
            HStack(spacing: 7) {
                Circle().fill(.white).frame(width: 9, height: 9)
                Text("Record").fontWeight(.semibold)
            }
        }
        .buttonStyle(RecordButtonStyle())
        .keyboardShortcut(.defaultAction)
        .help("Start recording (Return)")
    }

    private var micSymbol: String {
        if session.micProblem != nil { return "mic.badge.xmark" }
        return session.micEnabled ? "mic.fill" : "mic.slash.fill"
    }

    private var micTitle: String {
        if session.micProblem != nil { return "Microphone blocked" }
        return session.micEnabled ? session.micName : "No microphone"
    }

    // MARK: Recording

    @ViewBuilder
    private var recordingControls: some View {
        HStack(spacing: 8) {
            RecordingDot()
            Text(ElapsedTime.format(session.elapsed))
                .font(.system(size: 14, weight: .semibold, design: .monospaced))
                .monospacedDigit()
                .lineLimit(1)
                .fixedSize()
        }
        .padding(.horizontal, 10)

        if session.micEnabled {
            Button(action: actions.toggleMicMute) {
                HStack(spacing: 6) {
                    Image(systemName: session.micMuted ? "mic.slash.fill" : "mic.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(session.micMuted ? recordRed : Color.white)
                        .frame(width: 14)
                    LevelMeter(level: session.micMuted ? 0 : session.micLevel)
                }
                .padding(.horizontal, 8)
                .frame(height: 34)
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(session.micMuted ? recordRed.opacity(0.18) : Color.white.opacity(0.07)))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(session.micMuted ? "Microphone muted. Click to unmute" : "Mute the microphone (silence is recorded)")
            .accessibilityLabel(session.micMuted ? "Unmute microphone" : "Mute microphone")
        }
        if session.cameraEnabled {
            Button(action: actions.toggleCamera) {
                Image(systemName: session.cameraHidden ? "video.slash.fill" : "video.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(session.cameraHidden ? recordRed : Color.white)
                    .frame(width: 34, height: 34)
                    .background(RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(session.cameraHidden ? recordRed.opacity(0.18) : Color.white.opacity(0.07)))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(session.cameraHidden ? "Camera hidden. Click to show it again" : "Hide the camera from the recording")
            .accessibilityLabel(session.cameraHidden ? "Show camera" : "Hide camera")
        }

        if session.desktopAudio {
            Image(systemName: "speaker.wave.2.fill")
                .font(.system(size: 12, weight: .semibold))
                .padding(.horizontal, 6)
                .help("Recording desktop audio")
        }

        ToolbarDivider()

        // Icon only, so the bar keeps its size however long the recording gets.
        Button(action: actions.stop) {
            RoundedRectangle(cornerRadius: 2.5).fill(.white).frame(width: 11, height: 11)
                .frame(width: 18)
        }
        .buttonStyle(RecordButtonStyle())
        .keyboardShortcut(.defaultAction)
        .help("Stop and save (Return)")
        .accessibilityLabel("Stop and save")

        IconButton(symbol: "trash", help: "Discard this recording", action: actions.discard)
    }
}

// MARK: - Pieces

private let tape = Color(red: 1, green: 0.81, blue: 0.1)
private let recordRed = Color(red: 1, green: 0.23, blue: 0.19)


private extension View {
    /// Dark-tinted Liquid Glass on macOS 26+ (controls stay legible over any content);
    /// a dark material panel on older systems.
    func toolbarSurface() -> some View {
        hudSurface(cornerRadius: 18)
    }
}

private struct ToolbarDivider: View {
    var body: some View {
        Rectangle().fill(Color.white.opacity(0.14)).frame(width: 1, height: 22).padding(.horizontal, 2)
    }
}

private struct IconButton: View {
    let symbol: String
    let help: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .bold))
                .frame(width: 34, height: 34)
                .background(Circle().fill(Color.white.opacity(hovering ? 0.16 : 0.08)))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(help)
        .accessibilityLabel(help)
    }
}

private struct ChipStyle: ButtonStyle {
    var active: Bool
    var warning = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(warning ? Color.orange : (active ? tape : Color.white.opacity(0.85)))
            .padding(.horizontal, 11)
            .frame(height: 34)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(active && !warning ? tape.opacity(0.16) : Color.white.opacity(0.07))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(active && !warning ? tape.opacity(0.35) : Color.clear)
            )
            .opacity(configuration.isPressed ? 0.7 : 1)
            .contentShape(Rectangle())
    }
}

private struct RecordButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13))
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .frame(height: 34)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(recordRed.opacity(configuration.isPressed ? 0.75 : 1))
            )
            .contentShape(Rectangle())
    }
}

/// Six bars that light up with the input level.
private struct LevelMeter: View {
    let level: Float
    private let bars = 6

    var body: some View {
        HStack(alignment: .center, spacing: 2) {
            ForEach(0..<bars, id: \.self) { i in
                let threshold = Float(i) / Float(bars)
                RoundedRectangle(cornerRadius: 1)
                    .fill(level > threshold ? barColor(i) : Color.white.opacity(0.18))
                    .frame(width: 3, height: 5 + CGFloat(i) * 2)
            }
        }
        .frame(height: 16)
        .animation(.linear(duration: 0.08), value: level)
        .accessibilityLabel("Microphone level")
    }

    private func barColor(_ i: Int) -> Color {
        i >= bars - 1 ? recordRed : (i >= bars - 2 ? .orange : tape)
    }
}

private struct RecordingDot: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dim = false

    var body: some View {
        Circle()
            .fill(recordRed)
            .frame(width: 10, height: 10)
            .opacity(dim ? 0.35 : 1)
            .accessibilityLabel("Recording")
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) { dim = true }
            }
    }
}

/// Big 3-2-1 shown over the recording area before recording starts.
@MainActor
struct CountdownView: View {
    @ObservedObject var session: RecordingSession
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            countdownDisc
            if case .countdown(let n) = session.phase {
                Text(n > 0 ? "\(n)" : "Go")
                    .font(.system(size: n > 0 ? 64 : 46, weight: .bold, design: .rounded))
                    .foregroundStyle(n > 0 ? Color.white : tape)
                    .id(n)
                    .transition(reduceMotion ? .opacity : .scale(scale: 1.4).combined(with: .opacity))
                    .accessibilityLabel(n > 0 ? "Recording in \(n)" : "Go")
            }
        }
        .frame(width: 132, height: 132)
        .environment(\.colorScheme, .dark)
        .animation(reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.35, dampingFraction: 0.75), value: session.phase)
    }

    @ViewBuilder
    private var countdownDisc: some View {
        if #available(macOS 26.0, *) {
            Color.clear.glassEffect(.regular.tint(Color.black.opacity(0.35)), in: Circle())
        } else {
            Circle()
                .fill(.ultraThinMaterial)
                .background(Circle().fill(Color.black.opacity(0.45)))
                .overlay(Circle().strokeBorder(Color.white.opacity(0.15)))
        }
    }
}
