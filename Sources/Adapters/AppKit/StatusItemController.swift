import AppKit
import Foundation

/// Production `StateObserver` for the menubar icon. Recolors the
/// `NSStatusItem` and rebuilds its dropdown menu whenever the monitor
/// transitions between visible states.
///
/// Lives in `Sources/Adapters/AppKit/` so it can import AppKit without
/// polluting Core. Constructed by `AppDelegate` with the shared status
/// item and menu actions already wired.
@MainActor
final class StatusItemController: StateObserver {
    private let statusItem: NSStatusItem
    private var currentMenuState: MenuState = .initial

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
        applyIcon(for: .unknown)
        applyMenu()
    }

    nonisolated func stateDidChange(from previous: ChargerState, to current: ChargerState) async {
        await MainActor.run {
            self.applyIcon(for: current)
            self.applyMenu()
        }
    }

    /// Refresh the menu from a full `MonitorState`. Called by `AppDelegate`
    /// after every tick completes, separately from the transition
    /// observer notification, so the "last checked" / "last successful
    /// check" lines stay fresh even when the visible state didn't change.
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
        applyMenu()
    }

    /// Read the currently rendered menu state. Used by tests.
    func snapshotMenuState() -> MenuState {
        currentMenuState
    }

    // MARK: - Icon

    private func applyIcon(for state: ChargerState) {
        let image = NSImage(
            systemSymbolName: "bolt.car.circle",
            accessibilityDescription: "grounded"
        )
        image?.isTemplate = false
        statusItem.button?.image = image
        statusItem.button?.contentTintColor = Self.tint(for: state)
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

    private func applyMenu() {
        let menu = NSMenu()
        menu.autoenablesItems = false

        let title = NSMenuItem(title: currentMenuState.statusTitle, action: nil, keyEquivalent: "")
        title.isEnabled = false
        menu.addItem(title)

        if let lastChecked = currentMenuState.lastCheckedRelative {
            let item = NSMenuItem(title: "Last checked: \(lastChecked)", action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        }
        if let lastSuccess = currentMenuState.lastSuccessRelative {
            let item = NSMenuItem(title: "Last successful: \(lastSuccess)", action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        }
        menu.addItem(NSMenuItem.separator())

        if currentMenuState.showsSignIn {
            menu.addItem(Self.menuItem(title: "Sign in to ChargePoint…", target: self, action: #selector(didTapSignIn)))
        }
        if currentMenuState.showsSignOut {
            menu.addItem(Self.menuItem(title: "Sign out", target: self, action: #selector(didTapSignOut)))
        }
        menu.addItem(Self.menuItem(
            title: "Open ChargePoint…",
            target: self,
            action: #selector(didTapOpenChargePoint)
        ))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(Self.menuItem(
            title: "Quit grounded",
            target: self,
            action: #selector(didTapQuit),
            keyEquivalent: "q"
        ))

        statusItem.menu = menu
    }

    private static func menuItem(
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
