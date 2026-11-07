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
    private var redoStack: [Annotation] = []

    /// Text currently being typed, or `nil` when not editing text.
    private(set) var textEditing: TextEditingSession?

    @ObservationIgnored private var pixelatedCache: CGImage?

    /// Canvas magnification; `1` shows the screenshot at its native point size.
    var zoom: CGFloat = 1
    /// Incremented to ask the canvas to fit itself into the visible area.
    private(set) var zoomToFitRequest = 0

    init(screenshot: Screenshot, preferences: EditorPreferences = .load()) {
        self.screenshot = screenshot
        self.padding = preferences.padding
        self.cornerRadius = preferences.cornerRadius
        self.background = preferences.background
        self.annotationColor = preferences.annotationColor
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
        preferences.save()
    }

    /// Size of the full composition (screenshot + padding) in points.
    var canvasSize: CGSize {
        CGSize(
            width: screenshot.size.width + padding * 2,
            height: screenshot.size.height + padding * 2
        )
    }

    // MARK: Annotations

    /// Committed annotations plus the one being drawn.
    var visibleAnnotations: [Annotation] {
        annotations + [draft].compactMap { $0 }
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
    var canUndo: Bool { !annotations.isEmpty && !isEditingText }
    var canRedo: Bool { !redoStack.isEmpty && !isEditingText }

    /// Where the canvas should show its text field, in canvas space.
    var textFieldRequest: CanvasTextFieldRequest? {
        textEditing.map { CanvasTextFieldRequest(id: $0.id, origin: CGPoint(x: $0.origin.x + padding, y: $0.origin.y + padding)) }
    }

    /// Applies a mouse interaction on the canvas using the active tool.
    func handleCanvasDrag(_ drag: CanvasDrag) {
        guard let activeTool else { return }

        switch drag {
        case .began(let location):
            let point = toScreenshotSpace(location)
            switch activeTool {
            case .counter:
                addAnnotation(.counter(CounterAnnotation(center: point, number: nextCounterNumber, color: annotationColor)))
            case .text:
                textEditing = TextEditingSession(origin: point)
            case .arrow, .rectangle, .pixelate:
                break
            }

        case let .changed(start, location, isConstrained):
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
            case .text, .counter:
                break
            }

        case .ended:
            if let draft, Self.isLargeEnough(draft) {
                addAnnotation(draft)
            }
            draft = nil
        }
    }

    /// Finishes text editing, adding the text unless it's blank.
    func commitText(_ text: String) {
        guard let origin = textEditing?.origin else { return }
        textEditing = nil

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        addAnnotation(.text(TextAnnotation(origin: origin, text: trimmed, color: annotationColor)))
    }

    func addAnnotation(_ annotation: Annotation) {
        annotations.append(annotation)
        redoStack.removeAll()
    }

    func undo() {
        guard canUndo, let last = annotations.popLast() else { return }
        redoStack.append(last)
    }

    func redo() {
        guard canRedo, let next = redoStack.popLast() else { return }
        annotations.append(next)
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

/// One text-typing session; each click with the text tool starts a new one.
struct TextEditingSession {
    let id = UUID()
    /// Top-left of the text, in screenshot space.
    let origin: CGPoint
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
