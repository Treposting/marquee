import AppKit
import UserNotifications

/// Tells the user about a new version found in the background: one macOS notification per
/// version (if they allow notifications). Clicking it opens the update window.
@MainActor
enum UpdateNotifier {
    private static let delegate = Delegate()
    private static let notifiedKey = "notifiedUpdateVersion"

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

    private final class Delegate: NSObject, UNUserNotificationCenterDelegate {
        func userNotificationCenter(_ center: UNUserNotificationCenter,
                                    didReceive response: UNNotificationResponse) async {
            await MainActor.run { Updater.shared.showWindow() }
        }

        /// Shows the banner even while Marquee's own window is in front.
        func userNotificationCenter(_ center: UNUserNotificationCenter,
                                    willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
            [.banner, .sound]
        }
    }
}
