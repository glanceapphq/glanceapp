import SwiftUI

/// Editing state for a single screenshot.
@Observable
final class EditorModel {
    static let zoomRange: ClosedRange<CGFloat> = 0.1...8
    static let paddingRange: ClosedRange<CGFloat> = 0...160
    static let cornerRadiusRange: ClosedRange<CGFloat> = 0...32

    let screenshot: Screenshot

    // Styling is remembered between screenshots (see `EditorPreferences`).
    var padding: CGFloat { didSet { savePreferences() } }
    var cornerRadius: CGFloat { didSet { savePreferences() } }
    var background: CanvasBackground { didSet { savePreferences() } }
    var annotationColor: AnnotationColor { didSet { savePreferences() } }

    var activeTool: EditorTool? = .arrow

    /// Committed annotations, in drawing order.
    private(set) var annotations: [Annotation] = []
    /// The annotation currently being dragged out, not yet committed.
    private(set) var draft: Annotation?
    /// Selected annotation, shown with a selection frame and affected by delete/recolor.
    private(set) var selectedAnnotationID: UUID?

    // History holds snapshots of `annotations`, so every kind of change undoes the same way.
    private var undoStack: [[Annotation]] = []
    private var redoStack: [[Annotation]] = []
    /// In-progress move or resize of the selected annotation.
    @ObservationIgnored private var annotationDrag: AnnotationDrag?

    /// Text currently being typed, or `nil` when not editing text.
    private(set) var textEditing: TextEditingSession?

    @ObservationIgnored private var pixelatedCache: CGImage?
    /// Where styling is remembered.
    @ObservationIgnored private let preferencesStore: UserDefaults

    /// Canvas magnification; `1` shows the screenshot at its native point size.
    var zoom: CGFloat = 1
    /// Incremented to ask the canvas to fit itself into the visible area.
    private(set) var zoomToFitRequest = 0

    /// - Parameters:
    ///   - document: Earlier edits to restore, e.g. when reopening from history;
    ///     `nil` starts with no annotations and the remembered style.
    ///   - preferencesStore: Where styling is remembered between screenshots.
    init(screenshot: Screenshot, document: EditorDocument? = nil, preferencesStore: UserDefaults = .standard) {
        let preferences = document?.preferences ?? .load(from: preferencesStore)
        self.screenshot = screenshot
        self.preferencesStore = preferencesStore
        self.padding = preferences.padding
        self.cornerRadius = preferences.cornerRadius
        self.background = preferences.background
        self.annotationColor = preferences.annotationColor
        self.annotations = document?.annotations ?? []
    }

    /// Current edits, for reopening the screenshot later.
    var document: EditorDocument {
        EditorDocument(annotations: annotations, preferences: preferences)
    }

    var preferences: EditorPreferences {
        EditorPreferences(padding: padding, cornerRadius: cornerRadius, background: background, annotationColor: annotationColor)
    }

    var hasDefaultStyle: Bool { preferences == .defaults }

    /// Restores default styling (and saves it as the new preference).
    func resetStyle() {
        let defaults = EditorPreferences.defaults
        padding = defaults.padding
        cornerRadius = defaults.cornerRadius
        background = defaults.background
        annotationColor = defaults.annotationColor
    }

    private func savePreferences() {
        preferences.save(to: preferencesStore)
    }

    /// Size of the full composition (screenshot + padding) in points.
    var canvasSize: CGSize {
        CGSize(
            width: screenshot.size.width + padding * 2,
            height: screenshot.size.height + padding * 2
        )
    }

    // MARK: Annotations

    /// Committed annotations plus the one being drawn, minus text being re-edited
    /// (the text field shows it instead).
    var visibleAnnotations: [Annotation] {
        let editingID = textEditing?.annotationID
        return annotations.filter { $0.id != editingID } + [draft].compactMap { $0 }
    }

    /// Areas to pixelate, in screenshot space.
    var pixelatedRects: [CGRect] {
        visibleAnnotations.compactMap {
            if case .pixelate(let pixelate) = $0 { pixelate.rect } else { nil }
        }
    }

