import XCTest
@testable import Glance

@MainActor
final class EditorPreferencesTests: XCTestCase {
    func testEmptyStoreGivesDefaults() {
        XCTAssertEqual(EditorPreferences.load(from: makeIsolatedDefaults()), .defaults)
    }

    func testRoundTrip() {
        let store = makeIsolatedDefaults()
        let preferences = EditorPreferences(padding: 72, cornerRadius: 0, background: .mint, annotationColor: .blue)
        preferences.save(to: store)
        XCTAssertEqual(EditorPreferences.load(from: store), preferences)
    }

    func testOutOfRangeAndInvalidValues() {
        let store = makeIsolatedDefaults()
        store.set(999.0, forKey: "editor.padding")
        store.set("bogus", forKey: "editor.background")

        let loaded = EditorPreferences.load(from: store)
        XCTAssertEqual(loaded.padding, EditorModel.paddingRange.upperBound)
        XCTAssertEqual(loaded.background, EditorPreferences.defaults.background)
    }

    func testEditorRemembersStyleChanges() {
        let store = makeIsolatedDefaults()
        let model = EditorModel.blank(store: store)
        model.background = .rose
        model.padding = 20

        let next = EditorModel.blank(store: store)
        XCTAssertEqual(next.background, .rose)
        XCTAssertEqual(next.padding, 20)

        next.resetStyle()
        XCTAssertEqual(EditorPreferences.load(from: store), .defaults)
    }
}
