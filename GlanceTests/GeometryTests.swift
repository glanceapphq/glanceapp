import XCTest
@testable import Glance

final class GeometryTests: XCTestCase {
    func testRectFromCorners() {
        XCTAssertEqual(CGRect(corner: CGPoint(x: 50, y: 40), to: CGPoint(x: 10, y: 20)), CGRect(x: 10, y: 20, width: 40, height: 20))
        XCTAssertEqual(CGRect(corner: .zero, to: CGPoint(x: -30, y: 10), square: true), CGRect(x: -30, y: 0, width: 30, height: 30))
    }

    func testArrowSnapsToNearest45Degrees() {
        let end = ArrowAnnotation.snappedEnd(from: .zero, to: CGPoint(x: 100, y: 10))
        XCTAssertEqual(end.x, hypot(100, 10), accuracy: 0.001)
        XCTAssertEqual(end.y, 0, accuracy: 0.001)
    }

    func testDistanceToSegment() {
        let a = CGPoint(x: 0, y: 0), b = CGPoint(x: 10, y: 0)
        XCTAssertEqual(CGPoint(x: 5, y: 3).distance(toSegmentFrom: a, to: b), 3)
        XCTAssertEqual(CGPoint(x: 13, y: 4).distance(toSegmentFrom: a, to: b), 5, "beyond the end measures to the endpoint")
    }

    func testOutlinedShapesHitOnlyEdgesUnlessInteriorCounts() {
        let rectangle = Annotation.rectangle(RectangleAnnotation(rect: CGRect(x: 0, y: 0, width: 100, height: 100), color: .red))
        XCTAssertTrue(rectangle.contains(CGPoint(x: 1, y: 50), tolerance: 2, includeInterior: false))
        XCTAssertFalse(rectangle.contains(CGPoint(x: 50, y: 50), tolerance: 2, includeInterior: false))
        XCTAssertTrue(rectangle.contains(CGPoint(x: 50, y: 50), tolerance: 2, includeInterior: true))
    }
}
