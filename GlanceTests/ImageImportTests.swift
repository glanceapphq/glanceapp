import AppKit
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import Glance

@MainActor
final class ImageImportTests: XCTestCase {
    private let service = ImageImportService()

    // MARK: - Scale from DPI

    func testScaleFromDPI() {
        XCTAssertEqual(ImageImportService.scale(fromProperties: [kCGImagePropertyDPIWidth: 72]), 1)
        XCTAssertEqual(ImageImportService.scale(fromProperties: [kCGImagePropertyDPIWidth: 144]), 2)
        XCTAssertEqual(ImageImportService.scale(fromProperties: [kCGImagePropertyDPIWidth: 216]), 3)
    }

    func testScaleDefaultsToOneWithoutUsableDPI() {
        XCTAssertEqual(ImageImportService.scale(fromProperties: [:]), 1)
        XCTAssertEqual(ImageImportService.scale(fromProperties: [kCGImagePropertyDPIWidth: 0]), 1)
        // Low-DPI images are shown pixel for pixel, never enlarged.
        XCTAssertEqual(ImageImportService.scale(fromProperties: [kCGImagePropertyDPIWidth: 36]), 1)
    }

    func testScaleIgnoresPNGRoundingOfDPI() {
        // PNG stores 144 DPI as 5669 pixels per metre, which reads back as 143.99 DPI.
        let dpi = 5669 * 0.0254
        XCTAssertEqual(ImageImportService.scale(fromProperties: [kCGImagePropertyDPIWidth: dpi]), 2)
    }

    // MARK: - Decoding

    func testGlanceExportReopensAtSameSize() throws {
        // Exactly what `RenderService` writes: 800×480 px with a point size of 400×240 (144 DPI).
        let png = try XCTUnwrap(Self.png(width: 800, height: 480, pointSize: CGSize(width: 400, height: 240)))

        let screenshot = try service.screenshot(from: png)
        XCTAssertEqual(screenshot.scale, 2)
        XCTAssertEqual(screenshot.size, CGSize(width: 400, height: 240))
    }

    func testOpensFile() throws {
        let png = try XCTUnwrap(Self.png(width: 300, height: 200, pointSize: CGSize(width: 300, height: 200)))
        let url = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).png")
        try png.write(to: url)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }

        let screenshot = try service.screenshot(contentsOf: url)
        XCTAssertEqual(screenshot.scale, 1)
        XCTAssertEqual(screenshot.image.width, 300)
        XCTAssertEqual(screenshot.image.height, 200)
    }

    func testAppliesEXIFOrientation() throws {
        // A landscape JPEG tagged "rotate 90°", as phones save portrait photos.
        let data = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, TestImage.make(width: 60, height: 40), [kCGImagePropertyOrientation: 6] as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination))

        let screenshot = try service.screenshot(from: data as Data)
        XCTAssertEqual(screenshot.image.width, 40)
        XCTAssertEqual(screenshot.image.height, 60)
    }

    func testCorruptDataThrows() {
        XCTAssertThrowsError(try service.screenshot(from: Data("not an image".utf8)))
        XCTAssertThrowsError(try service.screenshot(from: Data()))
    }

    func testUnsupportedFileThrowsWithItsName() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "notes-\(UUID().uuidString).txt")
        try Data("hello".utf8).write(to: url)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }

        XCTAssertThrowsError(try service.screenshot(contentsOf: url)) { error in
            XCTAssertTrue(error.localizedDescription.contains(url.lastPathComponent))
        }
    }

    // MARK: - Clipboard

    func testReadsImageCopiedByGlance() throws {
        let pasteboard = makePasteboard()
        let png = try XCTUnwrap(Self.png(width: 800, height: 480, pointSize: CGSize(width: 400, height: 240)))
        let item = NSPasteboardItem()
        item.setData(png, forType: .png)
        pasteboard.writeObjects([item])

        XCTAssertTrue(ImageImportService.canReadImage(from: pasteboard))
        let screenshot = try service.screenshot(from: pasteboard)
        XCTAssertEqual(screenshot.size, CGSize(width: 400, height: 240))
    }

    func testTextOnClipboardIsNotAnImage() {
        let pasteboard = makePasteboard()
        pasteboard.setString("hello", forType: .string)

        XCTAssertFalse(ImageImportService.canReadImage(from: pasteboard))
        XCTAssertThrowsError(try service.screenshot(from: pasteboard))
    }

    // MARK: - Helpers

    /// A private pasteboard, so tests never touch the user's clipboard.
    private func makePasteboard() -> NSPasteboard {
        let pasteboard = NSPasteboard.withUniqueName()
        addTeardownBlock { pasteboard.releaseGlobally() }
        return pasteboard
    }

    /// PNG data whose DPI follows from `pointSize`, the way `RenderService` encodes exports.
    private static func png(width: Int, height: Int, pointSize: CGSize) -> Data? {
        let bitmap = NSBitmapImageRep(cgImage: TestImage.make(width: width, height: height))
        bitmap.size = pointSize
        return bitmap.representation(using: .png, properties: [:])
    }
}