    /// Pixelated copy of the screenshot, created on first use.
    var pixelatedScreenshot: CGImage? {
        if pixelatedCache == nil {
            pixelatedCache = Pixelator.pixelate(screenshot.image, blockSize: 12 * screenshot.scale)
        }
        return pixelatedCache
    }

    var isEditingText: Bool { textEditing != nil }
    var canUndo: Bool { !undoStack.isEmpty && !isEditingText }
    var canRedo: Bool { !redoStack.isEmpty && !isEditingText }

    /// Where the canvas should show its text field, in canvas space.
    var textFieldRequest: CanvasTextFieldRequest? {
        textEditing.map {
            CanvasTextFieldRequest(
                id: $0.id,
                origin: CGPoint(x: $0.origin.x + padding, y: $0.origin.y + padding),
                text: $0.text,
                fontSize: $0.fontSize
            )
        }
    }

    /// Color of the text being typed.
    var textEditingColor: AnnotationColor {
        textEditing?.color ?? annotationColor
    }

    var selectedAnnotation: Annotation? {
        annotations.first { $0.id == selectedAnnotationID }
    }

    var hasSelection: Bool { selectedAnnotation != nil }

    /// Gap between an annotation and its selection frame; constant on screen at any zoom.
    var selectionOutset: CGFloat { 4 / max(zoom, 0.01) }

    /// Selection frame around the selected annotation in screenshot space, or `nil`
    /// for arrows, which show only their endpoint handles.
    var selectionFrame: CGRect? {
        guard let annotation = selectedAnnotation else { return nil }
        if case .arrow = annotation { return nil }
        return annotation.bounds.insetBy(dx: -selectionOutset, dy: -selectionOutset)
    }

    /// Resize handles of the selected annotation and where they are, in screenshot space.
    var selectionHandles: [(handle: AnnotationHandle, point: CGPoint)] {
        guard let annotation = selectedAnnotation else { return [] }
        if case .arrow(let arrow) = annotation {
            return [(.start, arrow.start), (.end, arrow.end)]
        }
        guard let frame = selectionFrame else { return [] }
        return annotation.handles.map { ($0, frame.point(for: $0)) }
    }
    /// Whether annotations changed since the editor opened.
    private(set) var hasAnnotationChanges = false

    /// Applies a mouse interaction on the canvas.
    ///
    /// Dragging a handle of the selected annotation resizes it. Pressing on an existing
    /// annotation selects it and dragging moves it; double-clicking text edits it.
    /// Pressing on empty space clears the selection and uses the active tool.
    func handleCanvasDrag(_ drag: CanvasDrag) {
        switch drag {
        case let .began(location, clickCount):
            let point = toScreenshotSpace(location)
            if let selected = selectedAnnotation, let handle = handle(at: point) {
                annotationDrag = AnnotationDrag(original: selected, handle: handle, start: point, snapshot: annotations)
                return
            }
            if let hit = annotation(at: point) {
                if clickCount >= 2, case .text(let text) = hit {
                    beginEditing(text)
                    return
                }
                selectedAnnotationID = hit.id
                annotationDrag = AnnotationDrag(original: hit, handle: nil, start: point, snapshot: annotations)
                return
            }
            selectedAnnotationID = nil

            switch activeTool {
            case .counter:
                addAnnotation(.counter(CounterAnnotation(center: point, number: nextCounterNumber, color: annotationColor)))
            case .text:
                textEditing = TextEditingSession(origin: point, color: annotationColor)
            case .arrow, .rectangle, .pixelate, nil:
                break
            }

        case let .changed(start, location, isConstrained):
            if annotationDrag != nil {
                dragSelection(to: toScreenshotSpace(location), isConstrained: isConstrained)
                return
            }

            let start = toScreenshotSpace(start)
            let end = toScreenshotSpace(location)
            switch activeTool {
            case .arrow:
                let end = isConstrained ? ArrowAnnotation.snappedEnd(from: start, to: end) : end
                draft = .arrow(ArrowAnnotation(start: start, end: end, color: annotationColor))
            case .rectangle:
                draft = .rectangle(RectangleAnnotation(rect: CGRect(corner: start, to: end, square: isConstrained), color: annotationColor))
            case .pixelate:
                draft = .pixelate(PixelateAnnotation(rect: CGRect(corner: start, to: end, square: isConstrained)))
            case .text, .counter, nil:
                break
            }

        case .ended:
            if let annotationDrag {
                self.annotationDrag = nil
                if annotationDrag.didChange {
                    recordHistory(annotationDrag.snapshot)
                }
                return
            }

            if let draft, Self.isLargeEnough(draft) {
                addAnnotation(draft)
            }
            draft = nil
        }
    }

