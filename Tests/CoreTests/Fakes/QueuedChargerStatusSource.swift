import Foundation

/// Fake `ChargerStatusSource` that returns a queue of predetermined
/// results. Each `fetchStatus()` call dequeues one. Empty queue throws
/// `.serverError` so tests don't accidentally hang.
actor QueuedChargerStatusSource: ChargerStatusSource {
    private var results: [Result<HomeChargerSnapshot, APIErrorCategory>]
    private(set) var fetchCount = 0

    init(results: [Result<HomeChargerSnapshot, APIErrorCategory>] = []) {
        self.results = results
    }

    func enqueue(_ result: Result<HomeChargerSnapshot, APIErrorCategory>) {
        results.append(result)
    }

    func fetchStatus() async throws -> HomeChargerSnapshot {
        fetchCount += 1
        guard !results.isEmpty else {
            throw APIErrorCategory.serverError(message: "queue exhausted")
        }
        let next = results.removeFirst()
        switch next {
        case .success(let snapshot):
            return snapshot
        case .failure(let category):
            throw category
        }
    }
}
