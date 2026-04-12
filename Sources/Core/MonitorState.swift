import Foundation

/// Everything the monitor needs to know about the current polling loop: the
/// user-visible state, the last successful snapshot (for the menu's
/// "last successful check" line), and the failure count feeding into the
/// threshold machinery. All fields are pure Foundation values.
struct MonitorState: Sendable, Equatable {
    let visibleState: ChargerState
    let lastSuccessfulSnapshot: HomeChargerSnapshot?
    let lastSuccessAt: Date?
    let lastAttemptAt: Date?
    let consecutiveFailureCount: Int

    static let initial = MonitorState(
        visibleState: .unknown,
        lastSuccessfulSnapshot: nil,
        lastSuccessAt: nil,
        lastAttemptAt: nil,
        consecutiveFailureCount: 0
    )

    func withSuccess(
        snapshot: HomeChargerSnapshot,
        visibleState: ChargerState,
        at date: Date
    ) -> MonitorState {
        MonitorState(
            visibleState: visibleState,
            lastSuccessfulSnapshot: snapshot,
            lastSuccessAt: date,
            lastAttemptAt: date,
            consecutiveFailureCount: 0
        )
    }

    func withFailure(_ category: APIErrorCategory, at date: Date) -> MonitorState {
        _ = category  // reserved for future per-category metrics
        return MonitorState(
            visibleState: visibleState,
            lastSuccessfulSnapshot: lastSuccessfulSnapshot,
            lastSuccessAt: lastSuccessAt,
            lastAttemptAt: date,
            consecutiveFailureCount: consecutiveFailureCount + 1
        )
    }

    func withVisibleState(_ new: ChargerState) -> MonitorState {
        MonitorState(
            visibleState: new,
            lastSuccessfulSnapshot: lastSuccessfulSnapshot,
            lastSuccessAt: lastSuccessAt,
            lastAttemptAt: lastAttemptAt,
            consecutiveFailureCount: consecutiveFailureCount
        )
    }

    func withFailureCountReset() -> MonitorState {
        MonitorState(
            visibleState: visibleState,
            lastSuccessfulSnapshot: lastSuccessfulSnapshot,
            lastSuccessAt: lastSuccessAt,
            lastAttemptAt: lastAttemptAt,
            consecutiveFailureCount: 0
        )
    }
}