    /// Finishes text editing. New text is added unless it's blank; edited text is
    /// updated, or deleted when cleared.
    func commitText(_ text: String) {
        guard let session = textEditing else { return }
        textEditing = nil

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        guard let id = session.annotationID else {
            guard !trimmed.isEmpty else { return }
            addAnnotation(.text(TextAnnotation(origin: session.origin, text: trimmed, color: session.color, fontSize: session.fontSize)))
            return
        }

        guard let index = annotations.firstIndex(where: { $0.id == id }), case .text(var edited) = annotations[index] else { return }
        if trimmed.isEmpty {
            change { $0.remove(at: index) }
            return
        }

        selectedAnnotationID = id
        guard trimmed != edited.text || session.color != edited.color else { return }
        edited.text = trimmed
        edited.color = session.color
        change { $0[index] = .text(edited) }
    }

    func addAnnotation(_ annotation: Annotation) {
        change { $0.append(annotation) }
    }

    func deleteSelection() {
        guard let id = selectedAnnotation?.id else { return }
        change { $0.removeAll { $0.id == id } }
        selectedAnnotationID = nil
    }

    func clearSelection() {
        selectedAnnotationID = nil
    }

    /// Sets the color for new annotations and recolors the selected one.
    func selectColor(_ color: AnnotationColor) {
        annotationColor = color
        textEditing?.color = color

        guard let selected = selectedAnnotation,
              let recolored = selected.recolored(color),
              let index = annotations.firstIndex(where: { $0.id == selected.id })
        else { return }
        change { $0[index] = recolored }
    }

    func undo() {
        guard canUndo, let previous = undoStack.popLast() else { return }
        redoStack.append(annotations)
        annotations = previous
        selectedAnnotationID = nil
    }

    func redo() {
        guard canRedo, let next = redoStack.popLast() else { return }
        undoStack.append(annotations)
        annotations = next
        selectedAnnotationID = nil
    }

    /// Applies an undoable change to `annotations`.
    private func change(_ body: (inout [Annotation]) -> Void) {
        recordHistory(annotations)
        body(&annotations)
    }

    private func recordHistory(_ snapshot: [Annotation]) {
        undoStack.append(snapshot)
        redoStack.removeAll()
        hasAnnotationChanges = true
    }

    /// Starts editing an existing text annotation in place.
    private func beginEditing(_ text: TextAnnotation) {
        selectedAnnotationID = nil
        textEditing = TextEditingSession(origin: text.origin, text: text.text, color: text.color, fontSize: text.fontSize, annotationID: text.id)
    }

    /// Handle of the selected annotation under `point`. Hit size stays constant on screen.
    private func handle(at point: CGPoint) -> AnnotationHandle? {
        let radius = 7 / zoom
        return selectionHandles
            .filter { hypot($0.point.x - point.x, $0.point.y - point.y) <= radius }
            .min { hypot($0.point.x - point.x, $0.point.y - point.y) < hypot($1.point.x - point.x, $1.point.y - point.y) }?
            .handle
    }

    /// Topmost annotation under `point`. Hit slack stays constant on screen regardless of zoom.
    private func annotation(at point: CGPoint) -> Annotation? {
        let tolerance = 6 / zoom
        // Without a tool, clicking inside outlined shapes selects them too.
        let includeInterior = activeTool == nil
        return annotations.last { $0.contains(point, tolerance: tolerance, includeInterior: includeInterior) }
    }

