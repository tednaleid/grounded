import Testing

@Suite("APIErrorCategory")
struct APIErrorCategoryTests {
    @Test("networkFailure is transient")
    func networkFailureIsTransient() {
        #expect(APIErrorCategory.networkFailure.isTransient)
    }

    @Test("serverError is transient and preserves the message")
    func serverErrorIsTransient() {
        let category = APIErrorCategory.serverError(message: "503 Service Unavailable")
        #expect(category.isTransient)
        guard case let .serverError(message) = category else {
            Issue.record("expected .serverError")
            return
        }
        #expect(message == "503 Service Unavailable")
    }

    @Test("decodeFailure is transient")
    func decodeFailureIsTransient() {
        #expect(APIErrorCategory.decodeFailure.isTransient)
    }

    @Test("authFailure is NOT transient (fast-path to signedOut)")
    func authFailureIsNotTransient() {
        #expect(!APIErrorCategory.authFailure.isTransient)
    }

    @Test("botBlocked is NOT transient (Datadome fast-path to signedOut)")
    func botBlockedIsNotTransient() {
        #expect(!APIErrorCategory.botBlocked.isTransient)
    }

    @Test("equality compares serverError messages")
    func serverErrorEquality() {
        #expect(APIErrorCategory.serverError(message: "x") == .serverError(message: "x"))
        #expect(APIErrorCategory.serverError(message: "x") != .serverError(message: "y"))
    }
}
