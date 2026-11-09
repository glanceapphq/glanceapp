import AppKit
import XCTest
@testable import Glance

/// Synthetic images for tests.
enum TestImage {
    /// An sRGB image `width`×`height` pixels, drawn by `draw` (Core Graphics coordinates, bottom-left origin).
    static func make(width: Int, height: Int, draw: (CGContext) -> Void = { _ in }) -> CGImage {
        let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        draw(context)
        return context.makeImage()!
    }

    /// RGBA of the pixel at (`x`, `y`), counted from the top-left.
    static func pixel(of image: CGImage, x: Int, y: Int) -> [UInt8] {
        let context = CGContext(
            data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        // Bitmap memory starts with the top row.
        let bytes = context.data!.assumingMemoryBound(to: UInt8.self)
        let index = (y * image.width + x) * 4
        return Array(UnsafeBufferPointer(start: bytes + index, count: 4))
    }

    static func decodePNG(_ data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }
}

extension CGContext {
    func fill(_ rect: CGRect, red: CGFloat, green: CGFloat, blue: CGFloat) {
        setFillColor(CGColor(srgbRed: red, green: green, blue: blue, alpha: 1))
        fill(rect)
    }
}

extension XCTestCase {
    /// A defaults suite removed when the test ends, so tests never touch the app's real settings
    /// (the tests run inside the app, under its bundle identifier).
    func makeIsolatedDefaults() -> UserDefaults {
        let name = "GlanceTests.\(UUID().uuidString)"
        addTeardownBlock { UserDefaults.standard.removePersistentDomain(forName: name) }
        return UserDefaults(suiteName: name)!
    }
}

/// Drives an `EditorModel` with mouse input given in screenshot coordinates.
@MainActor
struct CanvasDriver {
    let model: EditorModel

    /// Screenshot space → canvas space.
    func canvas(_ point: CGPoint) -> CGPoint {
        CGPoint(x: point.x + model.padding, y: point.y + model.padding)
    }

    func drag(from start: CGPoint, to end: CGPoint, shift: Bool = false) {
        let from = canvas(start)
        model.handleCanvasDrag(.began(location: from, clickCount: 1))
        model.handleCanvasDrag(.changed(start: from, location: canvas(end), isConstrained: shift))
        model.handleCanvasDrag(.ended)
    }

    func click(_ point: CGPoint, count: Int = 1) {
        model.handleCanvasDrag(.began(location: canvas(point), clickCount: count))
        model.handleCanvasDrag(.ended)
    }

    /// Drags a handle of the selected annotation by `offset`.
    func dragHandle(_ handle: AnnotationHandle, by offset: CGSize, shift: Bool = false) {
        let point = model.selectionHandles.first { $0.handle == handle }!.point
        drag(from: point, to: CGPoint(x: point.x + offset.width, y: point.y + offset.height), shift: shift)
    }
}

extension EditorModel {
    /// A model for a blank 400×240 pt screenshot at 2x, with default styling kept in `store`.
    static func blank(store: UserDefaults) -> EditorModel {
        EditorModel(screenshot: Screenshot(image: TestImage.make(width: 800, height: 480), scale: 2), preferencesStore: store)
    }
}
