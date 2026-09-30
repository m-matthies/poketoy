import AppKit
import UserNotifications

/// Posts the Pomodoro notifications (with a sound, even while PokeToy is in front), and schedules them ahead with
/// macOS while PokeToy can't tick (screen locked, or quit with timers running).
@MainActor
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    private nonisolated static let prefix = "pomodoro-"
    private var ready = false

    /// Notifications need a real app bundle (a bare debug executable would crash asking for them).
    private var available: Bool {
        Bundle.main.bundleIdentifier != nil && Bundle.main.bundleURL.pathExtension == "app"
    }

    /// Asks for permission the first time a timer starts (touching the notification center only once needed).
    func prepare() {
        guard !ready, available else { return }
        ready = true
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    /// Posts now — unless macOS already showed this very one (scheduled ahead while PokeToy wasn't ticking).
    func post(id: String, title: String, body: String, notify: Bool = true, sound: Bool = true) {
        guard notify, available else {
            if sound { NSSound(named: "Glass")?.play() }
            return
        }
        prepare()
        let center = UNUserNotificationCenter.current()
        center.getDeliveredNotifications { delivered in
            let alreadyShown = delivered.contains { $0.request.identifier == Self.prefix + id }
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard !alreadyShown else { return }
                    if sound { NSSound(named: "Glass")?.play() }
                    self.add(id: id, title: title, body: body, sound: false, trigger: nil)
                }
            }
        }
    }

    /// Hands a notification to macOS to show at `date` (with its sound) even if PokeToy isn't running then.
    func schedule(id: String, title: String, body: String, at date: Date, sound: Bool) {
        guard available, date > Date() else { return }
        prepare()
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: date.timeIntervalSinceNow, repeats: false)
        add(id: id, title: title, body: body, sound: sound, trigger: trigger)
    }

    /// PokeToy is ticking again: it announces sessions itself.
    func cancelScheduled() {
        guard available else { return }
        UNUserNotificationCenter.current().getPendingNotificationRequests { requests in
            let ids = requests.map(\.identifier).filter { $0.hasPrefix(Self.prefix) }
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
        }
    }

    private func add(id: String, title: String, body: String, sound: Bool, trigger: UNNotificationTrigger?) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        if sound { content.sound = UNNotificationSound(named: UNNotificationSoundName("Glass.aiff")) }
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: Self.prefix + id, content: content,
                                                                     trigger: trigger))
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list])
    }
}
