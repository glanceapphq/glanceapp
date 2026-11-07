import AppKit
import SwiftUI

/// Presents an `EditorView` for one screenshot in a borderless, floating, translucent window.
///
/// The controller owns the window; when it closes, the window, hosting view and
/// model are released and `onClose` lets the owner drop its reference.
final class EditorWindowController: NSObject, NSWindowDelegate {
    var onClose: (() -> Void)?

    private let model: EditorModel
    private let renderService = RenderService()
    private let exportService = ExportService()
    private var window: NSWindow?

    init(screenshot: Screenshot) {
        self.model = EditorModel(screenshot: screenshot)
    }

    /// Shows the editor centered on `screen` (or the main screen).
    func show(on screen: NSScreen?) {
        let window = window ?? makeWindow(on: screen ?? NSScreen.main)
        self.window = window

        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        // The shadow follows the rounded content's alpha; recompute once it's drawn.
        window.invalidateShadow()
    }

    func close() {
        window?.close()
    }

    /// Copies the rendered composition to the clipboard and closes the editor.
    func copy() {
        export { image in exportService.copyToPasteboard(image) }
    }

    /// Saves the rendered composition as PNG and closes the editor.
    func save() {
        export { image in try exportService.save(image) }
    }

    func windowWillClose(_ notification: Notification) {
        window?.delegate = nil
        window?.contentView = nil
        window = nil
        onClose?()
        onClose = nil
    }

    // MARK: - Private

    /// Renders the composition and hands it to `deliver`. Closes on success; reports errors on the window.
    private func export(_ deliver: (RenderedImage) throws -> Void) {
        // End text editing first so text still being typed is committed and included.
        window?.makeFirstResponder(nil)
        do {
            try deliver(try renderService.render(model))
            close()
        } catch {
            presentError(error)
        }
    }

    private func presentError(_ error: Error) {
        let alert = NSAlert(error: error)
        alert.messageText = "Export Failed"
        alert.informativeText = error.localizedDescription
        if let window {
            alert.beginSheetModal(for: window)
        } else {
            alert.runModal()
        }
    }

    private func makeWindow(on screen: NSScreen?) -> NSWindow {
        let window = EditorWindow(
            contentRect: initialFrame(on: screen),
            styleMask: [.borderless, .resizable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = true
        window.minSize = CGSize(width: 860, height: 400)
        window.collectionBehavior = [.fullScreenAuxiliary]
        window.delegate = self
        window.contentView = makeContentView()
        return window
    }

    /// Translucent rounded background with the SwiftUI editor on top.
    private func makeContentView() -> NSView {
        let background = NSVisualEffectView()
        background.material = .underWindowBackground
        background.blendingMode = .behindWindow
        background.state = .active
        background.maskImage = .roundedRectMask(cornerRadius: EditorView.cornerRadius)

        let actions = EditorActions(
            close: { [weak self] in self?.close() },
            copy: { [weak self] in self?.copy() },
            save: { [weak self] in self?.save() }
        )
        let editor = NSHostingView(rootView: EditorView(model: model, actions: actions))
        editor.frame = background.bounds
        editor.autoresizingMask = [.width, .height]
        background.addSubview(editor)
        return background
    }

    /// Fits the composition at 100% when possible, capped to most of the screen.
    private func initialFrame(on screen: NSScreen?) -> CGRect {
        let visible = screen?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        let canvas = model.canvasSize
        let margin: CGFloat = 40

        let width = min(max(canvas.width + EditorView.inspectorWidth + margin, 900), visible.width * 0.85)
        let height = min(max(canvas.height + EditorView.toolbarHeight + margin, 480), visible.height * 0.85)

        return CGRect(
            x: visible.midX - width / 2,
            y: visible.midY - height / 2,
            width: width,
            height: height
        ).integral
    }
}

/// Borderless windows can't become key or main by default; the editor needs keyboard input.
private final class EditorWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

private extension NSImage {
    /// A stretchable rounded-rect mask, for `NSVisualEffectView.maskImage`.
    static func roundedRectMask(cornerRadius radius: CGFloat) -> NSImage {
        let edge = radius * 2 + 1
        let image = NSImage(size: CGSize(width: edge, height: edge), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }
}
