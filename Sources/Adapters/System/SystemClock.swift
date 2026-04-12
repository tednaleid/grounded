import Foundation

/// Production `GroundedClock` — wraps `Date()` and `Task.sleep`.
/// Tests use `ManualClock` for determinism.
struct SystemClock: GroundedClock {
    func now() async -> Date {
        Date()
    }

    func sleep(for duration: Duration) async throws {
        try await Task.sleep(for: duration)
    }
}
