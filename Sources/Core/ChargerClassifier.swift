import Foundation

/// Pure mapping from a `HomeChargerSnapshot` to a `ChargerState`.
/// Offline trumps everything. Otherwise we look at `isPluggedIn` and the
/// active session's state string (if any).
enum ChargerClassifier {
    static func classify(_ snapshot: HomeChargerSnapshot) -> ChargerState {
        // Payload-reported offline trumps any other signal and transitions
        // immediately (no threshold). This is a "trusted" error: the API
        // says the charger itself is offline, it's not transport noise.
        guard snapshot.isConnected else {
            return .error("Charger offline")
        }

        guard snapshot.isPluggedIn else {
            return .healthyIdle
        }

        if snapshot.chargingStatus == "CHARGING" {
            return .activelyCharging
        }

        if let session = snapshot.activeSession {
            switch session.state {
            case "in_use":
                return .activelyCharging
            case "fully_charged":
                return .healthyPluggedIn
            default:
                return .error("Unknown session state: \(session.state)")
            }
        }

        return .healthyPluggedIn
    }
}
