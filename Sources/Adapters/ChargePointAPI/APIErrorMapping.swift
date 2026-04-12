import Foundation

/// Maps URLSession outcomes to `APIErrorCategory`. Centralized here so the
/// `ChargePointAPIClient` can pipeline every failure through one function
/// and get consistent categorization.
enum APIErrorMapping {
    /// Classify a URLSession result.
    /// - Parameters:
    ///   - response: The URLResponse returned by URLSession, if any.
    ///   - data: The response body, if any. Used for Datadome detection.
    ///   - error: The URLSession transport error, if any. Takes precedence
    ///            over `response` when both are present.
    static func classify(
        response: URLResponse?,
        data: Data?,
        error: Error?
    ) -> APIErrorCategory? {
        // Transport error trumps everything.
        if error != nil {
            return .networkFailure
        }

        guard let http = response as? HTTPURLResponse else {
            return .networkFailure
        }

        switch http.statusCode {
        case 200...299:
            return nil  // success — caller proceeds to decode
        case 401:
            return .authFailure
        case 403:
            // Datadome captcha bodies are small JSON objects with a
            // top-level `url` field pointing at a captcha challenge URL.
            if let data, isDatadomeBody(data) {
                return .botBlocked
            }
            return .serverError(message: "HTTP 403")
        default:
            return .serverError(message: "HTTP \(http.statusCode)")
        }
    }

    /// A Datadome-blocked response is a 403 with a JSON body containing
    /// a `url` field. Example:
    ///     `{"url": "https://geo.captcha-delivery.com/captcha/?..."}`
    private static func isDatadomeBody(_ data: Data) -> Bool {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return false
        }
        return object["url"] is String
    }
}
