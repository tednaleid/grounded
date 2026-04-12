import Foundation
import Testing

@Suite("KeychainCredentialStore", .serialized)
struct KeychainCredentialStoreTests {
    /// Use a dedicated test service name so we never touch the production
    /// entry. Each test clears the slot on setup and teardown.
    private static let testService = "com.tednaleid.grounded.tests"

    private func makeStore() -> KeychainCredentialStore {
        KeychainCredentialStore(service: Self.testService, account: "test-chargepoint")
    }

    private func fixture() -> Credentials {
        Credentials(
            email: "test@example.com",
            token: "coulomb_sess_abc",
            region: "NA-US",
            userId: 1,
            chargerId: 13836601,
            accountsEndpoint: "https://account.chargepoint.test/account/",
            hcpoHcmEndpoint: "https://hcpo.chargepoint.test/",
            mapcacheEndpoint: "https://mapcache.chargepoint.test/"
        )
    }

    @Test("round-trip: save, load, clear")
    func roundTrip() async throws {
        let store = makeStore()
        try await store.clear()
        let empty = try await store.load()
        #expect(empty == nil)

        let toSave = fixture()
        try await store.save(toSave)

        let loaded = try await store.load()
        #expect(loaded == toSave)

        let hasAfterSave = await store.hasCredentials
        #expect(hasAfterSave == true)

        try await store.clear()
        let afterClear = try await store.load()
        #expect(afterClear == nil)

        let hasAfterClear = await store.hasCredentials
        #expect(hasAfterClear == false)
    }

    @Test("save overwrites an existing entry")
    func overwrite() async throws {
        let store = makeStore()
        try await store.clear()

        try await store.save(fixture())
        let updated = Credentials(
            email: "other@example.com",
            token: "coulomb_sess_xyz",
            region: "EU-DE",
            userId: 42,
            chargerId: 99_999,
            accountsEndpoint: "https://eu.account.chargepoint.test/account/",
            hcpoHcmEndpoint: "https://eu.hcpo.chargepoint.test/",
            mapcacheEndpoint: "https://eu.mapcache.chargepoint.test/"
        )
        try await store.save(updated)

        let loaded = try await store.load()
        #expect(loaded == updated)

        try await store.clear()
    }

    @Test("clear is a no-op when the slot is empty")
    func clearEmpty() async throws {
        let store = makeStore()
        try await store.clear()
        // Calling clear a second time should not throw.
        try await store.clear()
    }
}
