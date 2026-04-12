import AppKit
import Foundation
import Testing

@Suite("StatusItemController")
@MainActor
struct StatusItemControllerTests {
    private func makeController() -> (StatusItemController, NSStatusItem) {
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let controller = StatusItemController(statusItem: statusItem)
        return (controller, statusItem)
    }

    @Test("tint for each charger state")
    func tintsPerState() {
        #expect(StatusItemController.tint(for: .unknown) == .secondaryLabelColor)
        #expect(StatusItemController.tint(for: .signedOut) == .secondaryLabelColor)
        #expect(StatusItemController.tint(for: .healthyIdle) == .systemGreen)
        #expect(StatusItemController.tint(for: .healthyPluggedIn) == .systemBlue)
        #expect(StatusItemController.tint(for: .error("x")) == .systemRed)

        // activelyCharging uses an RGB literal — verify the components.
        let yellow = StatusItemController.tint(for: .activelyCharging)
        let converted = yellow.usingColorSpace(.deviceRGB) ?? yellow
        #expect(abs(converted.redComponent - 1.0) < 0.01)
        #expect(abs(converted.greenComponent - 0.95) < 0.01)
        #expect(abs(converted.blueComponent - 0.1) < 0.01)
    }

    @Test("menu shows 'Sign in' when state is signedOut")
    func menuSignedOut() {
        let (controller, _) = makeController()
        let state = MonitorState(
            visibleState: .signedOut,
            lastSuccessfulSnapshot: nil,
            lastSuccessAt: nil,
            lastAttemptAt: Date(),
            consecutiveFailureCount: 0
        )
        controller.refreshMenu(from: state)
        let snapshot = controller.snapshotMenuState()
        #expect(snapshot.showsSignIn)
        #expect(!snapshot.showsSignOut)
        #expect(snapshot.statusTitle == "Signed out")
    }

    @Test("menu shows 'Sign out' when state is healthy")
    func menuHealthy() {
        let (controller, _) = makeController()
        let state = MonitorState(
            visibleState: .healthyIdle,
            lastSuccessfulSnapshot: nil,
            lastSuccessAt: Date(),
            lastAttemptAt: Date(),
            consecutiveFailureCount: 0
        )
        controller.refreshMenu(from: state)
        let snapshot = controller.snapshotMenuState()
        #expect(!snapshot.showsSignIn)
        #expect(snapshot.showsSignOut)
        #expect(snapshot.statusTitle == "Charger idle")
    }

    @Test("menu surfaces error reason in status title")
    func menuErrorSurfacesReason() {
        let (controller, _) = makeController()
        let state = MonitorState(
            visibleState: .error("Charger unreachable"),
            lastSuccessfulSnapshot: nil,
            lastSuccessAt: nil,
            lastAttemptAt: Date(),
            consecutiveFailureCount: 3
        )
        controller.refreshMenu(from: state)
        let snapshot = controller.snapshotMenuState()
        #expect(snapshot.statusTitle.contains("Charger unreachable"))
    }

    @Test("relative time strings are populated when timestamps are set")
    func relativeTimestamps() {
        let (controller, _) = makeController()
        let now = Date()
        let fiveMinAgo = now.addingTimeInterval(-300)
        let tenMinAgo = now.addingTimeInterval(-600)
        let state = MonitorState(
            visibleState: .healthyIdle,
            lastSuccessfulSnapshot: nil,
            lastSuccessAt: tenMinAgo,
            lastAttemptAt: fiveMinAgo,
            consecutiveFailureCount: 0
        )
        controller.refreshMenu(from: state, now: now)
        let snapshot = controller.snapshotMenuState()
        #expect(snapshot.lastCheckedRelative != nil)
        #expect(snapshot.lastSuccessRelative != nil)
    }
}
