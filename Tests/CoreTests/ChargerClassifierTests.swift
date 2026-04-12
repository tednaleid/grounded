import Testing

@Suite("ChargerClassifier")
struct ChargerClassifierTests {
    private func snapshot(
        connected: Bool = true,
        plugged: Bool = false,
        chargingStatus: String = "AVAILABLE",
        session: ActiveSessionInfo? = nil
    ) -> HomeChargerSnapshot {
        HomeChargerSnapshot(
            chargerId: 13836601,
            isConnected: connected,
            isPluggedIn: plugged,
            chargingStatus: chargingStatus,
            activeSession: session
        )
    }

    @Test("idle, not plugged → healthyIdle")
    func idleNotPlugged() {
        let state = ChargerClassifier.classify(snapshot(plugged: false))
        #expect(state == .healthyIdle)
    }

    @Test("plugged, no session → healthyPluggedIn")
    func pluggedNoSession() {
        let state = ChargerClassifier.classify(snapshot(plugged: true, session: nil))
        #expect(state == .healthyPluggedIn)
    }

    @Test("plugged, session state = in_use → activelyCharging")
    func activelyCharging() {
        let state = ChargerClassifier.classify(
            snapshot(
                plugged: true,
                session: ActiveSessionInfo(sessionId: 1, state: "in_use")
            )
        )
        #expect(state == .activelyCharging)
    }

    @Test("plugged, session state = fully_charged → healthyPluggedIn")
    func fullyCharged() {
        let state = ChargerClassifier.classify(
            snapshot(
                plugged: true,
                session: ActiveSessionInfo(sessionId: 1, state: "fully_charged")
            )
        )
        #expect(state == .healthyPluggedIn)
    }

    @Test("offline → error with 'Charger offline' reason")
    func offline() {
        let state = ChargerClassifier.classify(snapshot(connected: false))
        #expect(state == .error("Charger offline"))
    }

    @Test("offline trumps plugged and session state")
    func offlineTrumpsOthers() {
        let state = ChargerClassifier.classify(
            snapshot(
                connected: false,
                plugged: true,
                session: ActiveSessionInfo(sessionId: 1, state: "in_use")
            )
        )
        #expect(state == .error("Charger offline"))
    }

    @Test("plugged, unknown session state → error with raw state in reason")
    func unknownSessionState() {
        let state = ChargerClassifier.classify(
            snapshot(
                plugged: true,
                session: ActiveSessionInfo(sessionId: 1, state: "flux_capacitor_overload")
            )
        )
        guard case let .error(reason) = state else {
            Issue.record("expected .error, got \(state)")
            return
        }
        #expect(reason.contains("flux_capacitor_overload"))
    }
}
