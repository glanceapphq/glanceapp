import XCTest
@testable import Glance

@MainActor
final class RenderTests: XCTestCase {
    func testExportMatchesCanvasAtScreenshotScale() throws {
        let model = EditorModel.blank(store: makeIsolatedDefaults())
        model.addAnnotation(.arrow(ArrowAnnotation(start: CGPoint(x: 20, y: 20), end: CGPoint(x: 120, y: 80), color: .red)))

        let image = try XCTUnwrap(TestImage.decodePNG(try RenderService().render(model).pngData))
        XCTAssertEqual(image.width, Int(model.canvasSize.width * 2))
        XCTAssertEqual(image.height, Int(model.canvasSize.height * 2))
        XCTAssertEqual(TestImage.pixel(of: image, x: 1, y: 1)[3], 255, "background is opaque")
    }

    func testNoBackgroundKeepsTransparency() throws {
        let model = EditorModel.blank(store: makeIsolatedDefaults())
        model.background = .none

        let image = try XCTUnwrap(TestImage.decodePNG(try RenderService().render(model).pngData))
        XCTAssertEqual(TestImage.pixel(of: image, x: 1, y: 1)[3], 0)
    }

    func testPixelationAveragesEachBlock() throws {
        // Black left half, white right half: one 4×4 block averages to mid gray.
        let image = TestImage.make(width: 4, height: 4) { context in
            context.fill(CGRect(x: 0, y: 0, width: 4, height: 4), red: 1, green: 1, blue: 1)
            context.fill(CGRect(x: 0, y: 0, width: 2, height: 4), red: 0, green: 0, blue: 0)
        }
        let pixelated = try XCTUnwrap(Pixelator.pixelate(image, blockSize: 4))

        for (x, y) in [(0, 0), (3, 3)] {
            let pixel = TestImage.pixel(of: pixelated, x: x, y: y)
            XCTAssertEqual(Int(pixel[0]), 128, accuracy: 30, "pixel (\(x), \(y)) is gray: \(pixel)")
        }
    }
}
