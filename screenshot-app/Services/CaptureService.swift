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

    /// The part of the image inside `rect` (points, top-left origin), at the same scale.
    func cropped(to rect: CGRect) -> Screenshot? {
        let pixelRect = CGRect(x: rect.minX * scale, y: rect.minY * scale, width: rect.width * scale, height: rect.height * scale).integral
        return image.cropping(to: pixelRect).map { Screenshot(image: $0, scale: scale) }
    }
}

/// An on-screen window the user can pick in the selection overlay.
struct SelectableWindow {
    let id: CGWindowID
    /// Window frame in the screen's local coordinate space (points, top-left origin).
    let frame: CGRect
}

enum CaptureError: LocalizedError {
    case displayNotFound
    case windowNotFound
    case cropFailed

    var errorDescription: String? {
        switch self {
        case .displayNotFound: "Could not find the display to capture."
        case .windowNotFound: "The window is no longer available."
        case .cropFailed: "Could not cut out the selected area."
        }
    }
}

/// Takes still screenshots using ScreenCaptureKit.
final class CaptureService {
    /// Captures the whole `screen` at full resolution.
    ///
    /// Area captures crop this image too: the selection overlay shows it "frozen"
    /// and cuts the selected area out of it, so no second capture is needed.
    func captureScreen(_ screen: NSScreen) async throws -> Screenshot {
        guard let displayID = screen.displayID else { throw CaptureError.displayNotFound }

        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first(where: { $0.displayID == displayID }) else {
            throw CaptureError.displayNotFound
        }

        let filter = SCContentFilter(display: display, excludingWindows: [])
        let scale = CGFloat(filter.pointPixelScale)

        let configuration = SCStreamConfiguration()
        configuration.width = Int((filter.contentRect.width * scale).rounded())
        configuration.height = Int((filter.contentRect.height * scale).rounded())
        configuration.captureResolution = .best
        configuration.showsCursor = false

        let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
        return Screenshot(image: image, scale: scale)
    }

    /// Captures a single window on its own: no other windows or desktop behind it,
    /// transparent rounded corners and no system shadow (the editor adds its own).
    func captureWindow(_ windowID: CGWindowID) async throws -> Screenshot {
        let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
        guard let window = content.windows.first(where: { $0.windowID == windowID }) else {
            throw CaptureError.windowNotFound
        }

        let filter = SCContentFilter(desktopIndependentWindow: window)
        let scale = CGFloat(filter.pointPixelScale)

        let configuration = SCStreamConfiguration()
        configuration.width = Int((filter.contentRect.width * scale).rounded())
        configuration.height = Int((filter.contentRect.height * scale).rounded())
        configuration.captureResolution = .best
        configuration.showsCursor = false
        configuration.ignoreShadowsSingleWindow = true

        let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
        return Screenshot(image: image, scale: scale)
    }

    /// Regular app windows visible on `screen`, frontmost first.
    ///
    /// Uses `CGWindowListCopyWindowInfo` because, unlike `SCShareableContent`, it
    /// guarantees front-to-back order, which hit-testing overlapping windows needs.
    func selectableWindows(on screen: NSScreen) -> [SelectableWindow] {
        guard let displayID = screen.displayID,
              let entries = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]
        else { return [] }

        // Window bounds and display bounds share the global top-left-origin coordinate space.
        let displayBounds = CGDisplayBounds(displayID)
        let ownPID = ProcessInfo.processInfo.processIdentifier

        return entries.compactMap { entry in
            guard (entry[kCGWindowLayer as String] as? Int) == 0,  // Normal windows: no menu bar, Dock, etc.
                  (entry[kCGWindowOwnerPID as String] as? pid_t) != ownPID,
                  (entry[kCGWindowAlpha as String] as? Double ?? 1) > 0,
                  let id = entry[kCGWindowNumber as String] as? CGWindowID,
                  let boundsDictionary = entry[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDictionary),
                  bounds.width >= 40, bounds.height >= 40,
                  bounds.intersects(displayBounds)
            else { return nil }

            return SelectableWindow(id: id, frame: bounds.offsetBy(dx: -displayBounds.minX, dy: -displayBounds.minY))
        }
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
