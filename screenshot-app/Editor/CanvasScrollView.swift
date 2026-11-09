import AppKit
import SwiftUI

/// A mouse drag on the canvas, in canvas coordinates (points, top-left origin).
enum CanvasDrag {
    /// `clickCount` is 2 for the second press of a double-click.
    case began(location: CGPoint, clickCount: Int)
    case changed(start: CGPoint, location: CGPoint, isConstrained: Bool)
    case ended
}

/// Asks the canvas to show its inline text field. A different `id` means a new,
/// empty field, even if the previous one was never seen removed.
struct CanvasTextFieldRequest {
    let id: UUID
    /// Top-left of the text, in canvas space.
    let origin: CGPoint
    /// Text the field starts with.
    let text: String
    let fontSize: CGFloat
}

/// An area of the canvas (in canvas space) that shows its own cursor, such as a resize handle.
struct CanvasCursorRect: Equatable {
    let rect: CGRect
    let cursor: NSCursor
}

/// Hosts SwiftUI content in an `NSScrollView` to get native zoom and pan:
/// pinch to zoom, two-finger scroll to pan, content centered when smaller than the view.
///
/// Mouse drags are handled by an AppKit view on top of the content rather than a
/// SwiftUI gesture: SwiftUI reports wrong locations inside a magnified scroll view,
/// while AppKit's coordinate conversion accounts for the magnification.
struct CanvasScrollView<Content: View>: NSViewRepresentable {
    let canvasSize: CGSize
    @Binding var zoom: CGFloat
    let zoomToFitRequest: Int
    /// Cursor over the canvas while a tool is active; `nil` lets the mouse pass through.
    let cursor: NSCursor?
    /// Areas that override `cursor`, e.g. resize handles.
    let cursorRects: [CanvasCursorRect]
    let onDrag: (CanvasDrag) -> Void
    /// The text field to show, or `nil` when not editing text.
    let textField: CanvasTextFieldRequest?
    let textColor: NSColor
    /// Called with the typed text when text editing ends.
    let onTextCommit: (String) -> Void
    @ViewBuilder let content: Content

    func makeCoordinator() -> Coordinator {
        Coordinator(zoom: $zoom, zoomToFitRequest: zoomToFitRequest)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.contentView = CenteringClipView()
        scrollView.drawsBackground = false
        scrollView.hasHorizontalScroller = true
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.allowsMagnification = true
        scrollView.minMagnification = EditorModel.zoomRange.lowerBound
        scrollView.maxMagnification = EditorModel.zoomRange.upperBound

        let documentView = FlippedView(frame: CGRect(origin: .zero, size: canvasSize))

        let hostingView = NSHostingView(rootView: content)
        // Size is driven by `canvasSize`, not by SwiftUI layout.
        hostingView.sizingOptions = []
        hostingView.frame = documentView.bounds
        hostingView.autoresizingMask = [.width, .height]
        documentView.addSubview(hostingView)

        let inputView = CanvasInputView(frame: documentView.bounds)
        inputView.autoresizingMask = [.width, .height]
        documentView.addSubview(inputView)

        scrollView.documentView = documentView

        context.coordinator.hostingView = hostingView
        context.coordinator.inputView = inputView
        context.coordinator.attach(to: scrollView)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        let coordinator = context.coordinator
        coordinator.zoom = $zoom

        coordinator.hostingView?.rootView = content
        coordinator.inputView?.cursor = cursor
        coordinator.inputView?.cursorRects = cursorRects
        coordinator.inputView?.onDrag = onDrag
        coordinator.onTextCommit = onTextCommit

        if let documentView = scrollView.documentView {
            if documentView.frame.size != canvasSize {
                documentView.setFrameSize(canvasSize)
            }
            coordinator.updateTextField(textField, color: textColor, in: documentView)
        }

        if zoomToFitRequest != coordinator.zoomToFitRequest {
            coordinator.zoomToFitRequest = zoomToFitRequest
            coordinator.zoomToFit(allowUpscaling: true)
        } else if abs(scrollView.magnification - zoom) > 0.001 {
            coordinator.setMagnification(zoom)
        }
    }

