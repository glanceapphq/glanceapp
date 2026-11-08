import AppKit

/// Owns the menu bar icon and its menu.
final class StatusBarController: NSObject {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let onCapture: (CaptureMode) -> Void
    private let onOpenSettings: () -> Void
    private var captureItems: [CaptureMode: NSMenuItem] = [:]

    init(onCapture: @escaping (CaptureMode) -> Void, onOpenSettings: @escaping () -> Void) {
        self.onCapture = onCapture
        self.onOpenSettings = onOpenSettings
        super.init()

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "camera.viewfinder", accessibilityDescription: "Glance")
            button.image?.isTemplate = true
        }
        statusItem.menu = makeMenu()
    }

    isolated deinit {
        NSStatusBar.system.removeStatusItem(statusItem)
    }

    /// Shows the current shortcuts next to the capture items.
    func updateHotKeys(_ hotKeys: [CaptureMode: HotKey]) {
        for (mode, item) in captureItems {
            item.keyEquivalent = hotKeys[mode]?.menuKeyEquivalent ?? ""
            item.keyEquivalentModifierMask = hotKeys[mode]?.modifiers ?? []
        }
    }

    // MARK: - Private

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()

        for mode in CaptureMode.allCases {
            // Key equivalents are filled in by `updateHotKeys(_:)` once shortcuts are registered.
            let item = NSMenuItem(title: mode.title, action: #selector(captureSelected(_:)), keyEquivalent: "")
            item.tag = Int(mode.rawValue)
            item.target = self
            menu.addItem(item)
            captureItems[mode] = item
        }

        menu.addItem(.separator())

        let settings = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)

        menu.addItem(.separator())

        menu.addItem(NSMenuItem(title: "Quit Glance", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

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
