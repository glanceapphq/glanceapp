import AppKit
import XCTest
@testable import Glance

@MainActor
final class SelectionTests: XCTestCase {
    private func makeModel() -> SelectionModel {
        let model = SelectionModel()
        model.screenSize = CGSize(width: 1920, height: 1080)
        model.windows = [SelectableWindow(id: 1, frame: CGRect(x: 100, y: 200, width: 800, height: 600))]
        return model
    }

    func testSnapsToWindowEdges() {
        let model = makeModel()
        model.drag(from: CGPoint(x: 103, y: 196), to: CGPoint(x: 895, y: 805), snapping: true)
        XCTAssertEqual(model.rect, CGRect(x: 100, y: 200, width: 800, height: 600))
        XCTAssertEqual(model.snappedX, 900)
        XCTAssertEqual(model.snappedY, 800)
    }

    func testOptionDisablesSnapping() {
        let model = makeModel()
        model.drag(from: CGPoint(x: 103, y: 196), to: CGPoint(x: 895, y: 805), snapping: false)
        XCTAssertEqual(model.rect, CGRect(x: 103, y: 196, width: 792, height: 609))
        XCTAssertNil(model.snappedX)
        XCTAssertNil(model.snappedY)
    }

    func testSnapsToScreenEdgesOnlyWhenClose() {
        let model = makeModel()
        model.drag(from: CGPoint(x: 400, y: 400), to: CGPoint(x: 1916, y: 1077), snapping: true)
        XCTAssertEqual(model.current, CGPoint(x: 1920, y: 1080))

        model.drag(from: CGPoint(x: 400, y: 400), to: CGPoint(x: 500, y: 500), snapping: true)
        XCTAssertEqual(model.current, CGPoint(x: 500, y: 500))
        XCTAssertNil(model.snappedX)
    }

    func testCropUsesTopLeftPoints() throws {
        // 400×240 pt at 2x, red exactly at (10, 20, 100, 50) pt in top-left coordinates.
        let image = TestImage.make(width: 800, height: 480) { context in
            context.fill(CGRect(x: 0, y: 0, width: 800, height: 480), red: 1, green: 1, blue: 1)
            context.fill(CGRect(x: 20, y: 480 - 40 - 100, width: 200, height: 100), red: 1, green: 0, blue: 0)
        }
        let cropped = try XCTUnwrap(Screenshot(image: image, scale: 2).cropped(to: CGRect(x: 10, y: 20, width: 100, height: 50)))

        XCTAssertEqual(cropped.size, CGSize(width: 100, height: 50))
        XCTAssertEqual(cropped.image.width, 200)
        XCTAssertEqual(cropped.image.height, 100)
        for (x, y) in [(0, 0), (199, 0), (0, 99), (199, 99), (100, 50)] {
            XCTAssertEqual(TestImage.pixel(of: cropped.image, x: x, y: y), [255, 0, 0, 255], "pixel (\(x), \(y))")
        }
    }
}
