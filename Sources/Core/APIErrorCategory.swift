import Foundation

/// Abstract categorization of failures surfaced by the `ChargerStatusSource`
/// port. Adapters map their framework-native errors (URLSession errors, HTTP
/// status codes, decode errors) into one of these cases. The Core reasons
/// about failures only via this abstraction.
enum APIErrorCategory: Sendable, Equatable, Error {
    /// HTTP 401 / invalid session. Non-transient. Fast-path to `.signedOut`.
    case authFailure
    /// HTTP 403 with a Datadome captcha body. Non-transient. Fast-path to
    /// `.signedOut` — the user needs to re-login.
    case botBlocked
    /// URLSession-level error (timeout, unreachable host, DNS). Transient.
    case networkFailure
    /// JSON decode / shape mismatch. Transient (probably a flaky server).
    case decodeFailure
    /// Any other non-200 response. Transient.
    case serverError(message: String)

    /// Whether this failure should be retried in-tick and counted toward the
    /// failure threshold. Non-transient errors bypass the threshold and
    /// transition immediately.
    var isTransient: Bool {
        switch self {
        case .authFailure, .botBlocked:
            return false
        case .networkFailure, .decodeFailure, .serverError:
            return true
        }
    }
}
