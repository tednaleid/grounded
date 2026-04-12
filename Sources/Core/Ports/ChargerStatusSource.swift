import Foundation

/// Port for fetching the current charger snapshot. The adapter handles the
/// details (two parallel HTTP calls, merging, in-tick retry, error
/// classification). Throws are typed as `APIErrorCategory` so the Core
/// stays decoupled from HTTP/URLSession concepts.
protocol ChargerStatusSource: Sendable {
    func fetchStatus() async throws -> HomeChargerSnapshot
}
