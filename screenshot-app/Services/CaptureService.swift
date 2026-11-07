import AppKit
import ScreenCaptureKit

/// A captured image together with the display scale it was taken at.
struct Screenshot {
    let image: CGImage
    /// Pixels per point of the source display (e.g. `2` on Retina).
    let scale: CGFloat

    /// Image size in points.
    var size: CGSize {
        CGSize(width: CGFloat(image.width) / scale, height: CGFloat(image.height) / scale)
    }
}

enum CaptureError: LocalizedError {
    case displayNotFound

    var errorDescription: String? {
        switch self {
        case .displayNotFound: "Could not find the display to capture."
        }
    }
}

/// Takes still screenshots using ScreenCaptureKit.
final class CaptureService {
    /// Captures the whole `screen`.
    func captureScreen(_ screen: NSScreen) async throws -> Screenshot {
        try await capture(screen: screen, rect: nil, excludingWindowIDs: [])
    }

    /// Captures `rect` on `screen`.
    ///
    /// - Parameters:
    ///   - rect: Area in the screen's local coordinate space (points, top-left origin).
    ///   - excludedWindowIDs: Windows to leave out of the image, such as the selection overlay.
    func captureRect(_ rect: CGRect, on screen: NSScreen, excludingWindowIDs excludedWindowIDs: Set<CGWindowID>) async throws -> Screenshot {
        try await capture(screen: screen, rect: rect, excludingWindowIDs: excludedWindowIDs)
    }

    // MARK: - Private

    private func capture(screen: NSScreen, rect: CGRect?, excludingWindowIDs excludedWindowIDs: Set<CGWindowID>) async throws -> Screenshot {
        guard let displayID = screen.displayID else { throw CaptureError.displayNotFound }

        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first(where: { $0.displayID == displayID }) else {
            throw CaptureError.displayNotFound
        }

        let excludedWindows = content.windows.filter { excludedWindowIDs.contains($0.windowID) }
        let filter = SCContentFilter(display: display, excludingWindows: excludedWindows)
        let scale = CGFloat(filter.pointPixelScale)
        let sourceRect = rect ?? CGRect(origin: .zero, size: filter.contentRect.size)

        let configuration = SCStreamConfiguration()
        configuration.sourceRect = sourceRect
        configuration.width = Int((sourceRect.width * scale).rounded())
        configuration.height = Int((sourceRect.height * scale).rounded())
        configuration.captureResolution = .best
        configuration.showsCursor = false

        let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
        return Screenshot(image: image, scale: scale)
    }
}

extension NSScreen {
    /// Core Graphics identifier of the display backing this screen.
    var displayID: CGDirectDisplayID? {
        deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }

    /// The screen currently under the mouse pointer, falling back to the main screen.
    static var underMouse: NSScreen? {
        let location = NSEvent.mouseLocation
        return screens.first { NSMouseInRect(location, $0.frame, false) } ?? main
    }
}
