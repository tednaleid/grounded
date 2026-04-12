import Foundation

/// Production `ChargerStatusSource` that talks to the ChargePoint API.
/// Every `fetchStatus()` call issues two parallel requests
/// (charger status + user charging status), merges their responses
/// into a `HomeChargerSnapshot`, and applies the injected retry policy
/// to transient failures. Auth/bot-blocked errors bypass retry and
/// surface immediately so the Core state machine can fast-path to
/// `.signedOut`.
///
/// Credentials — including the endpoint URLs discovered at login
/// time — come from the injected `CredentialStore`.
struct ChargePointAPIClient: ChargerStatusSource {
    private let session: URLSession
    private let credentialStore: any CredentialStore
    private let clock: any GroundedClock
    private let retryPolicy: RetryPolicy

    init(
        session: URLSession = .shared,
        credentialStore: any CredentialStore,
        clock: any GroundedClock,
        retryPolicy: RetryPolicy = RetryPolicy(delays: [2, 6])
    ) {
        self.session = session
        self.credentialStore = credentialStore
        self.clock = clock
        self.retryPolicy = retryPolicy
    }

    func fetchStatus() async throws -> HomeChargerSnapshot {
        guard let credentials = try await credentialStore.load() else {
            throw APIErrorCategory.authFailure
        }

        var lastError: APIErrorCategory = .networkFailure
        for attemptIndex in 0..<retryPolicy.maxAttempts {
            do {
                return try await fetchOnce(credentials: credentials)
            } catch let category as APIErrorCategory {
                lastError = category
                if !retryPolicy.shouldRetry(category) {
                    throw category
                }
                // Not the last attempt? Sleep before retrying.
                if attemptIndex < retryPolicy.delays.count {
                    let delay = retryPolicy.delays[attemptIndex]
                    try? await clock.sleep(for: .seconds(delay))
                }
            }
        }
        throw lastError
    }

    // MARK: - Private

    private func fetchOnce(credentials: Credentials) async throws -> HomeChargerSnapshot {
        async let chargerStatus: APIModels.HomeChargerStatusResponse = request(
            url: chargerStatusURL(credentials),
            method: "GET",
            body: nil,
            credentials: credentials
        )
        async let userStatus: APIModels.UserChargingStatusResponse = request(
            url: userChargingStatusURL(credentials),
            method: "POST",
            body: Data(#"{"user_status": {"mfhs": {}}}"#.utf8),
            credentials: credentials
        )

        let status = try await chargerStatus
        let user = try await userStatus

        let session: ActiveSessionInfo? = user.userStatus.charging.map { charging in
            ActiveSessionInfo(sessionId: charging.sessionId, state: charging.state)
        }

        return HomeChargerSnapshot(
            chargerId: credentials.chargerId,
            isConnected: status.isConnected,
            isPluggedIn: status.isPluggedIn,
            chargingStatus: status.chargingStatus,
            activeSession: session
        )
    }

    private func chargerStatusURL(_ credentials: Credentials) -> URL {
        URL(
            string: "api/v1/configuration/users/\(credentials.userId)" +
                "/chargers/\(credentials.chargerId)/status",
            relativeTo: URL(string: credentials.hcpoHcmEndpoint)
        )!.absoluteURL
    }

    private func userChargingStatusURL(_ credentials: Credentials) -> URL {
        URL(
            string: "v2",
            relativeTo: URL(string: credentials.mapcacheEndpoint)
        )!.absoluteURL
    }

    private func request<T: Decodable>(
        url: URL,
        method: String,
        body: Data?,
        credentials: Credentials
    ) async throws -> T {
        var req = URLRequest(url: url)
        req.httpMethod = method
        if let body {
            req.httpBody = body
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        req.setValue("CP_SESSION_TOKEN", forHTTPHeaderField: "cp-session-type")
        req.setValue(credentials.token, forHTTPHeaderField: "cp-session-token")
        req.setValue(credentials.region, forHTTPHeaderField: "cp-region")
        req.setValue("grounded/0.1", forHTTPHeaderField: "user-agent")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: req)
        } catch {
            throw APIErrorCategory.networkFailure
        }

        if let category = APIErrorMapping.classify(response: response, data: data, error: nil) {
            throw category
        }

        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw APIErrorCategory.decodeFailure
        }
    }
}
