import Foundation

/// Pure mapping from a `(StateTransition, MonitorState)` pair to the
/// user-facing notification copy. Returns `nil` when the transition should
/// be silent: baseline `.unknown → …` ticks, no-op same-state transitions.
enum TransitionMessage {
    /// Notification copy. Title is always "grounded" so macOS groups
    /// notifications in Notification Center.
    struct Message: Sendable, Equatable {
        let title: String
        let body: String
    }

    static func message(for transition: StateTransition, context: MonitorState) -> Message? {
        if shouldSuppress(transition) { return nil }

        if isRecovery(transition) {
            return Message(title: "grounded", body: "Charger reachable again")
        }

        if case let .error(reason) = transition.to {
            let count = context.consecutiveFailureCount
            return Message(title: "grounded", body: "\(reason) — \(count) failed checks")
        }

        if let body = happyPathBody(for: transition) {
            return Message(title: "grounded", body: body)
        }

        // Any other transition we haven't explicitly copy-written.
        // Surface a generic message rather than eating the signal.
        return Message(title: "grounded", body: "Charger state changed")
    }

    // MARK: - Helpers

    /// Baseline first-observation ticks are silent for healthy
    /// classifications. `.signedOut` and `.error` still fire on baseline —
    /// the user needs to know immediately. No-op same-state ticks are
    /// also silent.
    private static func shouldSuppress(_ transition: StateTransition) -> Bool {
        if transition.isNoOp { return true }
        if transition.from != .unknown { return false }
        switch transition.to {
        case .healthyIdle, .healthyPluggedIn, .activelyCharging:
            return true
        default:
            return false
        }
    }

    /// A tick is a recovery when the previous state was `.error` and the
    /// new state is anything *other* than `.error`.
    private static func isRecovery(_ transition: StateTransition) -> Bool {
        guard case .error = transition.from else { return false }
        if case .error = transition.to { return false }
        return true
    }

    /// Copy for the known plug/unplug/session transitions.
    private static func happyPathBody(for transition: StateTransition) -> String? {
        if case .signedOut = transition.to {
            return "Sign in to ChargePoint"
        }
        switch (transition.from, transition.to) {
        case (.healthyIdle, .healthyPluggedIn):
            return "Car plugged in"
        case (.healthyPluggedIn, .healthyIdle), (.activelyCharging, .healthyIdle):
            return "Car unplugged"
        case (.healthyPluggedIn, .activelyCharging):
            return "Charging started"
        case (.activelyCharging, .healthyPluggedIn):
            return "Fully charged"
        default:
            return nil
        }
    }
}
