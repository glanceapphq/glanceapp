import AppKit
import OSLog

/// Entry point for capture requests coming from the menu bar or global hot keys.
///
/// Gates requests behind the permission check, drives the selection overlay and
/// opens each result in its own editor window.
final class CaptureCoordinator {
    private let permissions: PermissionService
    private let captureService = CaptureService()
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "screenshot-app", category: "Capture")

    private var selection: SelectionOverlayController?
    /// Open editors, kept alive until their window closes.
    private var editors: [ObjectIdentifier: EditorWindowController] = [:]
    /// Guards against overlapping captures (e.g. a hot key pressed during selection).
    private var isBusy = false

    init(permissions: PermissionService) {
        self.permissions = permissions
    }

    func captureArea() {
        guard !isBusy, permissions.ensureScreenRecordingAccess(), let screen = NSScreen.underMouse else { return }
        isBusy = true

        let selection = SelectionOverlayController(screen: screen)
        self.selection = selection
        selection.begin { [weak self] rect in
            guard let self else { return }
            guard let rect else {
                endCapture()
                return
            }

            // Keep the overlay up while capturing; it's excluded from the image,
            // so there's no need to wait for the window server to remove it.
            let excluded = Set([self.selection?.windowID].compactMap { $0 })
            Task {
                await self.perform(on: screen) { try await self.captureService.captureRect(rect, on: screen, excludingWindowIDs: excluded) }
            }
        }
    }

    func captureFullScreen() {
        guard !isBusy, permissions.ensureScreenRecordingAccess(), let screen = NSScreen.underMouse else { return }
        isBusy = true

        Task {
            await perform(on: screen) { try await self.captureService.captureScreen(screen) }
        }
    }

    // MARK: - Private

    /// Runs `capture` and opens the result in an editor on `screen`.
    private func perform(on screen: NSScreen, _ capture: () async throws -> Screenshot) async {
        do {
            let screenshot = try await capture()
            logger.info("Captured \(screenshot.image.width)×\(screenshot.image.height) px")
            endCapture()
            openEditor(for: screenshot, on: screen)
        } catch {
            logger.error("Capture failed: \(error.localizedDescription)")
            endCapture()
            presentError(error)
        }
    }

    private func endCapture() {
        selection?.close()
        selection = nil
        isBusy = false
    }

    private func openEditor(for screenshot: Screenshot, on screen: NSScreen) {
        let editor = EditorWindowController(screenshot: screenshot)
        let id = ObjectIdentifier(editor)
        editor.onClose = { [weak self] in self?.editors[id] = nil }
        editors[id] = editor
        editor.show(on: screen)
    }

    private func presentError(_ error: Error) {
        let alert = NSAlert(error: error)
        alert.messageText = "Screenshot Failed"
        alert.informativeText = error.localizedDescription
        NSApp.activate()
        alert.runModal()
    }
}
