import Foundation

/// Completes a ChargePoint login after `WKLoginBrowser` harvests the
/// session cookie. Uses hardcoded NA-US endpoints (the only region
/// Phase 2 ships with) to run the profile + chargers-list setup calls
/// and produce a full `Credentials` blob.
///
/// Phase 2+ can replace this with dynamic discovery
/// (`POST /discovery/v3/globalconfig`) if non-NA-US users ever appear.
struct LoginFlow: Sendable {
    static let naUSRegion = "NA-US"
    static let naUSAccountsEndpoint = "https://account.chargepoint.com/account/"
    static let naUSHcpoHcmEndpoint =
        "https://internal-api-us.chargepoint.com/hcpo-charger-management/"
    static let naUSMapcacheEndpoint = "https://mc.chargepoint.com/map-prod/"

    let browser: any BrowserAuth
    let session: URLSession

    init(browser: any BrowserAuth, session: URLSession = .shared) {
        self.browser = browser
        self.session = session
    }

    /// Present the sign-in UI, harvest the token, and run profile +
    /// chargers-list setup calls. Throws `LoginFlowError` on any step.
    @MainActor
    func signIn() async throws -> Credentials {
        let partial = try await browser.presentLogin()

        let userId = try await fetchUserId(token: partial.token)
        let chargerId = try await fetchFirstChargerId(token: partial.token, userId: userId)

        return Credentials(
            email: partial.email,
            token: partial.token,
            region: Self.naUSRegion,
            userId: userId,
            chargerId: chargerId,
            accountsEndpoint: Self.naUSAccountsEndpoint,
            hcpoHcmEndpoint: Self.naUSHcpoHcmEndpoint,
            mapcacheEndpoint: Self.naUSMapcacheEndpoint
        )
    }

    // MARK: - Private

    private func fetchUserId(token: String) async throws -> Int {
        let url = URL(
            string: "v1/driver/profile/user",
            relativeTo: URL(string: Self.naUSAccountsEndpoint)
        )!
        let data = try await get(url: url, token: token)
        do {
            return try JSONDecoder().decode(APIModels.AccountResponse.self, from: data).user.userId
        } catch {
            throw LoginFlowError.decodeFailed("profile/user")
        }
    }

    private func fetchFirstChargerId(token: String, userId: Int) async throws -> Int {
        let url = URL(
            string: "api/v1/configuration/users/\(userId)/chargers",
            relativeTo: URL(string: Self.naUSHcpoHcmEndpoint)
        )!
        let data = try await get(url: url, token: token)
        let response: APIModels.HomeChargersResponse
        do {
            response = try JSONDecoder().decode(APIModels.HomeChargersResponse.self, from: data)
        } catch {
            throw LoginFlowError.decodeFailed("chargers list")
        }
        guard let first = response.data.first, let chargerId = Int(first.id) else {
            throw LoginFlowError.noChargersFound
        }
        return chargerId
    }

    private func get(url: URL, token: String) async throws -> Data {
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue("CP_SESSION_TOKEN", forHTTPHeaderField: "cp-session-type")
        req.setValue(token, forHTTPHeaderField: "cp-session-token")
        req.setValue(Self.naUSRegion, forHTTPHeaderField: "cp-region")
        req.setValue("grounded/0.1", forHTTPHeaderField: "user-agent")
        do {
            let (data, response) = try await session.data(for: req)
            if let category = APIErrorMapping.classify(response: response, data: data, error: nil) {
                throw LoginFlowError.apiError(category)
            }
            return data
        } catch let error as LoginFlowError {
            throw error
        } catch {
            throw LoginFlowError.network
        }
    }
}

enum LoginFlowError: Error, Equatable {
    case network
    case decodeFailed(String)
    case apiError(APIErrorCategory)
    case noChargersFound
}
