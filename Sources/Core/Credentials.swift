import Foundation

/// Everything we cache after a successful ChargePoint login so that
/// subsequent monitoring ticks can hit the authenticated endpoints
/// without re-running discovery or profile lookup.
///
/// The `token` is the `coulomb_sess` session cookie value. `region`
/// comes from the discovery response and is needed for the
/// `cp-region` header. `userId` and `chargerId` are also cached so we
/// don't re-fetch them on every tick.
struct Credentials: Sendable, Equatable, Codable {
    let email: String
    let token: String
    let region: String
    let userId: Int
    let chargerId: Int
    /// `accountsEndpoint` from the discovery response — the profile
    /// endpoint lives under this host.
    let accountsEndpoint: String
    /// `hcpoHcmEndpoint` from the discovery response — home charger
    /// status lives under this host.
    let hcpoHcmEndpoint: String
    /// `mapcacheEndpoint` from the discovery response — user charging
    /// status lives under this host.
    let mapcacheEndpoint: String
}
