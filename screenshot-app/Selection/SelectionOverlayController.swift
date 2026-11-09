import AppKit
import Carbon.HIToolbox
import SwiftUI

/// One screen taking part in a selection.
struct SelectionScreen {
    let screen: NSScreen
    /// Screenshot of the screen, shown as its overlay's background.
    let frozenScreen: Screenshot
    /// Windows on this screen that can be picked by clicking, frontmost first.
    let windows: [SelectableWindow]
}

/// Covers every screen with a transparent overlay and reports the area or window the
/// user picks on one of them. A selection stays within the screen it started on.
///
/// Call `close()` when done; it tears down the windows, hosting views and event monitors.
final class SelectionOverlayController {
    private var overlays: [Overlay] = []
    private var monitors: [Any] = []
    private var completion: (((SelectionScreen, SelectionResult)?) -> Void)?

    /// Shows the overlays. `completion` is called once with the screen and the user's pick,
    /// or `nil` if they cancelled.
    func begin(on screens: [SelectionScreen], completion: @escaping ((SelectionScreen, SelectionResult)?) -> Void) {
        self.completion = completion
        overlays = screens.map { target in
            Overlay(target: target) { [weak self] result in
                self?.finish(on: target, with: result)
            }
        }
        // Highlight the window under the pointer right away, before the mouse moves.
        updatePointer()

        monitors.append(NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == UInt16(kVK_Escape) else { return event }
            self?.finish(on: nil, with: nil)
            return nil
        } as Any)
        // SwiftUI only tracks hover reliably in the key window; follow the pointer across all screens here.
        monitors.append(NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) { [weak self] event in
            self?.updatePointer()
            return event
        } as Any)

        NSApp.activate()
        for overlay in overlays {
            overlay.window.orderFront(nil)
        }
        let underMouse = overlays.first { NSMouseInRect(NSEvent.mouseLocation, $0.target.screen.frame, false) } ?? overlays.first
        underMouse?.window.makeKey()
    }

    func close() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors.removeAll()
        completion = nil
        overlays.forEach { $0.close() }
        overlays.removeAll()
    }

    /// Converts a global AppKit point (bottom-left origin) to the local, top-left-origin
    /// coordinates of the screen with `frame`, or `nil` if the point is on another screen.
    static func localPoint(_ point: CGPoint, inScreenWithFrame frame: CGRect) -> CGPoint? {
        guard NSMouseInRect(point, frame, false) else { return nil }
        return CGPoint(x: point.x - frame.minX, y: frame.maxY - point.y)
    }

    // MARK: - Private

    /// Shows the crosshair and loupe only on the screen under the pointer, and nowhere
    /// else while a selection is being dragged out.
    private func updatePointer() {
        let mouse = NSEvent.mouseLocation
        let isDragging = overlays.contains { $0.model.isDragging }

        for overlay in overlays where !overlay.model.isDragging {
            overlay.model.hoverLocation = isDragging ? nil : Self.localPoint(mouse, inScreenWithFrame: overlay.target.screen.frame)
        }
    }

    private func finish(on target: SelectionScreen?, with result: SelectionResult?) {
        guard let completion else { return }
        self.completion = nil

        let pick = target.flatMap { target in result.map { (target, $0) } }
        // Defer so the hosting view isn't torn down from inside its own gesture callback.
        Task { completion(pick) }
    }
}

/// The overlay window on one screen.
private final class Overlay {
    let target: SelectionScreen
    let model = SelectionModel()
    let window: NSWindow

    init(target: SelectionScreen, onComplete: @escaping (SelectionResult?) -> Void) {
        self.target = target
        let frame = target.screen.frame
        model.windows = target.windows
        model.screenSize = frame.size

        window = OverlayWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.level = .screenSaver
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        window.acceptsMouseMovedEvents = true
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        window.contentView = OverlayHostingView(rootView: SelectionView(model: model, frozenScreen: target.frozenScreen, onComplete: onComplete))
        window.setFrame(frame, display: false)
    }

    func close() {
        window.orderOut(nil)
        window.contentView = nil
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
