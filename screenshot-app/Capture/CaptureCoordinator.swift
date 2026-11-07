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

        // Snapshot the window list before the overlay appears, so it isn't in the list.
        let windows = captureService.selectableWindows(on: screen)
        Task {
            do {
                // Freeze the screen first: the overlay shows this image and areas are cut out of it.
                let frozenScreen = try await captureService.captureScreen(screen)
                beginSelection(on: screen, frozenScreen: frozenScreen, windows: windows)
            } catch {
                fail(with: error)
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

    private func beginSelection(on screen: NSScreen, frozenScreen: Screenshot, windows: [SelectableWindow]) {
        let selection = SelectionOverlayController(screen: screen)
        self.selection = selection
        selection.begin(frozenScreen: frozenScreen, windows: windows) { [weak self] result in
            guard let self else { return }

            switch result {
            case .area(let rect):
                Task {
                    await self.perform(on: screen) {
                        guard let cropped = frozenScreen.cropped(to: rect) else { throw CaptureError.cropFailed }
                        return cropped
                    }
                }
            case .window(let windowID):
                // Captured live rather than cropped, so parts hidden behind other windows are included.
                Task {
                    await self.perform(on: screen) { try await self.captureService.captureWindow(windowID) }
                }
            case nil:
                endCapture()
            }
        }
    }

    /// Runs `capture` and opens the result in an editor on `screen`.
    private func perform(on screen: NSScreen, _ capture: () async throws -> Screenshot) async {
        do {
            let screenshot = try await capture()
            logger.info("Captured \(screenshot.image.width)×\(screenshot.image.height) px")
            endCapture()
            openEditor(for: screenshot, on: screen)
        } catch {
            fail(with: error)
        }
    }

    private func fail(with error: Error) {
        logger.error("Capture failed: \(error.localizedDescription)")
        endCapture()
        presentError(error)
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
