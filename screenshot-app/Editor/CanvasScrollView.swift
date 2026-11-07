import AppKit
import SwiftUI

/// Hosts SwiftUI content in an `NSScrollView` to get native zoom and pan:
/// pinch to zoom, two-finger scroll to pan, content centered when smaller than the view.
struct CanvasScrollView<Content: View>: NSViewRepresentable {
    let canvasSize: CGSize
    @Binding var zoom: CGFloat
    let zoomToFitRequest: Int
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

        let documentView = NSHostingView(rootView: content)
        // Size is driven by `canvasSize`, not by SwiftUI layout.
        documentView.sizingOptions = []
        documentView.frame = CGRect(origin: .zero, size: canvasSize)
        scrollView.documentView = documentView

        context.coordinator.attach(to: scrollView)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        let coordinator = context.coordinator
        coordinator.zoom = $zoom

        if let documentView = scrollView.documentView as? NSHostingView<Content> {
            documentView.rootView = content
            if documentView.frame.size != canvasSize {
                documentView.setFrameSize(canvasSize)
            }
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
