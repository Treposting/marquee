import AppKit
import SwiftUI

/// Click, then press a key combination. Esc cancels, ⌫ clears.
@MainActor
struct ShortcutRecorder: View {
    let action: ShortcutAction

    @State private var combo: KeyCombo?
    @State private var isRecording = false
    @State private var monitor: Any?

    var body: some View {
        HStack(spacing: 6) {
            Button(action: toggle) {
                Text(label)
                    .font(.system(.body, design: combo == nil || isRecording ? .default : .monospaced))
                    .foregroundStyle(isRecording ? Color.accentColor : (combo == nil ? Color.secondary : Color.primary))
                    .frame(minWidth: 130)
            }
            .glassButtonStyle(prominent: isRecording)
            .help("Click and press a new shortcut. Esc cancels, ⌫ clears.")
            .accessibilityLabel("Shortcut for \(action.title)")
            .accessibilityValue(label)

            Button {
                ShortcutStore.reset(action)
            } label: {
                Image(systemName: "arrow.counterclockwise")
                    // At least the 20 pt macOS minimum target (HIG: Accessibility).
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .help("Restore default")
            .accessibilityLabel("Restore the default shortcut for \(action.title)")
            .disabled(combo == action.defaultCombo)
        }
        .onAppear { combo = ShortcutStore.combo(for: action) }
        .onDisappear { stop(notify: true) }
        .onReceive(NotificationCenter.default.publisher(for: ShortcutStore.didChange)) { _ in
            combo = ShortcutStore.combo(for: action)
        }
        .onReceive(NotificationCenter.default.publisher(for: ShortcutStore.recordingWillBegin)) { note in
            // Only one recorder listens at a time.
            if note.object as? String != action.rawValue { stop(notify: false) }
        }
    }

    private var label: String {
        if isRecording { return "Press shortcut…" }
        return combo?.displayString ?? "Record Shortcut"
    }

    private func toggle() {
        isRecording ? stop(notify: true) : start()
    }

    private func start() {
        NotificationCenter.default.post(name: ShortcutStore.recordingWillBegin, object: action.rawValue)
        isRecording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            handle(event)
            return nil
        }
    }

    private func stop(notify: Bool) {
        guard isRecording else { return }
        isRecording = false
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        if notify {
            NotificationCenter.default.post(name: ShortcutStore.recordingDidEnd, object: nil)
        }
    }

    private func handle(_ event: NSEvent) {
        let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
        if flags.isEmpty && event.keyCode == 53 { // Esc
            stop(notify: true)
            return
        }
        if flags.isEmpty && (event.keyCode == 51 || event.keyCode == 117) { // ⌫ / ⌦
            ShortcutStore.set(nil, for: action)
            stop(notify: true)
            return
        }
        let newCombo = KeyCombo(event: event)
        guard newCombo.isValid else {
            NSSound.beep()
            return
        }
        ShortcutStore.set(newCombo, for: action)
        stop(notify: true)
    }
}
