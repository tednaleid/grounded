import Foundation
import Testing

@Suite("APIErrorMapping")
struct APIErrorMappingTests {
    private let url = URL(string: "https://example.com/foo")!

    private func response(status: Int) -> HTTPURLResponse {
        HTTPURLResponse(
            url: url,
            statusCode: status,
            httpVersion: "HTTP/1.1",
            headerFields: nil
        )!
    }

    @Test("nil for 200 success")
    func successIsNil() {
        let category = APIErrorMapping.classify(
            response: response(status: 200),
            data: Data(),
            error: nil
        )
        #expect(category == nil)
    }

    @Test("nil for 204 success")
    func success204IsNil() {
        #expect(APIErrorMapping.classify(response: response(status: 204), data: nil, error: nil) == nil)
    }

    @Test(".networkFailure when transport error is set")
    func transportErrorWins() {
        let networkError = NSError(domain: NSURLErrorDomain, code: NSURLErrorTimedOut)
        let category = APIErrorMapping.classify(
            response: response(status: 200),
            data: nil,
            error: networkError
        )
        #expect(category == .networkFailure)
    }

    @Test(".networkFailure when no HTTPURLResponse")
    func noResponseIsNetworkFailure() {
        #expect(APIErrorMapping.classify(response: nil, data: nil, error: nil) == .networkFailure)
    }

    @Test(".authFailure for 401")
    func authFailureFor401() {
        #expect(APIErrorMapping.classify(response: response(status: 401), data: nil, error: nil) == .authFailure)
    }

    @Test(".botBlocked for 403 with datadome JSON body")
    func datadomeFor403WithUrlField() {
        let body = Data(#"{"url":"https://geo.captcha-delivery.com/captcha/?initialCid=abc"}"#.utf8)
        let category = APIErrorMapping.classify(
            response: response(status: 403),
            data: body,
            error: nil
        )
        #expect(category == .botBlocked)
    }

    @Test(".serverError for 403 without datadome body")
    func serverErrorFor403WithoutUrl() {
        let body = Data(#"{"error":"forbidden"}"#.utf8)
        let category = APIErrorMapping.classify(
            response: response(status: 403),
            data: body,
            error: nil
        )
        #expect(category == .serverError(message: "HTTP 403"))
    }

    @Test(".serverError for 500")
    func serverErrorFor500() {
        #expect(
            APIErrorMapping.classify(response: response(status: 500), data: nil, error: nil) ==
                .serverError(message: "HTTP 500")
        )
    }

    @Test(".serverError for 502 with status code in message")
    func serverErrorFor502WithMessage() {
        let category = APIErrorMapping.classify(response: response(status: 502), data: nil, error: nil)
        guard case let .serverError(message) = category else {
            Issue.record("expected .serverError")
            return
        }
        #expect(message.contains("502"))
    }
}
