import XCTest
@testable import Glance

@MainActor
final class CanvasLayoutTests: XCTestCase {
    private let wide = CGSize(width: 400, height: 240)
    private let tall = CGSize(width: 200, height: 600)

    func testAutoIsScreenshotPlusPadding() {
        let layout = CanvasLayout(screenshotSize: wide, padding: 48, aspectRatio: .auto, scale: 2)
        XCTAssertEqual(layout.size, CGSize(width: 496, height: 336))
        XCTAssertEqual(layout.screenshotOrigin, CGPoint(x: 48, y: 48))
    }

    func testEveryPresetHasItsRatioAndFitsTheContent() throws {
        for ratio in CanvasAspectRatio.allCases {
            let expected = try XCTUnwrap(ratio.widthToHeight ?? 496 / 336)
            for screenshot in [wide, tall] {
                for scale: CGFloat in [1, 2] {
                    let layout = CanvasLayout(screenshotSize: screenshot, padding: 48, aspectRatio: ratio, scale: scale)
                    let label = "\(ratio) \(screenshot) @\(scale)x"

                    if ratio != .auto {
                        // Within one export pixel of the exact ratio.
                        XCTAssertEqual(layout.size.width, layout.size.height * expected, accuracy: 1 / scale, label)
                    }
                    // Never smaller than screenshot + padding.
                    XCTAssertGreaterThanOrEqual(layout.size.width, screenshot.width + 96, label)
                    XCTAssertGreaterThanOrEqual(layout.size.height, screenshot.height + 96, label)
                    // Whole export pixels, so the image isn't resampled.
                    XCTAssertEqual(layout.size.width * scale, (layout.size.width * scale).rounded(), label)
                    XCTAssertEqual(layout.size.height * scale, (layout.size.height * scale).rounded(), label)
                }
            }
        }
    }

    func testScreenshotIsCenteredOnWholePixels() {
        // 400×240 + 2×48 = 496×336; at 1:1 the canvas grows to 496×496.
        let layout = CanvasLayout(screenshotSize: wide, padding: 48, aspectRatio: .square, scale: 2)
        XCTAssertEqual(layout.size, CGSize(width: 496, height: 496))
        XCTAssertEqual(layout.screenshotOrigin, CGPoint(x: 48, y: 128))
    }

    func testOddLeftoverStaysOnThePixelGrid() {
        // A 101 pt square at 1x: the 16:9 canvas can't be exact, and the gap around the screenshot is odd.
        let layout = CanvasLayout(screenshotSize: CGSize(width: 101, height: 101), padding: 0, aspectRatio: .widescreen, scale: 1)
        XCTAssertEqual(layout.size.height, 101)
        XCTAssertEqual(layout.size.width, 180) // 101 × 16 / 9 = 179.6, rounded up
        XCTAssertEqual(layout.screenshotOrigin.x, 39) // (180 − 101) / 2 = 39.5, rounded down
        XCTAssertEqual(layout.screenshotOrigin.y, 0)
    }

    func testModelUsesTheLayout() {
        let model = EditorModel.blank(store: makeIsolatedDefaults())
        let autoSize = model.canvasSize
        model.aspectRatio = .story

        XCTAssertEqual(model.canvasSize.width, autoSize.width)
        XCTAssertGreaterThan(model.canvasSize.height, autoSize.height)
        XCTAssertEqual(model.screenshotOrigin.x, model.padding)
        XCTAssertGreaterThan(model.screenshotOrigin.y, model.padding)
    }

    func testChangingRatioFitsTheCanvasWithoutUpscaling() {
        let model = EditorModel.blank(store: makeIsolatedDefaults())
        let initial = model.zoomToFitRequest

        model.aspectRatio = .story
        XCTAssertEqual(model.zoomToFitRequest.id, initial.id + 1)
        XCTAssertFalse(model.zoomToFitRequest.allowsUpscaling, "small captures stay at 100%")

        model.aspectRatio = .story
        XCTAssertEqual(model.zoomToFitRequest.id, initial.id + 1, "same ratio: no refit")

        model.padding = 100
        XCTAssertEqual(model.zoomToFitRequest.id, initial.id + 1, "padding doesn't refit")

        model.zoomToFit()
        XCTAssertEqual(model.zoomToFitRequest.id, initial.id + 2)
        XCTAssertTrue(model.zoomToFitRequest.allowsUpscaling, "⌘0 still fills the window")
    }

    func testDrawingSelectingAndMovingHaveNoOffsetAtEveryRatio() {
        for ratio in CanvasAspectRatio.allCases {
            let model = EditorModel.blank(store: makeIsolatedDefaults())
            model.aspectRatio = ratio
            let canvas = CanvasDriver(model: model)

            model.activeTool = .rectangle
            canvas.drag(from: CGPoint(x: 10, y: 20), to: CGPoint(x: 110, y: 80))
            guard case .rectangle(let drawn) = model.annotations.last else { return XCTFail("\(ratio): nothing drawn") }
            XCTAssertEqual(drawn.rect, CGRect(x: 10, y: 20, width: 100, height: 60), "\(ratio)")

            // On the top edge, away from the resize handles.
            canvas.click(CGPoint(x: 35, y: 20))
            XCTAssertTrue(model.hasSelection, "\(ratio)")

            canvas.drag(from: CGPoint(x: 35, y: 20), to: CGPoint(x: 55, y: 30))
            guard case .rectangle(let moved) = model.annotations.last else { return XCTFail("\(ratio): annotation lost") }
            XCTAssertEqual(moved.rect.origin, CGPoint(x: 30, y: 30), "\(ratio)")

            canvas.dragHandle(.bottomRight, by: CGSize(width: 20, height: 10))
            guard case .rectangle(let resized) = model.annotations.last else { return XCTFail("\(ratio): annotation lost") }
            XCTAssertEqual(resized.rect.size, CGSize(width: 120, height: 70), "\(ratio)")
        }
    }

    func testExportHasTheChosenRatio() throws {
        let model = EditorModel.blank(store: makeIsolatedDefaults())
        for ratio in CanvasAspectRatio.allCases {
            model.aspectRatio = ratio
            let image = try XCTUnwrap(TestImage.decodePNG(try RenderService().render(model).pngData))
            XCTAssertEqual(image.width, Int(model.canvasSize.width * 2), "\(ratio)")
            XCTAssertEqual(image.height, Int(model.canvasSize.height * 2), "\(ratio)")
            if let expected = ratio.widthToHeight {
                XCTAssertEqual(CGFloat(image.width), CGFloat(image.height) * expected, accuracy: 1, "\(ratio)")
            }
        }
    }
}
