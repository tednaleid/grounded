import Foundation

/// The visible state of the home charger as exposed to the user.
/// `.error` carries a short human-readable reason string that the menubar menu
/// and error-entry notifications surface.
enum ChargerState: Sendable, Equatable {
    case unknown
    case signedOut
    case healthyIdle
    case healthyPluggedIn
    case activelyCharging
    case error(String)
}
