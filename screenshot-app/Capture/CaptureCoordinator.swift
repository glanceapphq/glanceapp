import AppKit
import OSLog

/// Entry point for capture requests coming from the menu bar or global hot keys.
///
/// Step 3 will route these calls into `CaptureService` (ScreenCaptureKit) and
/// the selection overlay. For now it only gates them behind the permission check.
final class CaptureCoordinator {
    private let permissions: PermissionService
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "screenshot-app", category: "Capture")

    init(permissions: PermissionService) {
        self.permissions = permissions
    }

    func captureArea() {
        guard permissions.ensureScreenRecordingAccess() else { return }
        logger.info("Capture area requested")
    }

    func captureFullScreen() {
        guard permissions.ensureScreenRecordingAccess() else { return }
        logger.info("Capture full screen requested")
    }
}
