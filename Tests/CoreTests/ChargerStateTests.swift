import Testing

@Suite("ChargerState")
struct ChargerStateTests {
    @Test("distinct cases are not equal")
    func distinctCasesAreNotEqual() {
        #expect(ChargerState.unknown != ChargerState.signedOut)
    }

    @Test("error carries a descriptive reason")
    func errorCarriesReason() {
        let state = ChargerState.error("Charger offline")
        guard case let .error(reason) = state else {
            Issue.record("expected .error case, got \(state)")
            return
        }
        #expect(reason == "Charger offline")
    }

    @Test("two error states with the same reason are equal")
    func errorEquality() {
        #expect(ChargerState.error("x") == ChargerState.error("x"))
        #expect(ChargerState.error("x") != ChargerState.error("y"))
    }
}
