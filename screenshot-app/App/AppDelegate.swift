import AppKit

/// Owns the app's long-lived services and wires them together.
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let appState = AppState()
    private let permissions = PermissionService()
    private lazy var captureCoordinator = CaptureCoordinator(permissions: permissions)
    private lazy var settingsWindow = SettingsWindowController(appState: appState, permissions: permissions)

    private var statusBar: StatusBarController?
    private var hotKeys: HotKeyService?

    func applicationDidFinishLaunching(_ notification: Notification) {
        appState.hasScreenRecordingPermission = permissions.hasScreenRecordingAccess

        statusBar = StatusBarController(
            onCapture: { [weak self] mode in self?.capture(mode) },
            onOpenSettings: { [weak self] in self?.settingsWindow.show() }
        )

        registerHotKeys()
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotKeys?.unregisterAll()
    }

    // MARK: - Private

    private func registerHotKeys() {
        let hotKeys = HotKeyService { [weak self] id in
            guard let mode = CaptureMode(rawValue: id) else { return }
            // Leave the Carbon event handler before doing any UI work (alerts, overlays).
            Task { self?.capture(mode) }
        }

        for mode in CaptureMode.allCases {
            appState.unavailableHotKeys[mode] = hotKeys.register(mode.defaultHotKey, id: mode.rawValue) ? nil : true
        }
        self.hotKeys = hotKeys
    }

    private func capture(_ mode: CaptureMode) {
        switch mode {
        case .area: captureCoordinator.captureArea()
        case .fullScreen: captureCoordinator.captureFullScreen()
        }
        appState.hasScreenRecordingPermission = permissions.hasScreenRecordingAccess
    }
}
