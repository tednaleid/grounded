import AppKit
import Foundation
import ServiceManagement

/// Production `StateObserver` for the menubar icon. Recolors the
/// `NSStatusItem` and rebuilds its dropdown menu whenever the monitor
/// transitions between visible states.
///
/// Lives in `Sources/Adapters/AppKit/` so it can import AppKit without
/// polluting Core. Constructed by `AppDelegate` with the shared status
/// item and menu actions already wired.
@MainActor
final class StatusItemController: NSObject, StateObserver, NSMenuDelegate {
    private let statusItem: NSStatusItem
    private let menu = NSMenu()
    private var currentMenuState: MenuState = .initial
    private var latestMonitorState: MonitorState?

    private var statusTitleItem: NSMenuItem?
    private var lastCheckedItem: NSMenuItem?
    private var lastSuccessItem: NSMenuItem?

    /// Callbacks fired by menu items. Wired by `AppDelegate`.
    struct Actions: Sendable {
        var signIn: @Sendable () -> Void = {}
        var signOut: @Sendable () -> Void = {}
        var openChargePoint: @Sendable () -> Void = {}
        var toggleOpenAtLogin: @Sendable () -> Void = {}
        var quit: @Sendable () -> Void = {}
    }

    private let actions: Actions
    private let relativeTimeFormatter: RelativeDateTimeFormatter

    /// Observable view of the menu content. Tests assert against this
    /// rather than prodding `NSMenu` directly (which is tied to the main
    /// thread and hard to snapshot).
    struct MenuState: Sendable, Equatable {
        var statusTitle: String
        var lastCheckedRelative: String?
        var lastSuccessRelative: String?
        var showsSignIn: Bool
        var showsSignOut: Bool

        static let initial = MenuState(
            statusTitle: "grounded (starting)",
            lastCheckedRelative: nil,
            lastSuccessRelative: nil,
            showsSignIn: false,
            showsSignOut: false
        )
    }

    init(
        statusItem: NSStatusItem,
        actions: Actions = Actions(),
        relativeTimeFormatter: RelativeDateTimeFormatter = StatusItemController.defaultFormatter
    ) {
        self.statusItem = statusItem
        self.actions = actions
        self.relativeTimeFormatter = relativeTimeFormatter
        super.init()
        menu.autoenablesItems = false
        menu.delegate = self
        statusItem.menu = menu
        applyIcon(for: .unknown)
        rebuildMenu()
    }

    nonisolated func stateDidChange(from previous: ChargerState, to current: ChargerState) async {
        await MainActor.run {
            self.applyIcon(for: current)
        }
    }

    nonisolated func tickDidComplete(state: MonitorState) async {
        await MainActor.run {
            self.latestMonitorState = state
            self.applyIcon(for: state.visibleState)
            self.refreshMenu(from: state)
        }
    }

    func menuWillOpen(_ menu: NSMenu) {
        guard let state = latestMonitorState else { return }
        let now = Date()
        if let attempt = state.lastAttemptAt {
            let relative = relativeTimeFormatter.localizedString(for: attempt, relativeTo: now)
            lastCheckedItem?.title = "Last checked: \(relative)"
        }
        if let success = state.lastSuccessAt {
            let relative = relativeTimeFormatter.localizedString(for: success, relativeTo: now)
            lastSuccessItem?.title = "Last successful: \(relative)"
        }
    }

    /// Refresh the menu from a full `MonitorState`. Called after every tick
    /// so the menu structure (sign in/out, status title) stays current.
    func refreshMenu(from state: MonitorState, now: Date = Date()) {
        let lastChecked = state.lastAttemptAt.map {
            relativeTimeFormatter.localizedString(for: $0, relativeTo: now)
        }
        let lastSuccess = state.lastSuccessAt.map {
            relativeTimeFormatter.localizedString(for: $0, relativeTo: now)
        }
        let visible = state.visibleState
        currentMenuState = MenuState(
            statusTitle: Self.title(for: visible),
            lastCheckedRelative: lastChecked,
            lastSuccessRelative: lastSuccess,
            showsSignIn: visible == .signedOut,
            showsSignOut: visible != .signedOut && visible != .unknown
        )
        rebuildMenu()
    }

