import Foundation
import Testing

@Suite("UNCenterNotificationSink")
struct UNCenterNotificationSinkTests {
    // UNUserNotificationCenter needs a real app context to deliver or
    // query authorization; exercising it from a bare test bundle tends
    // to hang the xctest process. This smoke test confirms the type
    // compiles and the init path works. Real delivery is hand-tested
    // via `just inspect-notify "title" "body"` per the contract.
    @Test("sink can be constructed")
    func construction() {
        _ = UNCenterNotificationSink()
    }
}
