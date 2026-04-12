import Foundation

/// Private Codable structs that match the raw ChargePoint API wire shapes.
/// These types are an implementation detail of `ChargePointAPIClient` —
/// they never leave the adapter. Core types like `HomeChargerSnapshot` and
/// `ActiveSessionInfo` are the projection the adapter exposes upward.
enum APIModels {
    // MARK: - Discovery
    // POST https://discovery.chargepoint.com/discovery/v3/globalconfig
    // body `{"username": email}`

    struct DiscoveryResponse: Decodable, Sendable {
        let region: String
        let endPoints: Endpoints
    }

    struct Endpoints: Decodable, Sendable {
        let accountsEndpoint: String
        let hcpoHcmEndpoint: String
        let mapcacheEndpoint: String
    }

    // MARK: - Profile
    // GET {accountsEndpoint}/v1/driver/profile/user

    struct AccountResponse: Decodable, Sendable {
        let user: AccountUser
    }

    struct AccountUser: Decodable, Sendable {
        let userId: Int
    }

    // MARK: - Home chargers list
    // GET {hcpoHcmEndpoint}/api/v1/configuration/users/{userId}/chargers

    struct HomeChargersResponse: Decodable, Sendable {
        let data: [HomeChargerEntry]
    }

    struct HomeChargerEntry: Decodable, Sendable {
        let id: String
    }

    // MARK: - Home charger status
    // GET {hcpoHcmEndpoint}/api/v1/configuration/users/{userId}/chargers/{chargerId}/status

    struct HomeChargerStatusResponse: Decodable, Sendable {
        let chargingStatus: String
        let isPluggedIn: Bool
        let isConnected: Bool
    }

    // MARK: - User charging status
    // POST {mapcacheEndpoint}/v2  body `{"user_status": {"mfhs": {}}}`
    //
    // When there is no active session the response is
    // `{"user_status": {}}` (empty inner object) — in which case the
    // `charging` decode is nil and we surface `activeSession: nil`.

    struct UserChargingStatusResponse: Decodable, Sendable {
        let userStatus: UserStatus
    }

    struct UserStatus: Decodable, Sendable {
        let charging: ChargingSession?
    }

    struct ChargingSession: Decodable, Sendable {
        let sessionId: Int
        let state: String
    }
}

// Swift's synthesized Codable uses the property name verbatim for JSON keys.
// `UserChargingStatusResponse.userStatus` needs to decode from `user_status`,
// so we hand-write CodingKeys on an extension at file scope (staying under
// the 1-level nesting limit).
extension APIModels.UserChargingStatusResponse {
    private enum CodingKeys: String, CodingKey {
        case userStatus = "user_status"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.userStatus = try container.decode(APIModels.UserStatus.self, forKey: .userStatus)
    }
}
