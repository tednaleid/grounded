import Foundation

/// Port for any component that wants to be notified when the visible
/// charger state changes. Phase 1 ships the protocol; the wire-up and
/// real observers land in Phase 2.
protocol StateObserver: Sendable {
    func stateDidChange(from previous: ChargerState, to current: ChargerState) async
}
