#if DEBUG
import Foundation
import Network

/// Debug HTTP server on `localhost:9877`. Answers the Phase 2 inspect
/// surface. See `contract.md` §Inspect Surface for the route table.
///
/// Wires directly to the real `ChargerMonitor` and `CredentialStore`
/// since it's DEBUG-only and already lives in the same process. No
/// authorization — relies on binding to localhost only.
final class InspectServer: @unchecked Sendable {
    static let port: NWEndpoint.Port = 9877

    private let queue = DispatchQueue(label: "com.tednaleid.grounded.inspect-server")
    private var listener: NWListener?
    private let dependencies: Dependencies

    struct Dependencies: Sendable {
        let monitor: ChargerMonitor
        let credentialStore: any CredentialStore
        let notificationSink: any NotificationSink
    }

    init(dependencies: Dependencies) {
        self.dependencies = dependencies
    }

    func start() {
        guard listener == nil else { return }
        do {
            let params = NWParameters.tcp
            params.allowLocalEndpointReuse = true
            let listener = try NWListener(using: params, on: Self.port)
            listener.newConnectionHandler = { [weak self] connection in
                self?.accept(connection)
            }
            listener.start(queue: queue)
            self.listener = listener
            NSLog("grounded inspect server listening on localhost:\(Self.port)")
        } catch {
            NSLog("grounded inspect server failed to start on port \(Self.port): \(error)")
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    // MARK: - Connection handling

    private func accept(_ connection: NWConnection) {
        connection.start(queue: queue)
        connection.receive(
            minimumIncompleteLength: 1,
            maximumLength: 64 * 1024
        ) { [weak self] data, _, _, _ in
            guard let self, let data else {
                connection.cancel()
                return
            }
            Task { [dependencies = self.dependencies] in
                let response = await Self.route(data: data, dependencies: dependencies)
                connection.send(
                    content: response,
                    completion: .contentProcessed { _ in connection.cancel() }
                )
            }
        }
    }

    // MARK: - Routing

    private static func route(data: Data, dependencies: Dependencies) async -> Data {
        guard let request = parseRequest(data) else {
            return httpResponse(status: "400 Bad Request", body: #"{"error":"bad request"}"#)
        }
        do {
            return try await dispatch(request: request, dependencies: dependencies)
        } catch {
            return httpResponse(
                status: "500 Internal Server Error",
                body: #"{"error":"\#(error.localizedDescription)"}"#
            )
        }
    }

    private static func dispatch(
        request: Request,
        dependencies: Dependencies
    ) async throws -> Data {
        switch (request.method, request.path) {
        case ("GET", "/state"):
            return await handleState(dependencies: dependencies)
        case ("POST", "/force-poll"):
            await dependencies.monitor.performTick()
            return await handleState(dependencies: dependencies)
        case ("POST", "/simulate-failure"):
            return try await handleSimulateFailure(request: request, dependencies: dependencies)
        case ("POST", "/clear-credentials"):
            try await dependencies.credentialStore.clear()
            return httpResponse(status: "200 OK", body: #"{"status":"cleared"}"#)
        case ("POST", "/classify"):
            return try await handleClassify(request: request)
        case ("POST", "/notify-test"):
            return try await handleNotifyTest(request: request, dependencies: dependencies)
        case ("POST", "/simulate"), ("GET", "/history"):
            // Deferred — ship a 501 so clients see a clear message rather
            // than a 404 that looks like a path typo.
            return httpResponse(
                status: "501 Not Implemented",
                body: #"{"error":"endpoint not yet implemented"}"#
            )
        default:
            return httpResponse(status: "404 Not Found", body: #"{"error":"not found"}"#)
        }
    }

    // MARK: - Endpoint handlers

    private static func handleState(dependencies: Dependencies) async -> Data {
        let state = await dependencies.monitor.currentState()
        let hasCreds = await dependencies.credentialStore.hasCredentials
        let payload = StateResponse(
            visibleState: describe(state.visibleState),
            consecutiveFailureCount: state.consecutiveFailureCount,
            lastSuccessAt: state.lastSuccessAt?.iso8601,
            lastAttemptAt: state.lastAttemptAt?.iso8601,
            hasCredentials: hasCreds
        )
        return jsonResponse(payload)
    }

    private static func handleSimulateFailure(
        request: Request,
        dependencies: Dependencies
    ) async throws -> Data {
        guard let body = request.body,
              let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
              let count = json["count"] as? Int else {
            return httpResponse(
                status: "400 Bad Request",
                body: #"{"error":"expected {\"category\":\"...\", \"count\":N}"}"#
            )
        }
        let categoryString = json["category"] as? String ?? "networkFailure"
        let category: APIErrorCategory
        switch categoryString {
        case "authFailure": category = .authFailure
        case "botBlocked": category = .botBlocked
        case "decodeFailure": category = .decodeFailure
        case "serverError":
            category = .serverError(message: (json["message"] as? String) ?? "simulated")
        default: category = .networkFailure
        }
        await dependencies.monitor.injectFailures(category, count: count)
        return await handleState(dependencies: dependencies)
    }

    private static func handleClassify(request: Request) throws -> Data {
        guard let body = request.body else {
            return httpResponse(status: "400 Bad Request", body: #"{"error":"missing body"}"#)
        }
        // Try to decode the body as a HomeChargerSnapshot projection from
        // the raw ChargePoint `home_charger_status` JSON shape. We need the
        // three fields the classifier cares about; everything else is
        // ignored.
        struct ClassifyInput: Decodable {
            let isConnected: Bool
            let isPluggedIn: Bool
            let chargingStatus: String
            let activeSession: ClassifySession?
        }
        struct ClassifySession: Decodable {
            let sessionId: Int
            let state: String
        }
        do {
            let input = try JSONDecoder().decode(ClassifyInput.self, from: body)
            let session = input.activeSession.map {
                ActiveSessionInfo(sessionId: $0.sessionId, state: $0.state)
            }
            let snapshot = HomeChargerSnapshot(
                chargerId: 0,
                isConnected: input.isConnected,
                isPluggedIn: input.isPluggedIn,
                chargingStatus: input.chargingStatus,
                activeSession: session
            )
            let state = ChargerClassifier.classify(snapshot)
            return jsonResponse(ClassifyResponse(state: describe(state)))
        } catch {
            return httpResponse(
                status: "400 Bad Request",
                body: #"{"error":"expected HomeChargerSnapshot JSON"}"#
            )
        }
    }

    private static func handleNotifyTest(
        request: Request,
        dependencies: Dependencies
    ) async throws -> Data {
        guard let body = request.body,
              let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
              let title = json["title"] as? String,
              let text = json["body"] as? String else {
            return httpResponse(
                status: "400 Bad Request",
                body: #"{"error":"expected {\"title\":\"...\",\"body\":\"...\"}"}"#
            )
        }
        await dependencies.notificationSink.deliver(title: title, body: text)
        return httpResponse(status: "200 OK", body: #"{"status":"delivered"}"#)
    }

    // MARK: - HTTP parsing + writing

    private struct Request {
        let method: String
        let path: String
        let body: Data?
    }

    private static func parseRequest(_ data: Data) -> Request? {
        guard let text = String(data: data, encoding: .utf8) else { return nil }
        // Split on the empty line that separates headers from body.
        let parts = text.components(separatedBy: "\r\n\r\n")
        guard let head = parts.first else { return nil }
        let lines = head.split(separator: "\r\n", omittingEmptySubsequences: false)
        guard let requestLine = lines.first else { return nil }
        let tokens = requestLine.split(separator: " ")
        guard tokens.count >= 2 else { return nil }
        let method = String(tokens[0])
        let path = String(tokens[1])

        // Body is whatever followed the blank line, decoded back to bytes.
        let body: Data?
        if parts.count > 1 {
            body = Data(parts.dropFirst().joined(separator: "\r\n\r\n").utf8)
        } else {
            body = nil
        }
        return Request(method: method, path: path, body: body)
    }

    private static func httpResponse(status: String, body: String) -> Data {
        let response = """
        HTTP/1.1 \(status)\r
        Content-Type: application/json\r
        Content-Length: \(body.utf8.count)\r
        Connection: close\r
        \r
        \(body)
        """
        return Data(response.utf8)
    }

    private static func jsonResponse<T: Encodable>(_ payload: T) -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(payload),
              let body = String(data: data, encoding: .utf8) else {
            return httpResponse(status: "500", body: #"{"error":"encode"}"#)
        }
        return httpResponse(status: "200 OK", body: body)
    }

    // MARK: - DTOs

    private struct StateResponse: Encodable {
        let visibleState: String
        let consecutiveFailureCount: Int
        let lastSuccessAt: String?
        let lastAttemptAt: String?
        let hasCredentials: Bool
    }

    private struct ClassifyResponse: Encodable {
        let state: String
    }

    private static func describe(_ state: ChargerState) -> String {
        switch state {
        case .unknown: return "unknown"
        case .signedOut: return "signedOut"
        case .healthyIdle: return "healthyIdle"
        case .healthyPluggedIn: return "healthyPluggedIn"
        case .activelyCharging: return "activelyCharging"
        case .error(let reason): return "error: \(reason)"
        }
    }
}

private extension Date {
    var iso8601: String {
        ISO8601DateFormatter().string(from: self)
    }
}
#endif
