import AppKit
import CoreGraphics

/// Checks and requests the Screen Recording (TCC) permission required by ScreenCaptureKit.
final class PermissionService {
    private static let didRequestAccessKey = "didRequestScreenRecordingAccess"
    private static let settingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!

    /// Whether the app currently has Screen Recording access. Does not prompt.
    var hasScreenRecordingAccess: Bool {
        CGPreflightScreenCaptureAccess()
    }

    /// Returns `true` when access is granted. Otherwise guides the user towards
    /// granting it and returns `false`.
    ///
    /// The first time, macOS shows its own prompt (and adds the app to the list in
    /// System Settings). macOS never shows that prompt again, so on later attempts
    /// we show our own alert pointing to System Settings.
    func ensureScreenRecordingAccess() -> Bool {
        if hasScreenRecordingAccess { return true }

        let defaults = UserDefaults.standard
        if !defaults.bool(forKey: Self.didRequestAccessKey) {
            defaults.set(true, forKey: Self.didRequestAccessKey)
            return CGRequestScreenCaptureAccess()
        }

        presentMissingPermissionAlert()
        return false
    }

    /// Opens Privacy & Security → Screen & System Audio Recording.
    func openScreenRecordingSettings() {
        // Ensures the app is listed in System Settings even if the user never saw the system prompt.
        _ = CGRequestScreenCaptureAccess()
        NSWorkspace.shared.open(Self.settingsURL)
    }

    // MARK: - Private

    private func presentMissingPermissionAlert() {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Screen Recording Permission Required"
        alert.informativeText = """
            To take screenshots, allow this app in System Settings → Privacy & Security → \
            Screen & System Audio Recording.

            macOS may ask you to quit and reopen the app after granting access.
            """
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Later")

        // Accessory apps are not frontmost by default; bring the alert to the user.
        NSApp.activate()
        if alert.runModal() == .alertFirstButtonReturn {
            openScreenRecordingSettings()
        }
    }
}
