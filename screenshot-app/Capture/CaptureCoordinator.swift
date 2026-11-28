import AppKit
import OSLog

/// Entry point for capture requests coming from the menu bar or global hot keys.
///
/// Gates requests behind the permission check, drives the selection overlay and
/// opens each result in its own editor window. Captures are recorded in `history`
/// and can be reopened from it. Existing images (files, clipboard) take the same path
/// once loaded, so they behave exactly like captures.
final class CaptureCoordinator {
    private let permissions: PermissionService
    private let history: CaptureHistory
    private let captureService = CaptureService()
    private let importService = ImageImportService()
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "screenshot-app", category: "Capture")

    private var selection: SelectionOverlayController?
    /// Open editors by history entry, kept alive until their window closes.
    private var editors: [UUID: EditorWindowController] = [:]
    /// Guards against overlapping captures (e.g. a hot key pressed during selection).
    private var isBusy = false

    init(permissions: PermissionService, history: CaptureHistory) {
        self.permissions = permissions
        self.history = history
    }

    /// Lets the user pick an area or a window on any screen.
    func captureArea() {
        let screens = NSScreen.screens
        guard !isBusy, permissions.ensureScreenRecordingAccess(), !screens.isEmpty else { return }
        isBusy = true

        // Snapshot the window lists before the overlays appear, so they aren't in the lists.
        let windows = screens.map { captureService.selectableWindows(on: $0) }
        Task {
            do {
                // Freeze every screen first: the overlays show these images and areas are cut out of them.
                // Start all captures before awaiting any, so they run side by side.
                let captures = screens.map { screen in
                    Task { try await self.captureService.captureScreen(screen) }
                }
                var targets: [SelectionScreen] = []
                for (index, screen) in screens.enumerated() {
                    targets.append(SelectionScreen(screen: screen, frozenScreen: try await captures[index].value, windows: windows[index]))
                }
                beginSelection(on: targets)
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

    /// Opens a recent capture in an editor, or brings its editor forward if it's already open.
    func reopen(_ id: UUID) {
        if let editor = editors[id] {
            editor.show(on: nil)
            return
        }
        guard let entry = history.entry(id: id), let screenshot = entry.screenshot else { return }
        openEditor(for: entry, screenshot: screenshot, on: NSScreen.underMouse)
    }

    // MARK: - Opening images

    /// Lets the user pick image files; each opens in its own editor.
    func openImageFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = ImageImportService.supportedTypes
        panel.allowsMultipleSelection = true
        // A menu bar app isn't active by default, and the panel would open behind other windows.
        NSApp.activate()
        guard panel.runModal() == .OK else { return }
        openImages(at: panel.urls)
    }

    /// Opens image files, e.g. dropped on the menu bar icon.
    func openImages(at urls: [URL]) {
        for url in urls {
            openImage { try self.importService.screenshot(contentsOf: url) }
        }
    }

    func openImageFromClipboard() {
        openImage { try self.importService.screenshot(from: .general) }
    }

    /// Opens an image in an editor and records it in Recent Captures, exactly like a capture.
    func open(_ screenshot: Screenshot, on screen: NSScreen? = NSScreen.underMouse) {
        openEditor(for: history.add(screenshot), screenshot: screenshot, on: screen)
    }

    // MARK: - Private

    private func openImage(_ load: () throws -> Screenshot) {
        guard !isBusy else { return }
        do {
            let screenshot = try load()
            logger.info("Opened \(screenshot.image.width)×\(screenshot.image.height) px at \(screenshot.scale)x")
            open(screenshot)
        } catch {
            logger.error("Opening an image failed: \(error.localizedDescription)")
            presentError(error, title: "Couldn’t open the image")
        }
    }

    private func beginSelection(on screens: [SelectionScreen]) {
        let selection = SelectionOverlayController()
        self.selection = selection
        selection.begin(on: screens) { [weak self] pick in
            guard let self else { return }
            guard let (target, result) = pick else {
                endCapture()
                return
            }

            switch result {
            case .area(let rect):
                Task {
                    await self.perform(on: target.screen) {
                        guard let cropped = target.frozenScreen.cropped(to: rect) else { throw CaptureError.cropFailed }
                        return cropped
                    }
                }
            case .window(let windowID):
                // Captured live rather than cropped, so parts hidden behind other windows are included.
                Task {
                    await self.perform(on: target.screen) { try await self.captureService.captureWindow(windowID) }
                }
            }
        }
    }

    /// Runs `capture` and opens the result in an editor on `screen`.
    private func perform(on screen: NSScreen, _ capture: () async throws -> Screenshot) async {
        do {
            let screenshot = try await capture()
            logger.info("Captured \(screenshot.image.width)×\(screenshot.image.height) px")
            endCapture()
            open(screenshot, on: screen)
        } catch {
            fail(with: error)
        }
    }

    private func fail(with error: Error) {
        logger.error("Capture failed: \(error.localizedDescription)")
        endCapture()
        presentError(error, title: "Screenshot Failed")
    }

    private func endCapture() {
        selection?.close()
        selection = nil
        isBusy = false
    }

    private func openEditor(for entry: CaptureHistoryEntry, screenshot: Screenshot, on screen: NSScreen?) {
        let editor = EditorWindowController(screenshot: screenshot, document: entry.document)
        let id = entry.id
        editor.onClose = { [weak self, weak entry] document in
            if let document {
                entry?.document = document
            }
            self?.editors[id] = nil
        }
        editors[id] = editor
        editor.show(on: screen)
    }

    private func presentError(_ error: Error, title: String) {
        let alert = NSAlert(error: error)
        alert.messageText = title
        alert.informativeText = error.localizedDescription
        NSApp.activate()
        alert.runModal()
    }
}
