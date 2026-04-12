import Foundation
import UserNotifications

/// Production `NotificationSink` that delivers via
/// `UNUserNotificationCenter`. macOS groups notifications with the same
/// title into Notification Center. If the user denied authorization,
/// `deliver(...)` silently drops the request — the inspect endpoint can
/// still drive fake state transitions for debugging.
struct UNCenterNotificationSink: NotificationSink {
    // `UNUserNotificationCenter` is a non-Sendable reference type, so
    // we don't store it — instead each method fetches `.current()`
    // directly. This matches Apple's recommended usage pattern and
    // keeps the sink trivially Sendable.

    func requestAuthorization() async -> Bool {
        do {
            return try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            return false
        }
    }

    func deliver(title: String, body: String) async {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        // `nil` trigger = deliver immediately.
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )

        do {
            try await UNUserNotificationCenter.current().add(request)
        } catch {
            // Authorization denied or delivery failed — log via NSLog
            // so the debug build shows it but don't throw; this path
            // must be non-fatal so the monitoring loop keeps running.
            NSLog("grounded: notification delivery failed: \(error)")
        }
    }
}
