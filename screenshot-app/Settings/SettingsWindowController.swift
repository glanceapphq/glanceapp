import AppKit
import SwiftUI

/// Presents `SettingsView` in a standard AppKit window.
///
/// The window (and its hosting controller) is created lazily and released when
/// closed, so nothing stays in memory while Settings isn't visible.
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private let appState: AppState
    private let permissions: PermissionService
    private let shortcutActions: ShortcutActions
    private var window: NSWindow?

    init(appState: AppState, permissions: PermissionService, shortcutActions: ShortcutActions) {
        self.appState = appState
        self.permissions = permissions
        self.shortcutActions = shortcutActions
    }

    func show() {
        let window = window ?? makeWindow()
        self.window = window

        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        window?.delegate = nil
        window = nil
    }

    // MARK: - Private

    private func makeWindow() -> NSWindow {
        let hostingController = NSHostingController(rootView: SettingsView(appState: appState, permissions: permissions, shortcutActions: shortcutActions))
        hostingController.sizingOptions = [.preferredContentSize]

        let window = NSWindow(contentViewController: hostingController)
        window.title = "Settings"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        return window
    }
}
