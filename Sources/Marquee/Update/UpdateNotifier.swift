import AppKit
import UserNotifications

/// Tells the user about a new version found in the background: one macOS notification per
/// version (if they allow notifications). Clicking it opens the update window. Also says once
/// that Marquee for Windows exists.
@MainActor
enum UpdateNotifier {
    private static let delegate = Delegate()
    private static let notifiedKey = "notifiedUpdateVersion"
    private static let windowsKey = "announcedWindowsPreview"
    private static let windowsID = "marquee.windows"
    /// The site's Windows section, which links the newest Windows preview.
    static let windowsURL = URL(string: "https://treposting.github.io/marquee/#windows")!

    /// Call once at launch so clicks on Marquee's notifications reach it.
    static func setUp() {
        UNUserNotificationCenter.current().delegate = delegate
    }

    static func announce(version: String) {
        guard Preferences.notifyUpdates,
              UserDefaults.standard.string(forKey: notifiedKey) != version else { return }
        UserDefaults.standard.set(version, forKey: notifiedKey)
        Task {
            let center = UNUserNotificationCenter.current()
            // macOS asks the first time; after that the user's choice in System Settings applies.
            guard (try? await center.requestAuthorization(options: [.alert, .sound])) == true else { return }
            let content = UNMutableNotificationContent()
            content.title = "Marquee \(version) is available"
            content.body = "Click to see what's new and install it."
            content.sound = .default
            try? await center.add(UNNotificationRequest(identifier: "marquee.update", content: content, trigger: nil))
        }
    }

    /// One notification, ever, about the Windows preview. Skipped for people who turned off
    /// update notifications.
    static func announceWindowsPreview() {
        guard Preferences.notifyUpdates, !UserDefaults.standard.bool(forKey: windowsKey) else { return }
        UserDefaults.standard.set(true, forKey: windowsKey)
        Task {
            let center = UNUserNotificationCenter.current()
            guard (try? await center.requestAuthorization(options: [.alert, .sound])) == true else { return }
            let content = UNMutableNotificationContent()
            content.title = "Marquee is coming to Windows"
            content.body = "An early preview is out for Windows 10 and 11. Click to get it or share it."
            try? await center.add(UNNotificationRequest(identifier: windowsID, content: content, trigger: nil))
        }
    }

    private final class Delegate: NSObject, UNUserNotificationCenterDelegate {
        func userNotificationCenter(_ center: UNUserNotificationCenter,
                                    didReceive response: UNNotificationResponse) async {
            let id = response.notification.request.identifier
            await MainActor.run {
                if id == UpdateNotifier.windowsID {
                    NSWorkspace.shared.open(UpdateNotifier.windowsURL)
                } else {
                    Updater.shared.showWindow()
                }
            }
        }

        /// Shows the banner even while Marquee's own window is in front.
        func userNotificationCenter(_ center: UNUserNotificationCenter,
                                    willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
            [.banner, .sound]
        }
    }
}
