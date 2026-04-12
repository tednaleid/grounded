import Foundation
import Testing

@Suite("TransitionMessage")
struct TransitionMessageTests {
    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)

    private func state(
        visibleState: ChargerState = .unknown,
        failureCount: Int = 0,
        lastAttemptAt: Date? = nil
    ) -> MonitorState {
        MonitorState(
            visibleState: visibleState,
            lastSuccessfulSnapshot: nil,
            lastSuccessAt: nil,
            lastAttemptAt: lastAttemptAt,
            consecutiveFailureCount: failureCount
        )
    }

    // Silent baseline

    @Test(".unknown -> healthyIdle is silent (first observation)")
    func baselineIdleIsSilent() {
        let msg = TransitionMessage.message(
            for: .init(from: .unknown, to: .healthyIdle),
            context: state()
        )
        #expect(msg == nil)
    }

    @Test(".unknown -> healthy states is silent (baseline)")
    func baselineHealthyIsSilent() {
        for target in [ChargerState.healthyIdle, .healthyPluggedIn, .activelyCharging] {
            let msg = TransitionMessage.message(
                for: .init(from: .unknown, to: target),
                context: state()
            )
            #expect(msg == nil, "expected silent baseline for → \(target)")
        }
    }

    @Test(".unknown -> signedOut notifies (auth failure fast-path even on baseline)")
    func baselineSignedOutNotifies() {
        let msg = TransitionMessage.message(
            for: .init(from: .unknown, to: .signedOut),
            context: state()
        )
        #expect(msg?.body == "Sign in to ChargePoint")
    }

    @Test(".unknown -> error notifies (trusted offline on baseline)")
    func baselineErrorNotifies() {
        let msg = TransitionMessage.message(
            for: .init(from: .unknown, to: .error("Charger offline")),
            context: state(failureCount: 0)
        )
        #expect(msg != nil)
        #expect(msg?.body.contains("Charger offline") == true)
    }

    // Normal transition copy

    @Test("healthyIdle → healthyPluggedIn: 'Car plugged in'")
    func plugIn() {
        let msg = TransitionMessage.message(
            for: .init(from: .healthyIdle, to: .healthyPluggedIn),
            context: state(visibleState: .healthyIdle)
        )
        #expect(msg?.title == "grounded")
        #expect(msg?.body == "Car plugged in")
    }

    @Test("healthyPluggedIn → activelyCharging: 'Charging started'")
    func startCharging() {
        let msg = TransitionMessage.message(
            for: .init(from: .healthyPluggedIn, to: .activelyCharging),
            context: state(visibleState: .healthyPluggedIn)
        )
        #expect(msg?.body == "Charging started")
    }

    @Test("activelyCharging → healthyPluggedIn: 'Fully charged'")
    func fullyCharged() {
        let msg = TransitionMessage.message(
            for: .init(from: .activelyCharging, to: .healthyPluggedIn),
            context: state(visibleState: .activelyCharging)
        )
        #expect(msg?.body == "Fully charged")
    }

    @Test("healthyPluggedIn → healthyIdle: 'Car unplugged'")
    func unplug() {
        let msg = TransitionMessage.message(
            for: .init(from: .healthyPluggedIn, to: .healthyIdle),
            context: state(visibleState: .healthyPluggedIn)
        )
        #expect(msg?.body == "Car unplugged")
    }

    @Test("any → signedOut: 'Sign in to ChargePoint'")
    func signedOut() {
        let msg = TransitionMessage.message(
            for: .init(from: .healthyIdle, to: .signedOut),
            context: state(visibleState: .healthyIdle)
        )
        #expect(msg?.body == "Sign in to ChargePoint")
    }

    // Error transition with failure count

    @Test("healthyIdle → error includes the failure count")
    func errorBodyMentionsFailureCount() {
        let msg = TransitionMessage.message(
            for: .init(from: .healthyIdle, to: .error("Charger unreachable")),
            context: state(visibleState: .healthyIdle, failureCount: 3)
        )
        #expect(msg?.body.contains("3 failed checks") == true)
        #expect(msg?.body.contains("Charger unreachable") == true)
    }

    // Recovery

    @Test("error → healthyIdle fires recovery message")
    func recoveryFromError() {
        let msg = TransitionMessage.message(
            for: .init(from: .error("Charger unreachable"), to: .healthyIdle),
            context: state(visibleState: .error("Charger unreachable"), failureCount: 4)
        )
        #expect(msg?.body == "Charger reachable again")
    }

    @Test("error → activelyCharging also counts as recovery")
    func recoveryToCharging() {
        let msg = TransitionMessage.message(
            for: .init(from: .error("x"), to: .activelyCharging),
            context: state(visibleState: .error("x"), failureCount: 5)
        )
        #expect(msg?.body == "Charger reachable again")
    }

    // Equal from == to should never produce a message

    @Test("same-state 'transition' returns nil")
    func sameStateIsSilent() {
        let msg = TransitionMessage.message(
            for: .init(from: .healthyIdle, to: .healthyIdle),
            context: state(visibleState: .healthyIdle)
        )
        #expect(msg == nil)
    }
}
