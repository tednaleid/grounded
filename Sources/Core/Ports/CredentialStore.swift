import Foundation

/// Port for the ChargePoint session credentials. The Keychain adapter is
/// the production implementation; tests use `InMemoryCredentialStore`.
protocol CredentialStore: Sendable {
    /// Fast-path probe used before every tick so we can short-circuit to
    /// `.signedOut` without hitting the network when creds are missing.
    var hasCredentials: Bool { get async }

    func load() async throws -> Credentials?
    func save(_ credentials: Credentials) async throws
    func clear() async throws
}
