import Foundation
import Testing

@Suite("SystemClock")
struct SystemClockTests {
    @Test("now() is within a tolerance of Date()")
    func nowIsWallClock() async {
        let clock = SystemClock()
        let before = Date()
        let clockNow = await clock.now()
        let after = Date()
        #expect(clockNow >= before.addingTimeInterval(-0.1))
        #expect(clockNow <= after.addingTimeInterval(0.1))
    }

    @Test("sleep suspends approximately the requested duration")
    func sleepDuration() async throws {
        let clock = SystemClock()
        let before = Date()
        try await clock.sleep(for: .milliseconds(50))
        let elapsed = Date().timeIntervalSince(before)
        #expect(elapsed >= 0.04, "elapsed=\(elapsed)")
        #expect(elapsed < 0.5, "elapsed=\(elapsed)")
    }
}