    static func dismantleNSView(_ scrollView: NSScrollView, coordinator: Coordinator) {
        coordinator.detach()
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var zoom: Binding<CGFloat>
        var zoomToFitRequest: Int
        var hostingView: NSHostingView<Content>?
        var inputView: CanvasInputView?
        var onTextCommit: ((String) -> Void)?
        private weak var scrollView: NSScrollView?
        private var magnifyObserver: NSObjectProtocol?
        private var textField: NSTextField?
        private var textFieldID: UUID?

        init(zoom: Binding<CGFloat>, zoomToFitRequest: Int) {
            self.zoom = zoom
            self.zoomToFitRequest = zoomToFitRequest
        }

        func attach(to scrollView: NSScrollView) {
            self.scrollView = scrollView

            // Keep the model in sync after pinch-zooming.
            magnifyObserver = NotificationCenter.default.addObserver(
                forName: NSScrollView.didEndLiveMagnifyNotification,
                object: scrollView,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.publishMagnification() }
            }

            // Fit large screenshots once the scroll view has its final size.
            Task { [weak self] in self?.zoomToFit(allowUpscaling: false) }
        }

        func detach() {
            if let magnifyObserver {
                NotificationCenter.default.removeObserver(magnifyObserver)
                self.magnifyObserver = nil
            }
            inputView?.onDrag = nil
            removeTextField()
            onTextCommit = nil
        }

        // MARK: Text editing

        /// Shows, replaces or removes the inline text field to match the model.
        ///
        /// Clicking elsewhere commits the current text and starts a new session in the
        /// same event, so the request can go straight from one id to the next without
        /// passing through `nil`; a new id must therefore always get a fresh field.
        func updateTextField(_ request: CanvasTextFieldRequest?, color: NSColor, in documentView: NSView) {
            guard let request else {
                removeTextField()
                return
            }

            if request.id != textFieldID {
                removeTextField()
                textField = makeTextField(text: request.text, fontSize: request.fontSize, in: documentView)
                textFieldID = request.id
            }

            guard let field = textField else { return }
            field.textColor = color
            // Compensate for the field's internal inset so typed text lines up with the rendered annotation.
            field.setFrameOrigin(CGPoint(x: request.origin.x - 2, y: request.origin.y))
        }

        private func removeTextField() {
            textField?.delegate = nil
            textField?.removeFromSuperview()
            textField = nil
            textFieldID = nil
        }

        private func makeTextField(text: String, fontSize: CGFloat, in documentView: NSView) -> NSTextField {
            let field = NSTextField(string: text)
            field.font = .systemFont(ofSize: fontSize, weight: .bold)
            field.isBordered = false
            field.drawsBackground = false
            field.focusRingType = .none
            field.placeholderString = "Text"
            field.cell?.wraps = false
            field.cell?.isScrollable = true
            field.delegate = self
            field.sizeToFit()
            field.setFrameSize(CGSize(width: max(field.frame.width + 8, 80), height: field.frame.height))

            // Added last so it sits above the input view and receives clicks.
            documentView.addSubview(field)
            documentView.window?.makeFirstResponder(field)
            // Becoming first responder selects everything; put the caret at the end instead.
            field.currentEditor()?.selectedRange = NSRange(location: (text as NSString).length, length: 0)
            return field
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            let height = field.frame.height
            field.sizeToFit()
            field.setFrameSize(CGSize(width: max(field.frame.width + 8, 80), height: height))
        }

        /// Enter and Esc finish editing; ending editing (by any means) commits the text.
        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            guard selector == #selector(NSResponder.insertNewline(_:)) || selector == #selector(NSResponder.cancelOperation(_:)) else {
                return false
            }
            control.window?.makeFirstResponder(nil)
            return true
        }

        func controlTextDidEndEditing(_ notification: Notification) {
            guard let field = notification.object as? NSTextField, field === textField else { return }
            // Detach first so a second end-editing notification can't commit twice.
            field.delegate = nil
            onTextCommit?(field.stringValue)
        }

        func setMagnification(_ value: CGFloat) {
            guard let scrollView else { return }
            let visible = scrollView.contentView.bounds
            scrollView.setMagnification(value, centeredAt: CGPoint(x: visible.midX, y: visible.midY))
        }

        func zoomToFit(allowUpscaling: Bool) {
            guard let scrollView, let documentView = scrollView.documentView else { return }
            let available = scrollView.contentSize
            let content = documentView.frame.size
            guard content.width > 0, content.height > 0, available.width > 0, available.height > 0 else { return }

            var fit = min(available.width / content.width, available.height / content.height)
            if !allowUpscaling { fit = min(fit, 1) }
            setMagnification(fit)
            publishMagnification()
        }

        private func publishMagnification() {
            guard let magnification = scrollView?.magnification else { return }
            // Defer: this can run during a SwiftUI view update.
            Task { [zoom] in zoom.wrappedValue = magnification }
        }
    }
}

