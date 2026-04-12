import Foundation
import Testing

@Suite("ChargePointAPIClient")
struct ChargePointAPIClientTests {
    // MARK: - Fixture helpers

    private static let credentials = Credentials(
        email: "test@example.com",
        token: "abc",
        region: "NA-US",
        userId: 1,
        chargerId: 13836601,
        accountsEndpoint: "https://account.chargepoint.test/account/",
        hcpoHcmEndpoint: "https://hcpo.chargepoint.test/",
        mapcacheEndpoint: "https://mapcache.chargepoint.test/"
    )

    private static func fixture(_ name: String) throws -> Data {
        // xcodegen copies Tests/Fixtures/** into the test bundle's
        // Resources dir with the subfolder structure preserved, so the
        // file is at `chargepoint/<name>.json` inside the bundle.
        let bundle = Bundle(for: MockURLProtocol.self)
        if let url = bundle.url(
            forResource: name,
            withExtension: "json",
            subdirectory: "chargepoint"
        ) {
            return try Data(contentsOf: url)
        }
        // Fallback: look for the file flat in the bundle root, which is
        // what happens if the folder-reference flag isn't set.
        if let url = bundle.url(forResource: name, withExtension: "json") {
            return try Data(contentsOf: url)
        }
        throw FixtureError.notFound(name)
    }

    private enum FixtureError: Error {
        case notFound(String)
    }

    // MARK: - Test helpers

    private func makeClient(
        credentials: Credentials? = credentials,
        clock: any GroundedClock = SystemClockStub(),
        retryPolicy: RetryPolicy = RetryPolicy(delays: [0, 0])
    ) async -> ChargePointAPIClient {
        let credStore = InMemoryCredentialStore(preload: credentials)
        let session = makeMockSession()
        return ChargePointAPIClient(
            session: session,
            credentialStore: credStore,
            clock: clock,
            retryPolicy: retryPolicy
        )
    }

