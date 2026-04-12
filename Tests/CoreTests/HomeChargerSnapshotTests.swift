import Foundation
import Testing

@Suite("HomeChargerSnapshot")
struct HomeChargerSnapshotTests {
    @Test("plugged-in snapshot with no session preserves field values")
    func pluggedNoSession() {
        let snapshot = HomeChargerSnapshot(
            chargerId: 13836601,
            isConnected: true,
            isPluggedIn: true,
            chargingStatus: "AVAILABLE",
            activeSession: nil
        )
        #expect(snapshot.isConnected)
        #expect(snapshot.isPluggedIn)
        #expect(snapshot.activeSession == nil)
        #expect(snapshot.chargingStatus == "AVAILABLE")
    }

    @Test("active-session snapshot carries session state")
    func withActiveSession() {
        let snapshot = HomeChargerSnapshot(
            chargerId: 13836601,
            isConnected: true,
            isPluggedIn: true,
            chargingStatus: "AVAILABLE",
            activeSession: ActiveSessionInfo(sessionId: 42, state: "in_use")
        )
        #expect(snapshot.activeSession?.sessionId == 42)
        #expect(snapshot.activeSession?.state == "in_use")
    }

    @Test("snapshots with identical fields are equal")
    func equality() {
        let a = HomeChargerSnapshot(
            chargerId: 1,
            isConnected: true,
            isPluggedIn: false,
            chargingStatus: "AVAILABLE",
            activeSession: nil
        )
        let b = HomeChargerSnapshot(
            chargerId: 1,
            isConnected: true,
            isPluggedIn: false,
            chargingStatus: "AVAILABLE",
            activeSession: nil
        )
        #expect(a == b)
    }

    @Test("ActiveSessionInfo equality compares sessionId and state")
    func activeSessionEquality() {
        let a = ActiveSessionInfo(sessionId: 1, state: "in_use")
        let b = ActiveSessionInfo(sessionId: 1, state: "in_use")
        let c = ActiveSessionInfo(sessionId: 1, state: "fully_charged")
        #expect(a == b)
        #expect(a != c)
    }
}
