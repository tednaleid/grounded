#if DEBUG
import Foundation
import Network

/// Minimal debug HTTP server for Phase 1. Phase 2 will expand the surface.
/// Only implements `GET /state` → `{"state":"unknown","hasCredentials":false}`.
final class InspectServer: @unchecked Sendable {
    static let shared = InspectServer()

    static let port: NWEndpoint.Port = 9877

    private let queue = DispatchQueue(label: "com.tednaleid.grounded.inspect-server")
    private var listener: NWListener?

    private init() {}

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
        } catch {
            NSLog("grounded inspect server failed to start on port \(Self.port): \(error)")
        }
    }

    private func accept(_ connection: NWConnection) {
        connection.start(queue: queue)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] data, _, _, _ in
            guard let self, let data, let request = String(data: data, encoding: .utf8) else {
                connection.cancel()
                return
            }
            let response = self.handle(request: request)
            connection.send(
                content: response,
                completion: .contentProcessed { _ in connection.cancel() }
            )
        }
    }

    private func handle(request: String) -> Data {
        let requestLine = request.split(whereSeparator: { $0 == "\r" || $0 == "\n" }).first ?? ""
        let parts = requestLine.split(separator: " ")
        let method = parts.first.map(String.init) ?? ""
        let path = parts.dropFirst().first.map(String.init) ?? ""

        switch (method, path) {
        case ("GET", "/state"):
            return Self.jsonResponse(status: "200 OK", body: #"{"state":"unknown","hasCredentials":false}"#)
        default:
            return Self.jsonResponse(status: "404 Not Found", body: #"{"error":"not found"}"#)
        }
    }

    private static func jsonResponse(status: String, body: String) -> Data {
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
}
#endif
