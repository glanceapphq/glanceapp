import AppKit

/// Accepts image files dragged onto the menu bar icon.
///
/// `NSStatusItem` creates its button itself, so it can't be swapped for a subclass that
/// handles drops. Instead the button's window is registered for file drags: `NSWindow`
/// forwards dragging-destination calls to its delegate, which is this object.
final class StatusItemDropTarget: NSObject, NSWindowDelegate, NSDraggingDestination {
    private weak var button: NSStatusBarButton?
    private let onDrop: ([URL]) -> Void

    init(button: NSStatusBarButton, onDrop: @escaping ([URL]) -> Void) {
        self.button = button
        self.onDrop = onDrop
        super.init()

        button.window?.registerForDraggedTypes([.fileURL])
        button.window?.delegate = self
    }

    func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        // Refuse drags without images, so the pointer shows they can't be dropped here.
        guard !ImageImportService.imageFileURLs(on: sender.draggingPasteboard).isEmpty else { return [] }
        button?.highlight(true)
        return .copy
    }

    func draggingExited(_ sender: NSDraggingInfo?) {
        button?.highlight(false)
    }

    func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        button?.highlight(false)
        let urls = ImageImportService.imageFileURLs(on: sender.draggingPasteboard)
        guard !urls.isEmpty else { return false }
        // Let the drag finish before opening windows or showing an error alert.
        Task { self.onDrop(urls) }
        return true
    }
}
