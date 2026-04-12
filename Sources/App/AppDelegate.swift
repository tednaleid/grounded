import AppKit
import Foundation
import ServiceManagement

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    // Adapters
    private let clock = SystemClock()
    private let credentialStore = KeychainCredentialStore()
    private let notificationSink = UNCenterNotificationSink()

    // Wired at launch
    private var statusItem: NSStatusItem?
    private var statusItemController: StatusItemController?
    private var monitor: ChargerMonitor?
    #if DEBUG
    private var inspectServer: InspectServer?
    #endif

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
        Task { @MainActor [weak self] in
            await self?.bootMonitoring()
        }
    }

    // MARK: - Status item

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem = item

        let actions = StatusItemController.Actions(
            signIn: { [weak self] in
                Task { @MainActor in await self?.presentSignIn() }
            },
            signOut: { [weak self] in
                Task { @MainActor in await self?.signOut() }
            },
            openChargePoint: {
                if let url = URL(string: "https://driver.chargepoint.com") {
                    NSWorkspace.shared.open(url)
                }
            },
            toggleOpenAtLogin: { [weak self] in
                Task { @MainActor in self?.toggleOpenAtLogin() }
            },
            quit: {
                Task { @MainActor in NSApp.terminate(nil) }
            }
        )
        statusItemController = StatusItemController(statusItem: item, actions: actions)
    }

    // MARK: - Monitoring

    private func bootMonitoring() async {
        _ = await notificationSink.requestAuthorization()

        let apiClient = ChargePointAPIClient(
            credentialStore: credentialStore,
            clock: clock
        )

        let monitor = ChargerMonitor(
            statusSource: apiClient,
            credentialStore: credentialStore,
            notificationSink: notificationSink,
            clock: clock
        )
        self.monitor = monitor

        if let controller = statusItemController {
            await monitor.addObserver(controller)
        }

        // Start the monitor immediately — it'll tick, see no creds (if
        // missing), and fast-path to .signedOut so the user gets a gray
        // menubar icon and a Sign-in menu item right away rather than
        // staring at an unresponsive app while we wait on login.
        await monitor.start()

        #if DEBUG
        let inspect = InspectServer(
            dependencies: InspectServer.Dependencies(
                monitor: monitor,
                credentialStore: credentialStore,
                notificationSink: notificationSink
            )
        )
        inspect.start()
        self.inspectServer = inspect
        #endif

        // If we have no credentials, surface the sign-in window in the
        // background without blocking the launch sequence. The user can
        // always retry via the Sign-in menu item.
        let hasCreds = await credentialStore.hasCredentials
        if !hasCreds {
            Task { @MainActor [weak self] in
                await self?.presentSignIn()
            }
        }
    }

    // MARK: - Login

    private func presentSignIn() async {
        let browser = WKLoginBrowser()
        let flow = LoginFlow(browser: browser)
        do {
            let credentials = try await flow.signIn()
            try await credentialStore.save(credentials)
            await monitor?.performTick()
        } catch {
            NSLog("grounded: login failed: \(error)")
        }
    }

    private func signOut() async {
        try? await credentialStore.clear()
        await monitor?.performTick()
    }

    // MARK: - Open at Login

    private func toggleOpenAtLogin() {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled {
                try service.unregister()
            } else {
                try service.register()
            }
        } catch {
            NSLog("grounded: open-at-login toggle failed: \(error)")
        }
    }
}
