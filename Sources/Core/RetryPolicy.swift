import Foundation

/// Decides whether an `APIErrorCategory` should be retried in-tick, and how
/// long to wait between each attempt. Non-transient errors (auth failure,
/// Datadome captcha) never retry — they fast-path to `.signedOut`.
struct RetryPolicy: Sendable, Equatable {
    /// Delays in seconds between attempts. `[2, 6]` means: first attempt, then
    /// wait 2s, second attempt, wait 6s, third attempt. Three attempts total.
    let delays: [TimeInterval]

    /// Total number of attempts = initial attempt + retries = `delays.count + 1`.
    var maxAttempts: Int { delays.count + 1 }

    func shouldRetry(_ error: APIErrorCategory) -> Bool {
        error.isTransient
    }
}