    /// Moves the dragged annotation, or resizes it when a handle is being dragged.
    /// `isConstrained` locks moves to an axis and constrains resizing (see `Annotation.resized`).
    private func dragSelection(to point: CGPoint, isConstrained: Bool) {
        guard var drag = annotationDrag, let index = annotations.firstIndex(where: { $0.id == drag.original.id }) else { return }

        var offset = CGSize(width: point.x - drag.start.x, height: point.y - drag.start.y)

        // Live update without history; the whole drag is recorded once when it ends.
        if let handle = drag.handle {
            annotations[index] = drag.original.resized(handle, by: offset, constrained: isConstrained)
        } else {
            if isConstrained {
                if abs(offset.width) > abs(offset.height) { offset.height = 0 } else { offset.width = 0 }
            }
            annotations[index] = drag.original.offset(by: offset)
        }
        drag.didChange = drag.didChange || offset != .zero
        annotationDrag = drag
    }

    private var nextCounterNumber: Int {
        let numbers = annotations.compactMap {
            if case .counter(let counter) = $0 { counter.number } else { nil }
        }
        return (numbers.max() ?? 0) + 1
    }

    /// Filters out clicks and tiny accidental drags.
    private static func isLargeEnough(_ annotation: Annotation) -> Bool {
        switch annotation {
        case .arrow(let arrow): arrow.length >= 4
        case .rectangle(let rectangle): rectangle.rect.width >= 4 && rectangle.rect.height >= 4
        case .pixelate(let pixelate): pixelate.rect.width >= 4 && pixelate.rect.height >= 4
        case .text, .counter: true
        }
    }

    // MARK: Zoom

    func zoomIn() { setZoom(zoom * 1.25) }
    func zoomOut() { setZoom(zoom / 1.25) }
    func zoomToActualSize() { setZoom(1) }
    func zoomToFit() { zoomToFitRequest += 1 }

    /// Canvas points → screenshot points (annotations are stored relative to the screenshot).
    private func toScreenshotSpace(_ point: CGPoint) -> CGPoint {
        CGPoint(x: point.x - padding, y: point.y - padding)
    }

    private func setZoom(_ value: CGFloat) {
        zoom = value.clamped(to: Self.zoomRange)
    }
}

/// Annotations and style of an edited screenshot.
struct EditorDocument {
    var annotations: [Annotation]
    var preferences: EditorPreferences
}

/// Dragging an existing annotation: moving it, or resizing it by one of its handles.
private struct AnnotationDrag {
    /// The annotation as it was when the drag started.
    let original: Annotation
    /// The handle being dragged, or `nil` when moving.
    let handle: AnnotationHandle?
    /// Where the drag started, in screenshot space.
    let start: CGPoint
    /// Annotations before the drag, recorded for undo if it actually changes something.
    let snapshot: [Annotation]
    var didChange = false
}

/// One text-typing session: each click with the text tool starts a new one, and
/// double-clicking existing text starts one that edits it.
struct TextEditingSession {
    let id = UUID()
    /// Top-left of the text, in screenshot space.
    let origin: CGPoint
    /// Text the field starts with.
    var text = ""
    var color: AnnotationColor
    var fontSize = TextAnnotation.defaultFontSize
    /// The text annotation being edited, or `nil` for new text.
    var annotationID: UUID?
}

/// Background presets for the composition.
enum CanvasBackground: String, CaseIterable, Identifiable {
    case none
    case white
    case midnight
    case violet
    case sky
    case mint
    case peach
    case rose

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none: "None"
        default: rawValue.capitalized
        }
    }

    /// Fill for the background, or `nil` for a transparent one.
    var style: AnyShapeStyle? {
        switch self {
        case .none: nil
        case .white: AnyShapeStyle(Color.white)
        case .midnight: gradient(0x232526, 0x414345)
        case .violet: gradient(0x667EEA, 0x764BA2)
        case .sky: gradient(0x4FACFE, 0x00F2FE)
        case .mint: gradient(0x43E97B, 0x38F9D7)
        case .peach: gradient(0xF6D365, 0xFDA085)
        case .rose: gradient(0xFF9A9E, 0xFECFEF)
        }
    }

    private func gradient(_ from: UInt32, _ to: UInt32) -> AnyShapeStyle {
        AnyShapeStyle(LinearGradient(colors: [Color(hex: from), Color(hex: to)], startPoint: .topLeading, endPoint: .bottomTrailing))
    }
}

extension Color {
    /// Creates an sRGB color from a `0xRRGGBB` value.
    nonisolated init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}
