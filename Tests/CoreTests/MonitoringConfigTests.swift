import Foundation
import Testing

@Suite("MonitoringConfig defaults")
struct MonitoringConfigTests {
    @Test("default poll interval is 10 minutes")
    func defaultPollInterval() {
        let config = MonitoringConfig.default
        #expect(config.pollInterval == 600)
    }

    @Test("default failure threshold is 3")
    func defaultFailureThreshold() {
        #expect(MonitoringConfig.default.failureThreshold == 3)
    }

    @Test("default in-tick retry delays are [2, 6]")
    func defaultRetryDelays() {
        #expect(MonitoringConfig.default.inTickRetryDelays == [2, 6])
    }
}

@Suite("RetryPolicy")
struct RetryPolicyTests {
    private let policy = RetryPolicy(delays: [2, 6])

    @Test("retries networkFailure")
    func retriesNetworkFailure() {
        #expect(policy.shouldRetry(.networkFailure))
    }

    @Test("retries serverError")
    func retriesServerError() {
        #expect(policy.shouldRetry(.serverError(message: "503")))
    }

    @Test("retries decodeFailure")
    func retriesDecodeFailure() {
        #expect(policy.shouldRetry(.decodeFailure))
    }

    @Test("does NOT retry authFailure")
    func noRetryOnAuthFailure() {
        #expect(!policy.shouldRetry(.authFailure))
    }

    @Test("does NOT retry botBlocked")
    func noRetryOnBotBlocked() {
        #expect(!policy.shouldRetry(.botBlocked))
    }

    @Test("delays match the injected schedule")
    func delaysExposed() {
        #expect(policy.delays == [2, 6])
    }

    @Test("attempts budget is delays.count + 1")
    func attemptsBudget() {
        #expect(policy.maxAttempts == 3)
    }
}
