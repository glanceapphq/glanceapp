import AppKit
import SwiftUI

/// A mouse drag on the canvas, in canvas coordinates (points, top-left origin).
enum CanvasDrag {
    case changed(start: CGPoint, location: CGPoint, isConstrained: Bool)
    case ended
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
    /// Whether drags on the canvas are captured (and the cursor becomes a crosshair).
    let isDrawingEnabled: Bool
    let onDrag: (CanvasDrag) -> Void
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
        coordinator.inputView?.isDrawingEnabled = isDrawingEnabled
        coordinator.inputView?.onDrag = onDrag

        if let documentView = scrollView.documentView, documentView.frame.size != canvasSize {
            documentView.setFrameSize(canvasSize)
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

    final class Coordinator {
        var zoom: Binding<CGFloat>
        var zoomToFitRequest: Int
        var hostingView: NSHostingView<Content>?
        var inputView: CanvasInputView?
        private weak var scrollView: NSScrollView?
        private var magnifyObserver: NSObjectProtocol?

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
/// When drawing is disabled it ignores the mouse entirely, letting events pass through.
final class CanvasInputView: NSView {
    var isDrawingEnabled = false {
        didSet {
            guard isDrawingEnabled != oldValue else { return }
            window?.invalidateCursorRects(for: self)
        }
    }
    var onDrag: ((CanvasDrag) -> Void)?

    private var dragStart: CGPoint?

    override var isFlipped: Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        isDrawingEnabled ? super.hitTest(point) : nil
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func resetCursorRects() {
        if isDrawingEnabled {
            addCursorRect(bounds, cursor: .crosshair)
        }
    }

    override func mouseDown(with event: NSEvent) {
        dragStart = location(of: event)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let dragStart else { return }
        onDrag?(.changed(start: dragStart, location: location(of: event), isConstrained: event.modifierFlags.contains(.shift)))
    }

    override func mouseUp(with event: NSEvent) {
        guard dragStart != nil else { return }
        dragStart = nil
        onDrag?(.ended)
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
