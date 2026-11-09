import AppKit

/// Owns the menu bar icon and its menu.
final class StatusBarController: NSObject, NSMenuDelegate {
    /// Where direct-download (DMG) users get new versions.
    private static let releasesURL = URL(string: "https://github.com/glanceapphq/glanceapp/releases")!

    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let onCapture: (CaptureMode) -> Void
    private let recentCaptures: () -> [CaptureHistoryEntry]
    private let onOpenRecent: (UUID) -> Void
    private let onClearRecent: () -> Void
    private let onOpenSettings: () -> Void
    private var captureItems: [CaptureMode: NSMenuItem] = [:]
    private let recentMenu = NSMenu(title: "Recent Captures")

    init(
        onCapture: @escaping (CaptureMode) -> Void,
        recentCaptures: @escaping () -> [CaptureHistoryEntry],
        onOpenRecent: @escaping (UUID) -> Void,
        onClearRecent: @escaping () -> Void,
        onOpenSettings: @escaping () -> Void
    ) {
        self.onCapture = onCapture
        self.recentCaptures = recentCaptures
        self.onOpenRecent = onOpenRecent
        self.onClearRecent = onClearRecent
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

        // Filled in by `menuNeedsUpdate(_:)` each time it opens.
        recentMenu.delegate = self
        let recent = NSMenuItem(title: "Recent Captures", action: nil, keyEquivalent: "")
        recent.submenu = recentMenu
        menu.addItem(recent)

        menu.addItem(.separator())

        let settings = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)

        // The App Store updates its copies itself, and doesn't allow pointing elsewhere for updates.
        if !Self.isFromAppStore {
            let updates = NSMenuItem(title: "Check for Updates…", action: #selector(checkForUpdates), keyEquivalent: "")
            updates.target = self
            menu.addItem(updates)
        }

        menu.addItem(.separator())

        menu.addItem(NSMenuItem(title: "Quit Glance", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        return menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        guard menu === recentMenu else { return }
        menu.removeAllItems()

        let entries = recentCaptures()
        guard !entries.isEmpty else {
            let empty = NSMenuItem(title: "No Recent Captures", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
            return
        }

        for entry in entries {
            let item = NSMenuItem(title: Self.title(for: entry), action: #selector(openRecent(_:)), keyEquivalent: "")
            item.image = entry.thumbnail
            item.representedObject = entry.id
            item.target = self
            menu.addItem(item)
        }

        menu.addItem(.separator())
        let clear = NSMenuItem(title: "Clear History", action: #selector(clearRecent), keyEquivalent: "")
        clear.target = self
        menu.addItem(clear)
    }

    /// E.g. "14:32 · 1280 × 720", with the date for captures from earlier days.
    private static func title(for entry: CaptureHistoryEntry) -> String {
        let time = Calendar.current.isDateInToday(entry.date)
            ? entry.date.formatted(date: .omitted, time: .shortened)
            : entry.date.formatted(date: .abbreviated, time: .shortened)
        return "\(time) · \(Int(entry.size.width.rounded())) × \(Int(entry.size.height.rounded()))"
    }

    @objc private func openRecent(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID else { return }
        onOpenRecent(id)
    }

    @objc private func clearRecent() {
        onClearRecent()
    }

    @objc private func captureSelected(_ sender: NSMenuItem) {
        guard let mode = CaptureMode(rawValue: UInt32(sender.tag)) else { return }
        onCapture(mode)
    }

    /// Copies from the App Store (and TestFlight) carry a receipt in the bundle; direct downloads don't.
    private static var isFromAppStore: Bool {
        let receipts = Bundle.main.bundleURL.appending(path: "Contents/_MASReceipt", directoryHint: .isDirectory)
        return FileManager.default.fileExists(atPath: receipts.path(percentEncoded: false))
    }

    @objc private func checkForUpdates() {
        NSWorkspace.shared.open(Self.releasesURL)
    }

    @objc private func openSettings() {
        onOpenSettings()
    }
}
