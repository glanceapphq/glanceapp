import XCTest
@testable import Glance

@MainActor
final class SaveFolderTests: XCTestCase {
    private func makeTemporaryFolder() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appending(path: "GlanceTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: folder) }
        return folder
    }

    private func makeImage() throws -> RenderedImage {
        try RenderService().render(.blank(store: makeIsolatedDefaults()))
    }

    func testDefaultsToDownloads() {
        let folder = SaveFolder(store: makeIsolatedDefaults())
        XCTAssertFalse(folder.isCustom)
        XCTAssertNil(folder.customFolder)
        XCTAssertEqual(folder.folder.lastPathComponent, "Downloads")
    }

    func testSavesIntoChosenFolderWithoutOverwriting() throws {
        let directory = try makeTemporaryFolder()
        let folder = SaveFolder(store: makeIsolatedDefaults())
        try folder.choose(directory)
        XCTAssertTrue(folder.isCustom)
        XCTAssertEqual(folder.title, directory.lastPathComponent)

        let image = try makeImage()
        let first = try ExportService().save(image, to: folder)
        let second = try ExportService().save(image, to: folder)

        XCTAssertEqual(first.deletingLastPathComponent().resolvingSymlinksInPath(), directory.resolvingSymlinksInPath())
        XCTAssertNotEqual(first, second)
        XCTAssertTrue(first.lastPathComponent.hasPrefix("Screenshot "))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path(percentEncoded: false)).count, 2)
        XCTAssertNotNil(TestImage.decodePNG(try Data(contentsOf: second)))
    }

    func testResetGoesBackToDownloads() throws {
        let folder = SaveFolder(store: makeIsolatedDefaults())
        try folder.choose(try makeTemporaryFolder())
        folder.reset()
        XCTAssertFalse(folder.isCustom)
    }

    func testDeletedFolderReportsAnError() throws {
        let directory = try makeTemporaryFolder()
        let folder = SaveFolder(store: makeIsolatedDefaults())
        try folder.choose(directory)
        try FileManager.default.removeItem(at: directory)

        XCTAssertThrowsError(try ExportService().save(try makeImage(), to: folder)) { error in
            guard case ExportError.saveFolderUnavailable = error else { return XCTFail("unexpected error: \(error)") }
        }
    }
}
