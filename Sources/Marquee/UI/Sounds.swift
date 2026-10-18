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

        fileprivate var name: String {
            switch self {
            case .copy: return "Tink"
            case .paste: return "Pop"
            }
        }
    }

    private static var systemSounds: [Effect: SystemSoundID] = [:]

    static func play(_ effect: Effect) {
        guard Preferences.copyPasteSound else { return }
        if let id = systemSound(for: effect) {
            AudioServicesPlaySystemSound(id)
        } else {
            NSSound(named: NSSound.Name(effect.name))?.play()
        }
    }

    /// Registers the macOS sound file once and reuses its ID.
    private static func systemSound(for effect: Effect) -> SystemSoundID? {
        if let id = systemSounds[effect] { return id }
        let url = URL(fileURLWithPath: "/System/Library/Sounds/\(effect.name).aiff")
        var id: SystemSoundID = 0
        guard FileManager.default.fileExists(atPath: url.path),
              AudioServicesCreateSystemSoundID(url as CFURL, &id) == kAudioServicesNoError else { return nil }
        systemSounds[effect] = id
        return id
    }
}
