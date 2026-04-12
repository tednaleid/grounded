import Foundation

/// Port for delivering macOS notifications. The `UNUserNotificationCenter`
/// adapter is the production implementation; tests use
/// `RecordingNotificationSink`.
protocol NotificationSink: Sendable {
    /// Ask the user for notification permission. Called once at launch.
    /// Returns whether authorization was granted.
    func requestAuthorization() async -> Bool

    /// Deliver a notification. Safe to call even if authorization was
    /// denied — the adapter silently drops the call in that case.
    func deliver(title: String, body: String) async
}
