import Foundation

/// Tunable monitoring parameters for `ChargerMonitor`. Defaults come from the
/// contract: poll every 10 minutes, tolerate 3 consecutive transient failures
/// before raising an error, retry each tick up to 2 extra times with 2s and 6s
/// backoff.
struct MonitoringConfig: Sendable, Equatable {
    let pollInterval: TimeInterval
    let failureThreshold: Int
    let inTickRetryDelays: [TimeInterval]

    static let `default` = MonitoringConfig(
        pollInterval: 600,
        failureThreshold: 3,
        inTickRetryDelays: [2, 6]
    )
}
