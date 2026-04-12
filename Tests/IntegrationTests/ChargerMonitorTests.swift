import Foundation
import Testing

@Suite("ChargerMonitor integration")
struct ChargerMonitorTests {
    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)

    private func idleSnapshot() -> HomeChargerSnapshot {
        HomeChargerSnapshot(
            chargerId: 13836601,
            isConnected: true,
            isPluggedIn: false,
            chargingStatus: "AVAILABLE",
            activeSession: nil
        )
    }

    private func pluggedSnapshot(session: ActiveSessionInfo? = nil) -> HomeChargerSnapshot {
        HomeChargerSnapshot(
            chargerId: 13836601,
            isConnected: true,
            isPluggedIn: true,
            chargingStatus: "AVAILABLE",
            activeSession: session
        )
    }

    private struct TestEnvironment {
        let monitor: ChargerMonitor
        let statusSource: QueuedChargerStatusSource
        let credentialStore: InMemoryCredentialStore
        let notificationSink: RecordingNotificationSink
        let clock: ManualClock
        let observer: RecordingStateObserver
    }

    private func makeMonitor(
        statusResults: [Result<HomeChargerSnapshot, APIErrorCategory>] = [],
        credentials: Credentials? = Credentials(
            email: "test@example.com",
            token: "abc",
            region: "NA-US",
            userId: 1,
            chargerId: 13836601,
            accountsEndpoint: "https://account.chargepoint.test/account/",
            hcpoHcmEndpoint: "https://hcpo.chargepoint.test/",
            mapcacheEndpoint: "https://mapcache.chargepoint.test/"
        )
    ) async -> TestEnvironment {
        let clock = ManualClock(t0: t0)
        let statusSource = QueuedChargerStatusSource(results: statusResults)
        let credentialStore = InMemoryCredentialStore(preload: credentials)
        let notificationSink = RecordingNotificationSink()
        let observer = RecordingStateObserver()
        let monitor = ChargerMonitor(
            statusSource: statusSource,
            credentialStore: credentialStore,
            notificationSink: notificationSink,
            clock: clock
        )
        await monitor.addObserver(observer)
        return TestEnvironment(
            monitor: monitor,
            statusSource: statusSource,
            credentialStore: credentialStore,
            notificationSink: notificationSink,
            clock: clock,
            observer: observer
        )
    }

    // MARK: - Happy path

    @Test("baseline success is silent, subsequent plug-in notifies")
    func baselineSilentThenPlugIn() async {
        let env = await makeMonitor(statusResults: [
            .success(idleSnapshot()),
            .success(pluggedSnapshot(session: nil))
        ])
        await env.monitor.performTick()
        let delivered0 = await env.notificationSink.delivered
        #expect(delivered0.isEmpty, "baseline should be silent")
        let state0 = await env.monitor.currentState().visibleState
        #expect(state0 == .healthyIdle)

        await env.monitor.performTick()
        let delivered1 = await env.notificationSink.delivered
        #expect(delivered1.count == 1)
        #expect(delivered1.first?.body == "Car plugged in")
        let state1 = await env.monitor.currentState().visibleState
        #expect(state1 == .healthyPluggedIn)
    }

    // MARK: - Flaky network (below threshold)

    @Test("one transient failure then success: no notification, state unchanged")
    func flakyNetworkAbsorbed() async {
        let env = await makeMonitor(statusResults: [
            .success(idleSnapshot()),            // baseline
            .failure(.networkFailure),           // blip
            .success(idleSnapshot())             // recovery
        ])
        await env.monitor.performTick()
        await env.monitor.performTick()
        await env.monitor.performTick()
        let delivered = await env.notificationSink.delivered
        #expect(delivered.isEmpty)
        let state = await env.monitor.currentState()
        #expect(state.visibleState == .healthyIdle)
        #expect(state.consecutiveFailureCount == 0)
    }

    // MARK: - Real outage

    @Test("3 consecutive failures: error notification fires exactly once")
    func threeFailuresTripThreshold() async {
        let env = await makeMonitor(statusResults: [
            .success(idleSnapshot()),
            .failure(.networkFailure),
            .failure(.networkFailure),
            .failure(.networkFailure)
        ])
        for _ in 0..<4 {
            await env.monitor.performTick()
        }
        let delivered = await env.notificationSink.delivered
        #expect(delivered.count == 1)
        #expect(delivered.first?.body.contains("3 failed checks") == true)
        let state = await env.monitor.currentState()
        if case .error = state.visibleState {
            // expected
        } else {
            Issue.record("expected .error, got \(state.visibleState)")
        }
    }

    @Test("4th, 5th, 6th failures do NOT fire duplicate error notifications")
    func noDuplicateErrorNotifications() async {
        let env = await makeMonitor(statusResults: [
            .success(idleSnapshot()),
            .failure(.networkFailure),
            .failure(.networkFailure),
            .failure(.networkFailure),   // threshold crossed -> notify
            .failure(.networkFailure),   // no duplicate
            .failure(.networkFailure),
            .failure(.networkFailure)
        ])
        for _ in 0..<7 {
            await env.monitor.performTick()
        }
        let delivered = await env.notificationSink.delivered
        #expect(delivered.count == 1, "expected exactly one error notification, got \(delivered.count)")
    }

    @Test("recovery from error fires 'Charger reachable again'")
    func recoveryAfterError() async {
        let env = await makeMonitor(statusResults: [
            .success(idleSnapshot()),
            .failure(.networkFailure),
            .failure(.networkFailure),
            .failure(.networkFailure),   // -> .error + notification
            .success(idleSnapshot())     // recovery
        ])
        for _ in 0..<5 {
            await env.monitor.performTick()
        }
        let delivered = await env.notificationSink.delivered
        #expect(delivered.count == 2)
        #expect(delivered.last?.body == "Charger reachable again")
        let state = await env.monitor.currentState()
        #expect(state.visibleState == .healthyIdle)
        #expect(state.consecutiveFailureCount == 0)
    }

    // MARK: - Auth fast-path

    @Test("auth failure fast-paths to .signedOut with notification")
    func authFailureFastPath() async {
        let env = await makeMonitor(statusResults: [
            .success(idleSnapshot()),
            .failure(.authFailure)
        ])
        await env.monitor.performTick()
        await env.monitor.performTick()
        let delivered = await env.notificationSink.delivered
        #expect(delivered.count == 1)
        #expect(delivered.first?.body == "Sign in to ChargePoint")
        let state = await env.monitor.currentState().visibleState
        #expect(state == .signedOut)
    }

    @Test("Datadome bot-block fast-paths to .signedOut")
    func datadomeFastPath() async {
        let env = await makeMonitor(statusResults: [
            .success(idleSnapshot()),
            .failure(.botBlocked)
        ])
        await env.monitor.performTick()
        await env.monitor.performTick()
        let delivered = await env.notificationSink.delivered
        #expect(delivered.last?.body == "Sign in to ChargePoint")
        let state = await env.monitor.currentState().visibleState
        #expect(state == .signedOut)
    }

    // MARK: - Missing credentials

    @Test("missing credentials short-circuits to .signedOut without calling statusSource")
    func missingCredentialsShortCircuits() async {
        let env = await makeMonitor(
            statusResults: [.success(idleSnapshot())],
            credentials: nil
        )
        await env.monitor.performTick()
        let fetchCount = await env.statusSource.fetchCount
        #expect(fetchCount == 0)
        let state = await env.monitor.currentState().visibleState
        #expect(state == .signedOut)
    }

    // MARK: - Observer notifications

    @Test("observers see transitions after baseline")
    func observersReceiveTransitions() async {
        let env = await makeMonitor(statusResults: [
            .success(idleSnapshot()),
            .success(pluggedSnapshot(session: nil)),
            .success(pluggedSnapshot(session: ActiveSessionInfo(sessionId: 1, state: "in_use")))
        ])
        await env.monitor.performTick()  // unknown -> healthyIdle
        await env.monitor.performTick()  // -> healthyPluggedIn
        await env.monitor.performTick()  // -> activelyCharging
        let observations = await env.observer.observations
        #expect(observations.count == 3)
        #expect(observations[0] == .init(from: .unknown, to: .healthyIdle))
        #expect(observations[1] == .init(from: .healthyIdle, to: .healthyPluggedIn))
        #expect(observations[2] == .init(from: .healthyPluggedIn, to: .activelyCharging))
    }
}
