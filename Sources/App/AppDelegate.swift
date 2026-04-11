import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            let image = NSImage(
                systemSymbolName: "bolt.car.circle",
                accessibilityDescription: "grounded"
            )
            image?.isTemplate = false
            button.image = image
            button.contentTintColor = .secondaryLabelColor
        }

        let menu = NSMenu()
        menu.addItem(withTitle: "grounded (empty)", action: nil, keyEquivalent: "")
        menu.addItem(NSMenuItem.separator())
        menu.addItem(
            withTitle: "Quit grounded",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        item.menu = menu
        statusItem = item

        #if DEBUG
        InspectServer.shared.start()
        #endif
    }
}
