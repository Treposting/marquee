import AppKit
import AudioToolbox

/// Short feedback sounds for copying and pasting, using sounds that ship with macOS.
/// Turned off with "Play sound on copy and paste" in Settings.
///
/// They play as system sound effects, like the screenshot shutter: through the device chosen
/// in System Settings → Sound → "Play sound effects through", at the alert volume. Regular
/// audio (NSSound) goes to the current output instead, which can be a different, muted device.
@MainActor
enum Sounds {
    enum Effect: Hashable {
        case copy, paste

        /// The sound chosen in Settings, or the default if it's missing.
        fileprivate var name: String {
            let chosen = self == .copy ? Preferences.copySound : Preferences.pasteSound
            return Sounds.choices.contains(chosen) ? chosen : (self == .copy ? "Tink" : "Pop")
        }
    }

    nonisolated private static let folder = URL(fileURLWithPath: "/System/Library/Sounds")

    /// The sounds that ship with macOS, offered in Settings.
    nonisolated static let choices: [String] = {
        let files = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        let names = files.filter { $0.hasSuffix(".aiff") }.map { String($0.dropLast(5)) }.sorted()
        return names.isEmpty ? ["Pop", "Tink"] : names
    }()

    private static var systemSounds: [String: SystemSoundID] = [:]
    private static var lastPlayed: Date?

    /// Plays one sound per action: pasting from history (which copies, then types ⌘V) or a
    /// copy Marquee already sounded isn't sounded again when the clipboard monitor or the
    /// ⌘V watcher sees it a moment later.
    static func play(_ effect: Effect) {
        guard Preferences.copyPasteSound else { return }
        let now = Date()
        if let lastPlayed, now.timeIntervalSince(lastPlayed) < 1 { return }
        lastPlayed = now
        play(named: effect.name)
    }

    /// Plays a sound right away, e.g. to preview it in Settings.
    static func play(named name: String) {
        if let id = systemSound(named: name) {
            AudioServicesPlaySystemSound(id)
        } else {
            NSSound(named: NSSound.Name(name))?.play()
        }
    }

    /// Registers the macOS sound file once and reuses its ID.
    private static func systemSound(named name: String) -> SystemSoundID? {
        if let id = systemSounds[name] { return id }
        let url = folder.appendingPathComponent("\(name).aiff")
        var id: SystemSoundID = 0
        guard FileManager.default.fileExists(atPath: url.path),
              AudioServicesCreateSystemSoundID(url as CFURL, &id) == kAudioServicesNoError else { return nil }
        systemSounds[name] = id
        return id
    }
}
