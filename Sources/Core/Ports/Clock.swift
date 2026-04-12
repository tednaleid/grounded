import Foundation

/// Port for wall-clock time and async sleeping. The production adapter is
/// `SystemClock` (wraps `Date()` and `Task.sleep`); tests use `ManualClock`
/// which advances on command.
///
/// Named `GroundedClock` to avoid colliding with Swift's standard
/// `Swift.Clock` protocol (available since Swift 5.7 for `ContinuousClock`
/// et al.). Using the unqualified name would force every import site to
/// disambiguate.
protocol GroundedClock: Sendable {
    func now() async -> Date
    func sleep(for duration: Duration) async throws
}
