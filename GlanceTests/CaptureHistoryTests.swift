import XCTest
@testable import Glance

@MainActor
final class CaptureHistoryTests: XCTestCase {
    /// A 150×100 pt crop at 2x whose top-left area is blue, cut from a larger red image.
    private func makeCrop() -> Screenshot {
        let image = TestImage.make(width: 400, height: 300) { context in
            context.fill(CGRect(x: 0, y: 0, width: 400, height: 300), red: 1, green: 0, blue: 0)
            context.fill(CGRect(x: 0, y: 150, width: 200, height: 150), red: 0, green: 0, blue: 1)
        }
        return Screenshot(image: image, scale: 2).cropped(to: CGRect(x: 0, y: 0, width: 150, height: 100))!
    }

    func testEntryKeepsSizeAndSmallThumbnail() {
        let entry = CaptureHistory().add(makeCrop())
        XCTAssertEqual(entry.size, CGSize(width: 150, height: 100))
        XCTAssertLessThanOrEqual(entry.thumbnail.size.width, CaptureHistoryEntry.thumbnailSize.width)
        XCTAssertLessThanOrEqual(entry.thumbnail.size.height, CaptureHistoryEntry.thumbnailSize.height)
    }

    func testImageSurvivesCompression() async throws {
        let crop = makeCrop()
        let entry = CaptureHistory().add(crop)

        for _ in 0..<100 where !entry.isCompressed {
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertTrue(entry.isCompressed)

        let restored = try XCTUnwrap(entry.screenshot)
        XCTAssertEqual(restored.scale, 2)
        XCTAssertEqual(restored.image.width, 300)
        XCTAssertEqual(restored.image.height, 200)
        XCTAssertEqual(TestImage.pixel(of: restored.image, x: 10, y: 10), [0, 0, 255, 255])
        XCTAssertEqual(TestImage.pixel(of: restored.image, x: 299, y: 199), TestImage.pixel(of: crop.image, x: 299, y: 199))
    }

    func testNewestFirstAndCapped() {
        let history = CaptureHistory()
        let first = history.add(makeCrop())
        for _ in 0..<CaptureHistory.limit {
            _ = history.add(makeCrop())
        }
        let newest = history.add(makeCrop())

        XCTAssertEqual(history.entries.count, CaptureHistory.limit)
        XCTAssertIdentical(history.entries.first, newest)
        XCTAssertNil(history.entry(id: first.id))
        XCTAssertIdentical(history.entry(id: newest.id), newest)

        history.removeAll()
        XCTAssertTrue(history.entries.isEmpty)
    }

    func testDocumentReopensWithAnnotationsAndStyle() throws {
        let entry = CaptureHistory().add(makeCrop())
        let screenshot = try XCTUnwrap(entry.screenshot)

        let model = EditorModel(screenshot: screenshot, preferencesStore: makeIsolatedDefaults())
        model.addAnnotation(.counter(CounterAnnotation(center: .zero, number: 1, color: .blue)))
        model.background = .mint
        entry.document = model.document

        let reopened = EditorModel(screenshot: screenshot, document: entry.document, preferencesStore: makeIsolatedDefaults())
        XCTAssertEqual(reopened.annotations.count, 1)
        XCTAssertEqual(reopened.background, .mint)
    }
}
