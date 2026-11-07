import AppKit
import OSLog

/// Entry point for capture requests coming from the menu bar or global hot keys.
///
/// Gates requests behind the permission check, drives the selection overlay and
/// hands the result off. Until the editor exists (Step 4), results go straight to the clipboard.
final class CaptureCoordinator {
    private let permissions: PermissionService
    private let captureService = CaptureService()
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "screenshot-app", category: "Capture")

    private var selection: SelectionOverlayController?
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
                await self.perform { try await self.captureService.captureRect(rect, on: screen, excludingWindowIDs: excluded) }
            }
        }
    }

    func captureFullScreen() {
        guard !isBusy, permissions.ensureScreenRecordingAccess(), let screen = NSScreen.underMouse else { return }
        isBusy = true

        Task {
            await perform { try await self.captureService.captureScreen(screen) }
        }
    }

    // MARK: - Private

    private func perform(_ capture: () async throws -> Screenshot) async {
        defer { endCapture() }
        do {
            let screenshot = try await capture()
            logger.info("Captured \(screenshot.image.width)×\(screenshot.image.height) px")
            deliver(screenshot)
        } catch {
            logger.error("Capture failed: \(error.localizedDescription)")
            presentError(error)
        }
    }

    private func endCapture() {
        selection?.close()
        selection = nil
        isBusy = false
    }

    /// Temporary hand-off until the editor exists: copies the image to the clipboard as PNG.
    private func deliver(_ screenshot: Screenshot) {
        let item = NSPasteboardItem()
        let bitmap = NSBitmapImageRep(cgImage: screenshot.image)
        bitmap.size = screenshot.size
        if let png = bitmap.representation(using: .png, properties: [:]) {
            item.setData(png, forType: .png)
        }
        if let tiff = bitmap.tiffRepresentation {
            item.setData(tiff, forType: .tiff)
        }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([item])
    }

    private func presentError(_ error: Error) {
        let alert = NSAlert(error: error)
        alert.messageText = "Screenshot Failed"
        alert.informativeText = error.localizedDescription
        NSApp.activate()
        alert.runModal()
    }
}
