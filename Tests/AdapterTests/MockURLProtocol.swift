import Foundation

/// A `URLProtocol` subclass that answers every request from a static
/// routing table keyed by request-path prefix. Each test calls
/// `MockURLProtocol.reset()` then `register(path:response:)` (or
/// `registerSequence(...)`) before building a session that uses this
/// protocol via `URLSessionConfiguration.protocolClasses`.
///
/// The static state is intentional — `URLProtocol` is instantiated by
/// the system per request with only a `URLRequest`, so tests need a
/// shared place to look up canned responses. Each test resets and
/// repopulates it; tests run serially inside a suite.
final class MockURLProtocol: URLProtocol, @unchecked Sendable {
    enum Response {
        case success(status: Int, body: Data)
        case failure(Error)
    }

    // Routing table and hit counts protected by a lock. `nonisolated(unsafe)`
    // is appropriate here because we're manually synchronizing via NSLock;
    // Swift 6's strict concurrency just needs the explicit opt-out.
    private static let lock = NSLock()
    nonisolated(unsafe) private static var routes: [String: [Response]] = [:]
    nonisolated(unsafe) private static var hits: [String: Int] = [:]

    static func reset() {
        lock.lock()
        defer { lock.unlock() }
        routes.removeAll()
        hits.removeAll()
    }

    /// Register a single canned response for every request whose path
    /// matches `path`.
    static func register(path: String, response: Response) {
        lock.lock()
        defer { lock.unlock() }
        routes[path] = [response]
    }

    /// Register a sequence of responses for a path. First request returns
    /// responses[0], second returns responses[1], and so on. Re-uses the
    /// last response once the sequence is exhausted.
    static func registerSequence(path: String, responses: [Response]) {
        lock.lock()
        defer { lock.unlock() }
        routes[path] = responses
    }

    static func hitCount(path: String) -> Int {
        lock.lock()
        defer { lock.unlock() }
        return hits[path] ?? 0
    }

    // MARK: - URLProtocol API

    // NSURLProtocol's overrides are class functions, not static, in
    // Objective-C. SwiftLint still prefers `static` on final classes —
    // silence the rule for these two required overrides.
    // swiftlint:disable:next static_over_final_class
    override class func canInit(with request: URLRequest) -> Bool { true }

    // swiftlint:disable:next static_over_final_class
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let client else { return }
        let path = request.url?.path ?? ""
        let response = Self.takeResponse(for: path)

        guard let response else {
            client.urlProtocol(self, didFailWithError: URLError(.cannotLoadFromNetwork))
            return
        }

        switch response {
        case .success(let status, let body):
            if let url = request.url,
               let httpResponse = HTTPURLResponse(
                   url: url,
                   statusCode: status,
                   httpVersion: "HTTP/1.1",
                   headerFields: nil
               ) {
                client.urlProtocol(self, didReceive: httpResponse, cacheStoragePolicy: .notAllowed)
                client.urlProtocol(self, didLoad: body)
                client.urlProtocolDidFinishLoading(self)
            } else {
                client.urlProtocol(self, didFailWithError: URLError(.badURL))
            }
        case .failure(let error):
            client.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}

    // MARK: - Private

    private static func takeResponse(for path: String) -> Response? {
        lock.lock()
        defer { lock.unlock() }
        hits[path, default: 0] += 1
        guard var responses = routes[path], !responses.isEmpty else {
            return nil
        }
        if responses.count == 1 {
            // Single registration — always return the same one.
            return responses[0]
        }
        let next = responses.removeFirst()
        routes[path] = responses
        return next
    }
}
