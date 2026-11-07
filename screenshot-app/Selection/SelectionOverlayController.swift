import AppKit
import Carbon.HIToolbox
import SwiftUI

/// Shows a transparent full-screen window on one screen and reports the area the user selects.
///
/// Call `close()` when done; it tears down the window, hosting view and key monitor.
final class SelectionOverlayController {
    let screen: NSScreen

    private let model = SelectionModel()
    private var window: NSWindow?
    private var keyMonitor: Any?
    private var completion: ((CGRect?) -> Void)?

    init(screen: NSScreen) {
        self.screen = screen
    }

    /// Window server ID of the overlay, so it can be excluded from the capture.
    var windowID: CGWindowID? {
        window.map { CGWindowID($0.windowNumber) }
    }

    /// Shows the overlay. `completion` is called once with the selected rect
    /// (screen-local points, top-left origin), or `nil` if the user cancelled.
    func begin(completion: @escaping (CGRect?) -> Void) {
        self.completion = completion

        let window = OverlayWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.level = .screenSaver
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        window.contentView = OverlayHostingView(rootView: SelectionView(model: model) { [weak self] rect in
            self?.finish(with: rect)
        })
        window.setFrame(screen.frame, display: false)
        self.window = window

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == UInt16(kVK_Escape) else { return event }
            self?.finish(with: nil)
            return nil
        }

        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    func close() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
        completion = nil
        window?.orderOut(nil)
        window?.contentView = nil
        window = nil
    }

    // MARK: - Private

    private func finish(with rect: CGRect?) {
        guard let completion else { return }
        self.completion = nil

        // A click or tiny drag counts as a cancel.
        let result = rect.flatMap { $0.width >= 4 && $0.height >= 4 ? $0 : nil }

        // Defer so the hosting view isn't torn down from inside its own gesture callback.
        Task { completion(result) }
    }
}

/// Lets the very first click start a selection even before the window becomes key.
private final class OverlayHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// Borderless windows can't become key by default; we need key status to receive Esc.
private final class OverlayWindow: NSWindow {
    override var canBecomeKey: Bool { true }
}
