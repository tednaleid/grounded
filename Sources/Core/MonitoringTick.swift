import Foundation

/// The outcome of applying one polling result to the current `MonitorState`.
/// All fields are pure values; the monitor actor uses them to update its
/// state and drive observers.
struct TickOutcome: Sendable, Equatable {
    let newState: MonitorState
    /// The transition emitted by this tick. `nil` when no visible change
    /// happened (e.g. a transient failure below the threshold).
    let transition: StateTransition?
    /// The notification to deliver, if any. Baseline ticks and same-state
    /// ticks are silent.
    let notification: TransitionMessage.Message?
}

/// Pure state machine for the monitoring loop. Given the previous state and
/// a polling result, produces a `TickOutcome`:
/// 1. Auth/bot-blocked errors fast-path to `.signedOut` (bypasses threshold).
/// 2. Transient errors increment the failure count. The visible state only
///    crosses into `.error` once `failureThreshold` is reached.
/// 3. Successful polls classify the snapshot and reset the count.
/// 4. Baseline ticks (`previous == .unknown`) are always silent.
enum MonitoringTick {
    static func tick(
        previous: MonitorState,
        result: Result<HomeChargerSnapshot, APIErrorCategory>,
        at date: Date,
        config: MonitoringConfig
    ) -> TickOutcome {
        switch result {
        case .success(let snapshot):
            return handleSuccess(previous: previous, snapshot: snapshot, at: date)
        case .failure(let category):
            return handleFailure(
                previous: previous,
                category: category,
                at: date,
                config: config
            )
        }
    }

    // MARK: - Success path

    private static func handleSuccess(
        previous: MonitorState,
        snapshot: HomeChargerSnapshot,
        at date: Date
    ) -> TickOutcome {
        let classified = ChargerClassifier.classify(snapshot)
        let newState = previous.withSuccess(
            snapshot: snapshot,
            visibleState: classified,
            at: date
        )
        let transition = StateTransition(from: previous.visibleState, to: classified)
        let message = TransitionMessage.message(for: transition, context: newState)
        return TickOutcome(
            newState: newState,
            transition: transition,
            notification: message
        )
    }

    // MARK: - Failure path

    private static func handleFailure(
        previous: MonitorState,
        category: APIErrorCategory,
        at date: Date,
        config: MonitoringConfig
    ) -> TickOutcome {
        // Non-transient errors (401, Datadome) fast-path to signedOut.
        if !category.isTransient {
            let newState = previous
                .withFailure(category, at: date)
                .withVisibleState(.signedOut)
            let transition = StateTransition(from: previous.visibleState, to: .signedOut)
            let message = TransitionMessage.message(for: transition, context: newState)
            return TickOutcome(
                newState: newState,
                transition: transition,
                notification: message
            )
        }

        // Transient error: bump count, decide whether to visibly flip to error.
        let bumped = previous.withFailure(category, at: date)

        // Already in error — just bump the count, don't re-notify.
        if case .error = previous.visibleState {
            return TickOutcome(
                newState: bumped,
                transition: nil,
                notification: nil
            )
        }

        // Not yet crossed threshold — stay visibly where we were.
        if bumped.consecutiveFailureCount < config.failureThreshold {
            return TickOutcome(
                newState: bumped,
                transition: nil,
                notification: nil
            )
        }

        // Threshold crossed: flip to error and emit notification.
        let errorState = ChargerState.error("Charger unreachable")
        let withVisible = bumped.withVisibleState(errorState)
        let transition = StateTransition(from: previous.visibleState, to: errorState)
        let message = TransitionMessage.message(for: transition, context: withVisible)
        return TickOutcome(
            newState: withVisible,
            transition: transition,
            notification: message
        )
    }
}
