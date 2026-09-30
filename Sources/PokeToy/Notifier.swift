import AppKit
import UserNotifications

/// Posts the Pomodoro notifications (with a sound, even while PokeToy is in front).
@MainActor
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    private var ready = false

    /// Asks for permission the first time a timer starts (touching the notification center only once needed).
    func prepare() {
        guard !ready else { return }
        ready = true
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func post(title: String, body: String, notify: Bool = true, sound: Bool = true) {
        if sound { NSSound(named: "Glass")?.play() }  // also when notifications are turned off in System Settings
        guard notify else { return }
        prepare()
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: content,
                                                                     trigger: nil))
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list])
    }
}
