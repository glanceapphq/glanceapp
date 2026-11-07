import Observation

/// Observable app-wide state shared between services and SwiftUI views.
@Observable
final class AppState {
    /// Last known Screen Recording permission status.
    var hasScreenRecordingPermission = false

    /// Current shortcut for each capture mode.
    var hotKeys: [CaptureMode: HotKey] = [:]

    /// Capture modes whose global hot key could not be registered
    /// (usually because another app already owns the shortcut).
    var unavailableHotKeys: [CaptureMode: Bool] = [:]
}
