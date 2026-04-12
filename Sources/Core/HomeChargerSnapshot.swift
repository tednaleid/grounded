import Foundation

/// A single polled snapshot of the home charger, merged from two upstream
/// ChargePoint endpoints (`charger_status` + `user_charging_status`).
/// All fields the classifier cares about live here. Extra raw fields the
/// adapter received but doesn't need should be dropped at the adapter layer.
struct HomeChargerSnapshot: Sendable, Equatable {
    let chargerId: Int
    let isConnected: Bool
    let isPluggedIn: Bool
    let chargingStatus: String
    let activeSession: ActiveSessionInfo?
}

/// The payload projected out of the `user_charging_status` response when a
/// session is in progress. Nil on the snapshot means "no session."
struct ActiveSessionInfo: Sendable, Equatable {
    let sessionId: Int
    /// Raw session state string from the API. Known values: `"in_use"`,
    /// `"fully_charged"`. The classifier inspects this literally.
    let state: String
}
