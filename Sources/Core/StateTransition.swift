import Foundation

/// A pairing of the old and new `ChargerState`. The state machine emits one
/// of these every time a tick is processed, even if `from == to` (suppression
/// happens at the `TransitionMessage` layer, not here).
struct StateTransition: Sendable, Equatable {
    let from: ChargerState
    let to: ChargerState

    /// True if the two states are identical — the tick was a no-op visually.
    var isNoOp: Bool { from == to }
}
