import Foundation

/// Port for presenting the ChargePoint sign-in flow. The production adapter
/// is a `WKWebView` that navigates to `driver.chargepoint.com`, watches the
/// cookie store for a `coulomb_sess` cookie, and harvests the value along
/// with discovery/profile data into a `Credentials` struct.
///
/// Marked `@MainActor` because WebKit can only be touched from the main
/// thread. Main-actor isolation implies `Sendable`.
@MainActor
protocol BrowserAuth {
    func presentLogin() async throws -> Credentials
}