    private func makeMockSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self] + (config.protocolClasses ?? [])
        return URLSession(configuration: config)
    }

    // MARK: - Happy path

    @Test("merges charger status + active user session into a snapshot with activeSession")
    func mergedSnapshotWithActiveSession() async throws {
        let chargerStatus = try Self.fixture("status_available_plugged")
        let userStatus = try Self.fixture("user_status_active")
        MockURLProtocol.reset()
        MockURLProtocol.register(
            path: "/api/v1/configuration/users/1/chargers/13836601/status",
            response: .success(status: 200, body: chargerStatus)
        )
        MockURLProtocol.register(
            path: "/v2",
            response: .success(status: 200, body: userStatus)
        )

        let client = await makeClient()
        let snapshot = try await client.fetchStatus()
        #expect(snapshot.chargerId == 13836601)
        #expect(snapshot.isConnected)
        #expect(snapshot.isPluggedIn)
        #expect(snapshot.activeSession?.sessionId == 1)
        #expect(snapshot.activeSession?.state == "in_use")
    }

    @Test("merges charger status + empty user status into snapshot with no session")
    func mergedSnapshotWithoutSession() async throws {
        let chargerStatus = try Self.fixture("status_available_plugged")
        let userStatus = try Self.fixture("user_status_none")
        MockURLProtocol.reset()
        MockURLProtocol.register(
            path: "/api/v1/configuration/users/1/chargers/13836601/status",
            response: .success(status: 200, body: chargerStatus)
        )
        MockURLProtocol.register(
            path: "/v2",
            response: .success(status: 200, body: userStatus)
        )

        let client = await makeClient()
        let snapshot = try await client.fetchStatus()
        #expect(snapshot.isPluggedIn)
        #expect(snapshot.activeSession == nil)
    }

    // MARK: - Error mapping

    @Test("401 on charger status is surfaced as .authFailure without retry")
    func authFailureBypassesRetry() async throws {
        let chargerStatus = try Self.fixture("error_401")
        let userStatus = try Self.fixture("user_status_none")
        MockURLProtocol.reset()
        MockURLProtocol.register(
            path: "/api/v1/configuration/users/1/chargers/13836601/status",
            response: .success(status: 401, body: chargerStatus)
        )
        MockURLProtocol.register(
            path: "/v2",
            response: .success(status: 200, body: userStatus)
        )

        let client = await makeClient()
        do {
            _ = try await client.fetchStatus()
            Issue.record("expected auth failure")
        } catch let category as APIErrorCategory {
            #expect(category == .authFailure)
            // fetchOnce fires both calls in parallel so both are made once —
            // assert the charger status was hit exactly once (no retries).
            #expect(MockURLProtocol.hitCount(path: "/api/v1/configuration/users/1/chargers/13836601/status") == 1)
        }
    }

    @Test("Datadome 403 is surfaced as .botBlocked without retry")
    func datadomeBypassesRetry() async throws {
        let datadomeBody = try Self.fixture("error_datadome")
        let userStatus = try Self.fixture("user_status_none")
        MockURLProtocol.reset()
        MockURLProtocol.register(
            path: "/api/v1/configuration/users/1/chargers/13836601/status",
            response: .success(status: 403, body: datadomeBody)
        )
        MockURLProtocol.register(
            path: "/v2",
            response: .success(status: 200, body: userStatus)
        )

        let client = await makeClient()
        do {
            _ = try await client.fetchStatus()
            Issue.record("expected bot-blocked")
        } catch let category as APIErrorCategory {
            #expect(category == .botBlocked)
        }
    }

    // MARK: - In-tick retry

    @Test("two network failures then success: retry sleeps + succeeds on 3rd attempt")
    func retryRecovers() async throws {
        let chargerStatus = try Self.fixture("status_available_plugged")
        let userStatus = try Self.fixture("user_status_none")
        MockURLProtocol.reset()
        MockURLProtocol.registerSequence(
            path: "/api/v1/configuration/users/1/chargers/13836601/status",
            responses: [
                .failure(URLError(.timedOut)),
                .failure(URLError(.timedOut)),
                .success(status: 200, body: chargerStatus)
            ]
        )
        MockURLProtocol.register(
            path: "/v2",
            response: .success(status: 200, body: userStatus)
        )

        let clock = ManualClock(t0: Date(timeIntervalSince1970: 0))
        let client = await makeClient(
            clock: clock,
            retryPolicy: RetryPolicy(delays: [2, 6])
        )

        // Schedule the clock to advance past both retry sleeps. In a real
        // test we'd drive this concurrently but since ManualClock.sleep
        // returns immediately once the deadline is met, and each retry
        // loop iteration schedules a new sleeper, we need to advance
        // enough to wake each waiter as it's added.
        async let snapshotTask = client.fetchStatus()
        // Let the first two attempts run and register their sleep waits.
        try await Task.sleep(for: .milliseconds(50))
        await clock.advance(by: .seconds(2))
        try await Task.sleep(for: .milliseconds(50))
        await clock.advance(by: .seconds(6))

        let snapshot = try await snapshotTask
        #expect(snapshot.chargerId == 13836601)
        #expect(MockURLProtocol.hitCount(path: "/api/v1/configuration/users/1/chargers/13836601/status") == 3)
    }

    @Test("three network failures exhaust retry and throw .networkFailure")
    func retryExhausts() async throws {
        MockURLProtocol.reset()
        MockURLProtocol.registerSequence(
            path: "/api/v1/configuration/users/1/chargers/13836601/status",
            responses: [
                .failure(URLError(.timedOut)),
                .failure(URLError(.timedOut)),
                .failure(URLError(.timedOut))
            ]
        )
        let userStatus = try Self.fixture("user_status_none")
        MockURLProtocol.register(
            path: "/v2",
            response: .success(status: 200, body: userStatus)
        )

        let clock = ManualClock(t0: Date(timeIntervalSince1970: 0))
        let client = await makeClient(
            clock: clock,
            retryPolicy: RetryPolicy(delays: [2, 6])
        )

        async let snapshotTask: HomeChargerSnapshot = client.fetchStatus()
        try await Task.sleep(for: .milliseconds(50))
        await clock.advance(by: .seconds(2))
        try await Task.sleep(for: .milliseconds(50))
        await clock.advance(by: .seconds(6))

        do {
            _ = try await snapshotTask
            Issue.record("expected .networkFailure")
        } catch let category as APIErrorCategory {
            #expect(category == .networkFailure)
        }
    }

    // MARK: - Missing credentials

    @Test("missing credentials throws .authFailure without touching the network")
    func missingCredentialsShortCircuits() async throws {
        MockURLProtocol.reset()
        let client = await makeClient(credentials: nil)
        do {
            _ = try await client.fetchStatus()
            Issue.record("expected .authFailure")
        } catch let category as APIErrorCategory {
            #expect(category == .authFailure)
        }
    }
}

// MARK: - Helpers

/// Stub clock used when the retry loop doesn't need deterministic waits.
private struct SystemClockStub: GroundedClock, Sendable {
    func now() async -> Date { Date() }
    func sleep(for duration: Duration) async throws {}
}
