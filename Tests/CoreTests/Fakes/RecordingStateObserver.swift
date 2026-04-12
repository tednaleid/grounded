import Foundation

/// Fake `StateObserver` that records every observed transition. Tests assert
/// the sequence is what they expect.
actor RecordingStateObserver: StateObserver {
    struct Observation: Sendable, Equatable {
        let from: ChargerState
        let to: ChargerState
    }

    private(set) var observations: [Observation] = []

    func stateDidChange(from previous: ChargerState, to current: ChargerState) async {
        observations.append(Observation(from: previous, to: current))
    }
}
