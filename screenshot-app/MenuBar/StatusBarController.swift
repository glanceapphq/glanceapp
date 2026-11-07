import AppKit

/// Owns the menu bar icon and its menu.
final class StatusBarController: NSObject {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let onCapture: (CaptureMode) -> Void
    private let onOpenSettings: () -> Void

    init(onCapture: @escaping (CaptureMode) -> Void, onOpenSettings: @escaping () -> Void) {
        self.onCapture = onCapture
        self.onOpenSettings = onOpenSettings
        super.init()

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "camera.viewfinder", accessibilityDescription: "Screenshot")
            button.image?.isTemplate = true
        }
        statusItem.menu = makeMenu()
    }

    isolated deinit {
        NSStatusBar.system.removeStatusItem(statusItem)
    }

    // MARK: - Private

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()

        for mode in CaptureMode.allCases {
            let hotKey = mode.defaultHotKey
            let item = NSMenuItem(title: mode.title, action: #selector(captureSelected(_:)), keyEquivalent: hotKey.key)
            item.keyEquivalentModifierMask = hotKey.modifiers
            item.tag = Int(mode.rawValue)
            item.target = self
            menu.addItem(item)
        }

        menu.addItem(.separator())

        let settings = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)

        menu.addItem(.separator())

        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        return menu
    }

    @objc private func captureSelected(_ sender: NSMenuItem) {
        guard let mode = CaptureMode(rawValue: UInt32(sender.tag)) else { return }
        onCapture(mode)
    }

    @objc private func openSettings() {
        onOpenSettings()
    }
}
