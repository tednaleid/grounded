import Foundation

/// Deterministic fake `GroundedClock` for integration tests. `now()` returns
/// whatever the test last set via `set(_:)` or `advance(by:)`. `sleep`
/// suspends until the test manually advances to (or past) the target
/// time — no real wall-clock delay.
///
/// Usage pattern in tests:
///     let clock = ManualClock(t0: start)
///     let monitor = ChargerMonitor(clock: clock, ...)
///     Task { await monitor.run() }
///     await clock.advance(by: .seconds(600))  // triggers the next tick
actor ManualClock: GroundedClock {
    private var current: Date
    private var waiters: [(deadline: Date, continuation: CheckedContinuation<Void, Never>)] = []

    init(t0: Date) {
        self.current = t0
    }

    func now() -> Date { current }

    func sleep(for duration: Duration) async throws {
        let deadline = current.addingTimeInterval(Double(duration.components.seconds))
        if current >= deadline {
            return
        }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            waiters.append((deadline, continuation))
        }
    }

    func set(_ newTime: Date) {
        current = newTime
        drainWaiters()
    }

    func advance(by duration: Duration) {
        current = current.addingTimeInterval(Double(duration.components.seconds))
        drainWaiters()
    }

    private func drainWaiters() {
        let deadline = current
        var remaining: [(deadline: Date, continuation: CheckedContinuation<Void, Never>)] = []
        for waiter in waiters {
            if waiter.deadline <= deadline {
                waiter.continuation.resume()
            } else {
                remaining.append(waiter)
            }
        }
        waiters = remaining
    }
}
