import Foundation

/// The visible state of the home charger as exposed to the user.
/// Phase 1 only wires up `.unknown` and `.signedOut`. Phase 2 fills in the
/// remaining cases alongside the classifier.
enum ChargerState: String, Sendable, CaseIterable, Equatable {
    case unknown
    case signedOut
    case healthyIdle
    case healthyPluggedIn
    case activelyCharging
    case error
}
