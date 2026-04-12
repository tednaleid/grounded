#if DEBUG
import Foundation

/// Port for the DEBUG-only inspect surface. `InspectServer` receives HTTP
/// requests on `localhost:9877` and translates them into calls on this
/// port. The production implementation lives in `Sources/App/` and is a
/// thin bridge to the real `ChargerMonitor`. The full API lands in Phase 2
/// step F2; Block B only commits the read surface.
protocol InspectSink: Sendable {
    func currentState() async -> MonitorState
}
#endif
