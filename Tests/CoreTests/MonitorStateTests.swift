import Foundation
import Testing

@Suite("MonitorState")
struct MonitorStateTests {
    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)

    private var snapshot: HomeChargerSnapshot {
        HomeChargerSnapshot(
            chargerId: 1,
            isConnected: true,
            isPluggedIn: false,
            chargingStatus: "AVAILABLE",
            activeSession: nil
        )
    }

    @Test("initial state is unknown with zero failures and no history")
    func initialState() {
        let state = MonitorState.initial
        #expect(state.visibleState == .unknown)
        #expect(state.consecutiveFailureCount == 0)
        #expect(state.lastSuccessfulSnapshot == nil)
        #expect(state.lastSuccessAt == nil)
        #expect(state.lastAttemptAt == nil)
    }

    @Test("withSuccess stamps attempt + success timestamps and clears failure count")
    func withSuccessResetsCounters() {
        let state = MonitorState.initial
            .withFailure(.networkFailure, at: t0)
            .withSuccess(snapshot: snapshot, visibleState: .healthyIdle, at: t0.addingTimeInterval(60))
        #expect(state.visibleState == .healthyIdle)
        #expect(state.consecutiveFailureCount == 0)
        #expect(state.lastSuccessfulSnapshot == snapshot)
        #expect(state.lastSuccessAt == t0.addingTimeInterval(60))
        #expect(state.lastAttemptAt == t0.addingTimeInterval(60))
    }

    @Test("withFailure increments the count and stamps only the attempt timestamp")
    func withFailureIncrementsCount() {
        let first = MonitorState.initial.withFailure(.networkFailure, at: t0)
        #expect(first.consecutiveFailureCount == 1)
        #expect(first.lastAttemptAt == t0)
        #expect(first.lastSuccessAt == nil)

        let second = first.withFailure(.networkFailure, at: t0.addingTimeInterval(600))
        #expect(second.consecutiveFailureCount == 2)
        #expect(second.lastAttemptAt == t0.addingTimeInterval(600))
    }

    @Test("withFailure preserves the last successful snapshot and timestamp")
    func failurePreservesSuccessHistory() {
        let state = MonitorState.initial
            .withSuccess(snapshot: snapshot, visibleState: .healthyIdle, at: t0)
            .withFailure(.networkFailure, at: t0.addingTimeInterval(600))
        #expect(state.lastSuccessfulSnapshot == snapshot)
        #expect(state.lastSuccessAt == t0)
        #expect(state.visibleState == .healthyIdle)
    }

    @Test("withVisibleState only changes the visible state")
    func withVisibleState() {
        let state = MonitorState.initial
            .withFailure(.networkFailure, at: t0)
            .withVisibleState(.signedOut)
        #expect(state.visibleState == .signedOut)
        #expect(state.consecutiveFailureCount == 1)
    }
}