/// Transparent view over the canvas that turns mouse drags into `CanvasDrag` events.
/// With no cursor set (no active tool) it ignores the mouse entirely, letting events pass through.
///
/// Cursors are set from mouse tracking rather than cursor rects, because cursor rects
/// may not overlap and handle areas sit on top of the canvas-wide cursor.
final class CanvasInputView: NSView {
    var cursor: NSCursor? {
        didSet {
            guard cursor !== oldValue else { return }
            updateCursor()
        }
    }
    var cursorRects: [CanvasCursorRect] = [] {
        didSet {
            guard cursorRects != oldValue else { return }
            updateCursor()
        }
    }
    var onDrag: ((CanvasDrag) -> Void)?

    private var dragStart: CGPoint?

    override var isFlipped: Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        cursor != nil ? super.hitTest(point) : nil
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .cursorUpdate, .activeAlways, .inVisibleRect], owner: self))
    }

    override func cursorUpdate(with event: NSEvent) {
        updateCursor(at: location(of: event))
    }

    override func mouseMoved(with event: NSEvent) {
        updateCursor(at: location(of: event))
    }

    /// Sets the cursor for the pointer's current position. Keeps the cursor while dragging,
    /// so a resize cursor stays put even when the pointer runs ahead of the handle.
    private func updateCursor(at point: CGPoint? = nil) {
        guard dragStart == nil, let window else { return }
        let point = point ?? convert(window.mouseLocationOutsideOfEventStream, from: nil)
        // The inline text field sits on top and shows its own I-beam.
        let overTextField = superview?.subviews.contains { $0 is NSTextField && $0.frame.contains(point) } ?? false
        guard bounds.contains(point), !overTextField, let cursor else { return }
        (cursorRects.last { $0.rect.contains(point) }?.cursor ?? cursor).set()
    }

    override func mouseDown(with event: NSEvent) {
        // A click outside the text being typed only finishes (commits) it; the next click starts something new.
        if let editor = window?.firstResponder as? NSTextView, editor.isFieldEditor {
            window?.makeFirstResponder(nil)
            return
        }

        let location = location(of: event)
        dragStart = location
        onDrag?(.began(location: location, clickCount: event.clickCount))
    }

    override func mouseDragged(with event: NSEvent) {
        guard let dragStart else { return }
        onDrag?(.changed(start: dragStart, location: location(of: event), isConstrained: event.modifierFlags.contains(.shift)))
    }

    override func mouseUp(with event: NSEvent) {
        guard dragStart != nil else { return }
        dragStart = nil
        onDrag?(.ended)
        updateCursor()
    }

    /// Event location in this view's coordinates, i.e. canvas points regardless of magnification.
    private func location(of event: NSEvent) -> CGPoint {
        convert(event.locationInWindow, from: nil)
    }
}

/// Document view with a top-left origin, matching SwiftUI's coordinate space.
private final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

/// Clip view that keeps the document centered when it's smaller than the visible area.
private final class CenteringClipView: NSClipView {
    override func constrainBoundsRect(_ proposedBounds: NSRect) -> NSRect {
        var rect = super.constrainBoundsRect(proposedBounds)
        guard let documentFrame = documentView?.frame else { return rect }

        if rect.width > documentFrame.width {
            rect.origin.x = (documentFrame.width - rect.width) / 2
        }
        if rect.height > documentFrame.height {
            rect.origin.y = (documentFrame.height - rect.height) / 2
        }
        return rect
    }
}
