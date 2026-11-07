import AppKit
import Carbon.HIToolbox
import SwiftUI

/// Shows a transparent full-screen window on one screen and reports the area or window the user picks.
///
/// Call `close()` when done; it tears down the window, hosting view and key monitor.
final class SelectionOverlayController {
    let screen: NSScreen

    private let model = SelectionModel()
    private var window: NSWindow?
    private var keyMonitor: Any?
    private var completion: ((SelectionResult?) -> Void)?

    init(screen: NSScreen) {
        self.screen = screen
    }

    /// Shows the overlay. `completion` is called once with the user's pick, or `nil` if they cancelled.
    ///
    /// - Parameters:
    ///   - frozenScreen: Screenshot of this screen, shown as the overlay's background.
    ///   - windows: Windows that can be picked by clicking, frontmost first.
    func begin(frozenScreen: Screenshot, windows: [SelectableWindow], completion: @escaping (SelectionResult?) -> Void) {
        self.completion = completion
        model.windows = windows
        model.screenSize = screen.frame.size
        // Highlight the window under the pointer right away, before the mouse moves.
        let mouse = NSEvent.mouseLocation
        model.hoverLocation = CGPoint(x: mouse.x - screen.frame.minX, y: screen.frame.maxY - mouse.y)

        let window = OverlayWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.level = .screenSaver
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        window.contentView = OverlayHostingView(rootView: SelectionView(model: model, frozenScreen: frozenScreen) { [weak self] result in
            self?.finish(with: result)
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

    private func finish(with result: SelectionResult?) {
        guard let completion else { return }
        self.completion = nil

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
