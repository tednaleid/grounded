import Testing

@Suite("ChargerState")
struct ChargerStateTests {
    @Test("distinct cases are not equal")
    func distinctCasesAreNotEqual() {
        #expect(ChargerState.unknown != ChargerState.signedOut)
    }
}
