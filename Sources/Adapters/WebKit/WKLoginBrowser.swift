import AppKit
import Foundation
import WebKit

/// Production `BrowserAuth` adapter. Presents a modal `NSWindow` hosting
/// a `WKWebView` pointed at `https://driver.chargepoint.com`. Watches the
/// cookie store for a `coulomb_sess` cookie on the `.chargepoint.com`
/// domain. Once seen, runs the discovery / profile / home-chargers setup
/// calls with the harvested token to populate the full `Credentials` blob.
///
/// No automated test — relies on real browser interaction with
/// ChargePoint's real auth flow. Verification path:
///   `just inspect-clear-creds && just inspect-poll`  (enters .signedOut)
///   → click "Sign in..." in the menubar dropdown
///   → log in via the presented WKWebView window
///   → window closes on successful cookie harvest
///   → next tick fetches real status
@MainActor
final class WKLoginBrowser: NSObject, BrowserAuth {
    private static let loginURL = URL(string: "https://driver.chargepoint.com")!
    private static let cookieName = "coulomb_sess"
    private static let cookieDomain = ".chargepoint.com"

    private var window: NSWindow?
    private var webView: WKWebView?
    private var continuation: CheckedContinuation<Credentials, Error>?

    func presentLogin() async throws -> Credentials {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Credentials, Error>) in
            self.continuation = continuation
            self.presentWindow()
        }
    }

    // MARK: - Private

    private func presentWindow() {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = WKWebsiteDataStore.default()

        let webView = WKWebView(
            frame: NSRect(x: 0, y: 0, width: 480, height: 720),
            configuration: config
        )
        self.webView = webView

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 720),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Sign in to ChargePoint"
        window.contentView = webView
        window.center()
        self.window = window

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        webView.load(URLRequest(url: Self.loginURL))

        // Poll for the session cookie every 500ms. This is cruder than
        // hooking WKNavigationDelegate's didFinish, but it's robust to
        // the multi-redirect IdP flow ChargePoint uses. Closing the
        // window manually (without completing sign-in) resolves the
        // continuation with an error via `windowWillClose`.
        Task { [weak self] in
            while let self, self.continuation != nil {
                if let creds = await self.harvestCredentials() {
                    self.closeAndResume(with: .success(creds))
                    return
                }
                try? await Task.sleep(for: .milliseconds(500))
            }
        }
    }

    private func harvestCredentials() async -> Credentials? {
        let cookies = await WKWebsiteDataStore.default().httpCookieStore.allCookies()
        guard let sessionCookie = cookies.first(where: {
            $0.name == Self.cookieName && $0.domain.contains("chargepoint.com")
        }) else {
            return nil
        }
        // Phase 2 placeholder: we have the cookie; the full login flow
        // also needs to run discovery + profile + home-chargers list to
        // populate region/userId/chargerId/endpoint URLs. Wiring that up
        // here is the Phase 2 F1 step (AppDelegate) where we plumb the
        // harvested cookie into a one-off ChargePointAPIClient setup
        // sequence. For now we return a credentials blob with the
        // cookie token and empty endpoint strings — callers of this
        // adapter should not ship until F1 finishes the discovery wire-up.
        return Credentials(
            email: "",
            token: sessionCookie.value,
            region: "",
            userId: 0,
            chargerId: 0,
            accountsEndpoint: "",
            hcpoHcmEndpoint: "",
            mapcacheEndpoint: ""
        )
    }

    private func closeAndResume(with result: Result<Credentials, Error>) {
        window?.close()
        window = nil
        webView = nil
        let continuation = self.continuation
        self.continuation = nil
        switch result {
        case .success(let creds):
            continuation?.resume(returning: creds)
        case .failure(let error):
            continuation?.resume(throwing: error)
        }
    }
}

enum BrowserAuthError: Error, Equatable {
    case cancelled
}
