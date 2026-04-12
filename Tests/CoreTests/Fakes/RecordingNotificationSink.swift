import Foundation

/// Fake `NotificationSink` that records every delivered notification so
/// tests can assert exactly what fired. Also exposes an
/// `authorizationResponse` override so tests can simulate denied auth.
actor RecordingNotificationSink: NotificationSink {
    struct DeliveredNotification: Sendable, Equatable {
        let title: String
        let body: String
    }

    private(set) var delivered: [DeliveredNotification] = []
    private(set) var authorizationRequestCount = 0
    private let authorizationResponse: Bool

    init(authorizationResponse: Bool = true) {
        self.authorizationResponse = authorizationResponse
    }

    func requestAuthorization() async -> Bool {
        authorizationRequestCount += 1
        return authorizationResponse
    }

    func deliver(title: String, body: String) async {
        delivered.append(DeliveredNotification(title: title, body: body))
    }
}
