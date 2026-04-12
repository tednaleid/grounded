import Foundation
import Testing

@Suite("MonitoringTick")
struct MonitoringTickTests {
    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)
    private let config = MonitoringConfig.default

    private func snapshot(
        plugged: Bool = false,
        session: ActiveSessionInfo? = nil,
        connected: Bool = true
    ) -> HomeChargerSnapshot {
        HomeChargerSnapshot(
            chargerId: 13836601,
            isConnected: connected,
            isPluggedIn: plugged,
            chargingStatus: "AVAILABLE",
            activeSession: session
        )
    }

    private func runTick(
        _ state: MonitorState,
        _ result: Result<HomeChargerSnapshot, APIErrorCategory>,
        at offset: TimeInterval
    ) -> TickOutcome {
        MonitoringTick.tick(
            previous: state,
            result: result,
            at: t0.addingTimeInterval(offset),
            config: config
        )
    }

    // MARK: - First tick from .unknown

    @Test("first tick from .unknown with success classifies and stays silent")
    func baselineSuccessIsSilent() {
        let outcome = MonitoringTick.tick(
            previous: .initial,
            result: .success(snapshot(plugged: false)),
            at: t0,
            config: config
        )
        #expect(outcome.newState.visibleState == .healthyIdle)
        #expect(outcome.newState.consecutiveFailureCount == 0)
        #expect(outcome.transition?.to == .healthyIdle)
        #expect(outcome.notification == nil)  // baseline: silent
    }

    @Test("first tick from .unknown with transient failure stays .unknown, count = 1, no notification")
    func baselineTransientFailure() {
        let outcome = MonitoringTick.tick(
            previous: .initial,
            result: .failure(.networkFailure),
            at: t0,
            config: config
        )
        #expect(outcome.newState.visibleState == .unknown)
        #expect(outcome.newState.consecutiveFailureCount == 1)
        #expect(outcome.notification == nil)
    }

    @Test("first tick from .unknown with auth failure transitions immediately to .signedOut with notification")
    func baselineAuthFailureIsImmediate() {
        let outcome = MonitoringTick.tick(
            previous: .initial,
            result: .failure(.authFailure),
            at: t0,
            config: config
        )
        #expect(outcome.newState.visibleState == .signedOut)
        #expect(outcome.notification?.body == "Sign in to ChargePoint")
    }

    @Test("first tick from .unknown with Datadome bot-block transitions to .signedOut")
    func baselineBotBlockedIsImmediate() {
        let outcome = MonitoringTick.tick(
            previous: .initial,
            result: .failure(.botBlocked),
            at: t0,
            config: config
        )
        #expect(outcome.newState.visibleState == .signedOut)
        #expect(outcome.notification?.body == "Sign in to ChargePoint")
    }

    // MARK: - Threshold machinery

    @Test("1 failure from .healthyIdle stays silent, count = 1")
    func oneFailureSilent() {
        let previous = MonitorState.initial
            .withSuccess(snapshot: snapshot(), visibleState: .healthyIdle, at: t0)
        let outcome = MonitoringTick.tick(
            previous: previous,
            result: .failure(.networkFailure),
            at: t0.addingTimeInterval(600),
            config: config
        )
        #expect(outcome.newState.visibleState == .healthyIdle)
        #expect(outcome.newState.consecutiveFailureCount == 1)
        #expect(outcome.notification == nil)
    }

    @Test("2 failures stay silent, count = 2")
    func twoFailuresSilent() {
        var state = MonitorState.initial
            .withSuccess(snapshot: snapshot(), visibleState: .healthyIdle, at: t0)
        state = runTick(state, .failure(.networkFailure), at: 600).newState
        let outcome = runTick(state, .failure(.networkFailure), at: 1200)
        #expect(outcome.newState.visibleState == .healthyIdle)
        #expect(outcome.newState.consecutiveFailureCount == 2)
        #expect(outcome.notification == nil)
    }

    @Test("3 failures transition to .error exactly once, notification fires")
    func threeFailuresTripThreshold() {
        var state = MonitorState.initial
            .withSuccess(snapshot: snapshot(), visibleState: .healthyIdle, at: t0)
        state = runTick(state, .failure(.networkFailure), at: 600).newState
        state = runTick(state, .failure(.networkFailure), at: 1200).newState
        let outcome = runTick(state, .failure(.networkFailure), at: 1800)
        guard case .error = outcome.newState.visibleState else {
            Issue.record("expected .error, got \(outcome.newState.visibleState)")
            return
        }
        #expect(outcome.newState.consecutiveFailureCount == 3)
        #expect(outcome.notification != nil)
        #expect(outcome.notification?.body.contains("3 failed checks") == true)
    }

    @Test("4th, 5th, 6th failures after .error entry do NOT fire duplicate notifications")
    func noDuplicateErrorNotifications() {
        let state = MonitorState(
            visibleState: .error("Charger unreachable"),
            lastSuccessfulSnapshot: nil,
            lastSuccessAt: nil,
            lastAttemptAt: t0,
            consecutiveFailureCount: 3
        )
        let fourth = runTick(state, .failure(.networkFailure), at: 600)
        #expect(fourth.newState.consecutiveFailureCount == 4)
        #expect(fourth.notification == nil)
        let fifth = runTick(fourth.newState, .failure(.networkFailure), at: 1200)
        #expect(fifth.notification == nil)
    }

    @Test("recovery from .error fires recovery notification and resets count")
    func recoveryFromError() {
        let previous = MonitorState(
            visibleState: .error("Charger unreachable"),
            lastSuccessfulSnapshot: nil,
            lastSuccessAt: nil,
            lastAttemptAt: t0,
            consecutiveFailureCount: 4
        )
        let outcome = MonitoringTick.tick(
            previous: previous,
            result: .success(snapshot(plugged: false)),
            at: t0.addingTimeInterval(600),
            config: config
        )
        #expect(outcome.newState.visibleState == .healthyIdle)
        #expect(outcome.newState.consecutiveFailureCount == 0)
        #expect(outcome.notification?.body == "Charger reachable again")
    }

    @Test("1 transient failure followed by success resets count silently")
    func transientFailureSilentReset() {
        var state = MonitorState.initial
            .withSuccess(snapshot: snapshot(), visibleState: .healthyIdle, at: t0)
        state = runTick(state, .failure(.networkFailure), at: 600).newState
        let outcome = runTick(state, .success(snapshot(plugged: false)), at: 1200)
        #expect(outcome.newState.visibleState == .healthyIdle)
        #expect(outcome.newState.consecutiveFailureCount == 0)
        #expect(outcome.notification == nil)
    }

    // MARK: - Auth fast-path bypasses threshold from ANY state

    @Test("auth failure from .healthyIdle transitions to .signedOut immediately")
    func authFailureFromHealthyIsImmediate() {
        let previous = MonitorState.initial
            .withSuccess(snapshot: snapshot(), visibleState: .healthyIdle, at: t0)
        let outcome = MonitoringTick.tick(
            previous: previous,
            result: .failure(.authFailure),
            at: t0.addingTimeInterval(600),
            config: config
        )
        #expect(outcome.newState.visibleState == .signedOut)
        #expect(outcome.notification?.body == "Sign in to ChargePoint")
    }

    // MARK: - Plug / unplug cycles

    @Test("plug: healthyIdle -> healthyPluggedIn fires 'Car plugged in'")
    func plugInNotifies() {
        let previous = MonitorState.initial
            .withSuccess(snapshot: snapshot(plugged: false), visibleState: .healthyIdle, at: t0)
        let outcome = MonitoringTick.tick(
            previous: previous,
            result: .success(snapshot(plugged: true, session: nil)),
            at: t0.addingTimeInterval(600),
            config: config
        )
        #expect(outcome.newState.visibleState == .healthyPluggedIn)
        #expect(outcome.notification?.body == "Car plugged in")
    }

    @Test("charge start: healthyPluggedIn -> activelyCharging fires 'Charging started'")
    func chargeStartNotifies() {
        let previous = MonitorState.initial
            .withSuccess(snapshot: snapshot(plugged: true), visibleState: .healthyPluggedIn, at: t0)
        let outcome = MonitoringTick.tick(
            previous: previous,
            result: .success(snapshot(plugged: true, session: ActiveSessionInfo(sessionId: 1, state: "in_use"))),
            at: t0.addingTimeInterval(600),
            config: config
        )
        #expect(outcome.newState.visibleState == .activelyCharging)
        #expect(outcome.notification?.body == "Charging started")
    }

    @Test("fully charged: activelyCharging -> healthyPluggedIn fires 'Fully charged'")
    func fullyChargedNotifies() {
        let previous = MonitorState.initial
            .withSuccess(
                snapshot: snapshot(plugged: true, session: ActiveSessionInfo(sessionId: 1, state: "in_use")),
                visibleState: .activelyCharging,
                at: t0
            )
        let outcome = MonitoringTick.tick(
            previous: previous,
            result: .success(snapshot(plugged: true, session: ActiveSessionInfo(sessionId: 1, state: "fully_charged"))),
            at: t0.addingTimeInterval(600),
            config: config
        )
        #expect(outcome.newState.visibleState == .healthyPluggedIn)
        #expect(outcome.notification?.body == "Fully charged")
    }

    @Test("unplug: healthyPluggedIn -> healthyIdle fires 'Car unplugged'")
    func unplugNotifies() {
        let previous = MonitorState.initial
            .withSuccess(snapshot: snapshot(plugged: true), visibleState: .healthyPluggedIn, at: t0)
        let outcome = MonitoringTick.tick(
            previous: previous,
            result: .success(snapshot(plugged: false)),
            at: t0.addingTimeInterval(600),
            config: config
        )
        #expect(outcome.newState.visibleState == .healthyIdle)
        #expect(outcome.notification?.body == "Car unplugged")
    }

    // MARK: - No-op same-state tick

    @Test("successful same-state tick is silent")
    func sameStateSuccessIsSilent() {
        let previous = MonitorState.initial
            .withSuccess(snapshot: snapshot(), visibleState: .healthyIdle, at: t0)
        let outcome = MonitoringTick.tick(
            previous: previous,
            result: .success(snapshot()),
            at: t0.addingTimeInterval(600),
            config: config
        )
        #expect(outcome.newState.visibleState == .healthyIdle)
        #expect(outcome.notification == nil)
    }
}
