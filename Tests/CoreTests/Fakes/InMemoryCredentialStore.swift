import Foundation

/// Actor-backed fake CredentialStore for tests. Starts empty; tests inject
/// credentials via `preload(_:)`. `saved` / `cleared` flags let assertions
/// verify adapter writes without reaching into internal state.
actor InMemoryCredentialStore: CredentialStore {
    private var credentials: Credentials?
    private(set) var saveCallCount = 0
    private(set) var clearCallCount = 0

    init(preload: Credentials? = nil) {
        self.credentials = preload
    }

    var hasCredentials: Bool {
        credentials != nil
    }

    func load() async throws -> Credentials? {
        credentials
    }

    func save(_ credentials: Credentials) async throws {
        self.credentials = credentials
        saveCallCount += 1
    }

    func clear() async throws {
        credentials = nil
        clearCallCount += 1
    }
}
