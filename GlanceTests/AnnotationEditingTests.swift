import XCTest
@testable import Glance

/// Drawing, selecting, moving, recoloring and deleting annotations, with undo.
@MainActor
final class AnnotationEditingTests: XCTestCase {
    private var model: EditorModel!
    private var canvas: CanvasDriver!

    private func setUpModel() {
        model = .blank(store: makeIsolatedDefaults())
        canvas = CanvasDriver(model: model)
        // An arrow (10,10)→(110,10) and a rectangle (200,50)-(300,150).
        model.activeTool = .arrow
        canvas.drag(from: CGPoint(x: 10, y: 10), to: CGPoint(x: 110, y: 10))
        model.activeTool = .rectangle
        canvas.drag(from: CGPoint(x: 200, y: 50), to: CGPoint(x: 300, y: 150))
    }

    private var arrow: ArrowAnnotation? {
        model.annotations.lazy.compactMap { if case .arrow(let arrow) = $0 { arrow } else { nil } }.first
    }

    func testDrawing() {
        setUpModel()
        XCTAssertEqual(model.annotations.count, 2)
        XCTAssertTrue(model.hasAnnotationChanges)
    }

    func testTinyDragsAreIgnored() {
        setUpModel()
        model.activeTool = .rectangle
        canvas.drag(from: CGPoint(x: 350, y: 200), to: CGPoint(x: 352, y: 201))
        XCTAssertEqual(model.annotations.count, 2)
    }

    func testDrawingInsideRectangleWithToolDoesNotSelectIt() {
        setUpModel()
        model.activeTool = .arrow
        canvas.drag(from: CGPoint(x: 230, y: 80), to: CGPoint(x: 270, y: 120))
        XCTAssertEqual(model.annotations.count, 3)
        XCTAssertFalse(model.hasSelection)

        model.undo()
        XCTAssertEqual(model.annotations.count, 2)
    }

    func testMoveRecolorAndUndo() {
        setUpModel()

        // Pressing on the shaft selects the arrow; dragging moves it.
        canvas.drag(from: CGPoint(x: 60, y: 12), to: CGPoint(x: 60, y: 72))
        XCTAssertEqual(model.annotations.count, 2)
        XCTAssertEqual(arrow?.start, CGPoint(x: 10, y: 70))
        XCTAssertEqual(arrow?.end, CGPoint(x: 110, y: 70))

        // Shift locks the move to one axis.
        canvas.drag(from: CGPoint(x: 60, y: 70), to: CGPoint(x: 100, y: 75), shift: true)
        XCTAssertEqual(arrow?.start, CGPoint(x: 50, y: 70))

        model.selectColor(.blue)
        XCTAssertEqual(arrow?.color, .blue)

        model.undo()
        XCTAssertEqual(arrow?.color, .red)
        XCTAssertEqual(arrow?.start, CGPoint(x: 50, y: 70))
        model.undo()
        model.undo()
        XCTAssertEqual(arrow?.start, CGPoint(x: 10, y: 10))
        model.redo()
        XCTAssertEqual(arrow?.start, CGPoint(x: 10, y: 70))
    }

    func testSelectWithoutToolAndDelete() {
        setUpModel()
        model.activeTool = nil
        canvas.click(CGPoint(x: 250, y: 100))
        guard case .rectangle = model.selectedAnnotation else { return XCTFail("interior click selects the rectangle") }

        model.deleteSelection()
        XCTAssertEqual(model.annotations.count, 1)
        XCTAssertFalse(model.hasSelection)

        model.undo()
        XCTAssertEqual(model.annotations.count, 2)

        // A plain click doesn't touch history, so redo stays available.
        XCTAssertTrue(model.canRedo)
        canvas.click(CGPoint(x: 250, y: 100))
        XCTAssertTrue(model.canRedo)
    }

    func testCountersNumberThemselves() {
        model = .blank(store: makeIsolatedDefaults())
        canvas = CanvasDriver(model: model)
        model.activeTool = .counter
        canvas.click(CGPoint(x: 20, y: 20))
        canvas.click(CGPoint(x: 80, y: 20))

        let numbers = model.annotations.compactMap { if case .counter(let counter) = $0 { counter.number } else { nil } }
        XCTAssertEqual(numbers, [1, 2])
    }

    func testReopenedDocumentStartsUnchanged() {
        setUpModel()
        let reopened = EditorModel(screenshot: model.screenshot, document: model.document, preferencesStore: makeIsolatedDefaults())
        XCTAssertEqual(reopened.annotations.count, 2)
        XCTAssertFalse(reopened.hasAnnotationChanges)
        XCTAssertFalse(reopened.canUndo)
    }
}