    /// Read the currently rendered menu state. Used by tests.
    func snapshotMenuState() -> MenuState {
        currentMenuState
    }

    // MARK: - Icon

    private func applyIcon(for state: ChargerState) {
        let color = Self.tint(for: state)
        let config = NSImage.SymbolConfiguration(paletteColors: [color])
        let image = NSImage(
            systemSymbolName: "bolt.car.circle",
            accessibilityDescription: "grounded"
        )?.withSymbolConfiguration(config)
        image?.isTemplate = false
        statusItem.button?.image = image
    }

    static func tint(for state: ChargerState) -> NSColor {
        switch state {
        case .unknown, .signedOut:
            return .secondaryLabelColor
        case .healthyIdle:
            return .systemGreen
        case .healthyPluggedIn:
            return .systemBlue
        case .activelyCharging:
            return NSColor(red: 1.0, green: 0.95, blue: 0.1, alpha: 1.0)
        case .error:
            return .systemRed
        }
    }

    // MARK: - Menu

    private func rebuildMenu() {
        menu.removeAllItems()

        let titleItem = NSMenuItem(title: currentMenuState.statusTitle, action: nil, keyEquivalent: "")
        titleItem.isEnabled = false
        menu.addItem(titleItem)
        statusTitleItem = titleItem

        let checkedItem = NSMenuItem(
            title: currentMenuState.lastCheckedRelative.map { "Last checked: \($0)" } ?? "",
            action: nil,
            keyEquivalent: ""
        )
        checkedItem.isEnabled = false
        checkedItem.isHidden = currentMenuState.lastCheckedRelative == nil
        menu.addItem(checkedItem)
        lastCheckedItem = checkedItem

        let successItem = NSMenuItem(
            title: currentMenuState.lastSuccessRelative.map { "Last successful: \($0)" } ?? "",
            action: nil,
            keyEquivalent: ""
        )
        successItem.isEnabled = false
        successItem.isHidden = currentMenuState.lastSuccessRelative == nil
        menu.addItem(successItem)
        lastSuccessItem = successItem

        menu.addItem(NSMenuItem.separator())
        addActionItems(to: menu)
    }

    private func addActionItems(to menu: NSMenu) {
        if currentMenuState.showsSignIn {
            menu.addItem(Self.actionItem(
                title: "Sign in to ChargePoint…", target: self, action: #selector(didTapSignIn)
            ))
        }
        if currentMenuState.showsSignOut {
            menu.addItem(Self.actionItem(title: "Sign out", target: self, action: #selector(didTapSignOut)))
        }
        menu.addItem(Self.actionItem(
            title: "Open ChargePoint…",
            target: self,
            action: #selector(didTapOpenChargePoint)
        ))
        let openAtLogin = Self.actionItem(
            title: "Open at Login",
            target: self,
            action: #selector(didTapToggleOpenAtLogin)
        )
        openAtLogin.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(openAtLogin)
        menu.addItem(NSMenuItem.separator())
        menu.addItem(Self.actionItem(
            title: "Quit grounded",
            target: self,
            action: #selector(didTapQuit),
            keyEquivalent: "q"
        ))
    }

    private static func actionItem(
        title: String,
        target: AnyObject,
        action: Selector,
        keyEquivalent: String = ""
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        item.target = target
        return item
    }

    @objc private func didTapSignIn() { actions.signIn() }
    @objc private func didTapSignOut() { actions.signOut() }
    @objc private func didTapOpenChargePoint() { actions.openChargePoint() }
    @objc private func didTapToggleOpenAtLogin() { actions.toggleOpenAtLogin() }
    @objc private func didTapQuit() { actions.quit() }

    // MARK: - Helpers

    private static func title(for state: ChargerState) -> String {
        switch state {
        case .unknown:
            return "grounded (starting)"
        case .signedOut:
            return "Signed out"
        case .healthyIdle:
            return "Charger idle"
        case .healthyPluggedIn:
            return "Car plugged in"
        case .activelyCharging:
            return "Charging"
        case .error(let reason):
            return "Error: \(reason)"
        }
    }

    static let defaultFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter
    }()
}
