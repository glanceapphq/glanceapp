import XCTest
@testable import Glance

/// Resize handles and in-place text editing.
@MainActor
final class AnnotationResizeTests: XCTestCase {
    private var model: EditorModel!
    private var canvas: CanvasDriver!

    private func setUpModel() {
        model = .blank(store: makeIsolatedDefaults())
        canvas = CanvasDriver(model: model)
    }

    private func addRectangle() {
        model.activeTool = .rectangle
        canvas.drag(from: CGPoint(x: 200, y: 50), to: CGPoint(x: 300, y: 150))
        model.activeTool = nil
        canvas.click(CGPoint(x: 250, y: 100))
    }

    private var rectangle: CGRect? {
        if case .rectangle(let rectangle) = model.annotations.first { rectangle.rect } else { nil }
    }

    func testRectangleCornerAndEdgeHandles() {
        setUpModel()
        addRectangle()
        XCTAssertEqual(model.selectionHandles.count, 8)

        canvas.dragHandle(.bottomRight, by: CGSize(width: 40, height: 20))
        XCTAssertEqual(rectangle, CGRect(x: 200, y: 50, width: 140, height: 120))

        // Dragging an edge past the opposite one flips the rectangle and leaves the other axis alone.
        canvas.dragHandle(.left, by: CGSize(width: 200, height: 999))
        XCTAssertEqual(rectangle, CGRect(x: 340, y: 50, width: 60, height: 120))
    }

    func testShiftKeepsRectangleSquareAndUndoRestoresSize() {
        setUpModel()
        addRectangle()
        canvas.dragHandle(.topLeft, by: CGSize(width: -10, height: -100), shift: true)
        XCTAssertEqual(rectangle?.width, rectangle?.height)

        model.undo()
        XCTAssertEqual(rectangle, CGRect(x: 200, y: 50, width: 100, height: 100))
    }

    func testArrowEndpointSnapsTo45Degrees() throws {
        setUpModel()
        model.activeTool = .arrow
        canvas.drag(from: CGPoint(x: 10, y: 300), to: CGPoint(x: 110, y: 300))
        model.activeTool = nil
        canvas.click(CGPoint(x: 60, y: 300))
        XCTAssertEqual(model.selectionHandles.map(\.handle), [.start, .end])

        canvas.dragHandle(.end, by: CGSize(width: 0, height: 80), shift: true)
        guard case .arrow(let arrow) = model.annotations.first else { return XCTFail() }
        XCTAssertEqual(arrow.start, CGPoint(x: 10, y: 300))
        XCTAssertEqual(arrow.end.x - arrow.start.x, arrow.end.y - arrow.start.y, accuracy: 0.01)
    }

    func testCounterGrowsAroundItsCenter() {
        setUpModel()
        model.activeTool = .counter
        canvas.click(CGPoint(x: 300, y: 150))
        model.activeTool = nil
        canvas.click(CGPoint(x: 300, y: 150))

        canvas.dragHandle(.bottomRight, by: CGSize(width: 10, height: 4))
        guard case .counter(let counter) = model.annotations.first else { return XCTFail() }
        XCTAssertEqual(counter.diameter, CounterAnnotation.defaultDiameter + 20, accuracy: 0.01)
        XCTAssertEqual(counter.center, CGPoint(x: 300, y: 150))
    }

    // MARK: Text

    private func addText(_ text: String) -> TextAnnotation? {
        model.activeTool = .text
        canvas.click(CGPoint(x: 100, y: 100))
        model.commitText(text)
        model.activeTool = nil
        return self.text
    }

    private var text: TextAnnotation? {
        if case .text(let text) = model.annotations.last { text } else { nil }
    }

    func testTextScalesFromCornerHandle() throws {
        setUpModel()
        let original = try XCTUnwrap(addText("Hello"))
        canvas.click(CGPoint(x: 110, y: 110))
        canvas.dragHandle(.bottomRight, by: CGSize(width: original.size.width, height: 0))
        XCTAssertEqual(try XCTUnwrap(text).fontSize, TextAnnotation.defaultFontSize * 2, accuracy: 0.01)
    }

    func testBlankTextIsNotAdded() {
        setUpModel()
        XCTAssertNil(addText("   "))
        XCTAssertTrue(model.annotations.isEmpty)
    }

    func testDoubleClickEditsTextInPlace() throws {
        setUpModel()
        let original = try XCTUnwrap(addText("Hello"))

        canvas.click(CGPoint(x: 110, y: 110))
        canvas.click(CGPoint(x: 110, y: 110), count: 2)
        XCTAssertTrue(model.isEditingText)
        XCTAssertEqual(model.textFieldRequest?.text, "Hello")
        XCTAssertTrue(model.visibleAnnotations.isEmpty, "the text field replaces the annotation while editing")

        model.selectColor(.blue)
        model.commitText("Hello world")
        let edited = try XCTUnwrap(text)
        XCTAssertEqual(edited.id, original.id)
        XCTAssertEqual(edited.text, "Hello world")
        XCTAssertEqual(edited.color, .blue)
        XCTAssertEqual(model.annotations.count, 1)

        model.undo()
        XCTAssertEqual(text?.text, "Hello")
        XCTAssertEqual(text?.color, original.color)
    }

    func testClearingEditedTextDeletesIt() {
        setUpModel()
        _ = addText("Hello")
        canvas.click(CGPoint(x: 110, y: 110), count: 2)
        model.commitText("")
        XCTAssertTrue(model.annotations.isEmpty)
    }

    func testUnchangedEditAddsNoHistory() {
        setUpModel()
        _ = addText("Hello")
        model.undo()
        model.redo()
        model.undo()
        XCTAssertTrue(model.canRedo)
        model.redo()

        canvas.click(CGPoint(x: 110, y: 110), count: 2)
        model.commitText("Hello")
        model.undo()
        XCTAssertTrue(model.annotations.isEmpty, "one undo removes the text: the edit recorded nothing")
    }
}
