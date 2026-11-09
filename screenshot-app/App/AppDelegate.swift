import AppKit

/// Owns the app's long-lived services and wires them together.
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let appState = AppState()
    private let permissions = PermissionService()
    private let history = CaptureHistory()
    private lazy var captureCoordinator = CaptureCoordinator(permissions: permissions, history: history)
    private lazy var settingsWindow = SettingsWindowController(
        appState: appState,
        permissions: permissions,
        shortcutActions: ShortcutActions(
            change: { [weak self] hotKey, mode in self?.changeHotKey(hotKey, for: mode) },
            setRecording: { [weak self] isRecording in self?.setHotKeysSuspended(isRecording) }
        )
    )

    private var statusBar: StatusBarController?
    private var hotKeys: HotKeyService?

    func applicationDidFinishLaunching(_ notification: Notification) {
        appState.hasScreenRecordingPermission = permissions.hasScreenRecordingAccess

        statusBar = StatusBarController(
            onCapture: { [weak self] mode in self?.capture(mode) },
            recentCaptures: { [weak self] in self?.history.entries ?? [] },
            onOpenRecent: { [weak self] id in self?.captureCoordinator.reopen(id) },
            onClearRecent: { [weak self] in self?.history.removeAll() },
            onOpenSettings: { [weak self] in self?.settingsWindow.show() }
        )

        registerHotKeys()
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotKeys?.unregisterAll()
    }

    // MARK: - Private

    private func registerHotKeys() {
        hotKeys = HotKeyService { [weak self] id in
            guard let mode = CaptureMode(rawValue: id) else { return }
            // Leave the Carbon event handler before doing any UI work (alerts, overlays).
            Task { self?.capture(mode) }
        }
        applyHotKeys()
    }

    /// Registers the saved shortcuts and updates the state and menu that display them.
    private func applyHotKeys() {
        guard let hotKeys else { return }

        for mode in CaptureMode.allCases {
            let hotKey = HotKeySettings.hotKey(for: mode)
            appState.hotKeys[mode] = hotKey
            appState.unavailableHotKeys[mode] = hotKeys.register(hotKey, id: mode.rawValue) ? nil : true
        }
        statusBar?.updateHotKeys(appState.hotKeys)
    }

    /// Saves a new shortcut for `mode` (`nil` restores the default).
    /// - Returns: An error message if the shortcut can't be used.
    private func changeHotKey(_ hotKey: HotKey?, for mode: CaptureMode) -> String? {
        let newHotKey = hotKey ?? mode.defaultHotKey
        if let other = CaptureMode.allCases.first(where: { $0 != mode && HotKeySettings.hotKey(for: $0) == newHotKey }) {
            return "Already used for \(other.title)."
        }

        HotKeySettings.setHotKey(hotKey, for: mode)
        applyHotKeys()
        return nil
    }

    /// Pauses global hot keys while a new shortcut is being recorded, so pressing an
    /// existing one records it instead of starting a capture.
    private func setHotKeysSuspended(_ suspended: Bool) {
        if suspended {
            CaptureMode.allCases.forEach { hotKeys?.unregister(id: $0.rawValue) }
        } else {
            applyHotKeys()
        }
    }

    private func capture(_ mode: CaptureMode) {
        switch mode {
        case .area: captureCoordinator.captureArea()
        case .fullScreen: captureCoordinator.captureFullScreen()
        }
        appState.hasScreenRecordingPermission = permissions.hasScreenRecordingAccess
    }
}
