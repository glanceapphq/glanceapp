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
    private(set) var annotations: [ArrowAnnotation] = []
    /// The arrow currently being dragged out, not yet committed.
    var draftArrow: ArrowAnnotation?
    private var redoStack: [ArrowAnnotation] = []

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

    var canUndo: Bool { !annotations.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    /// Turns a drag on the canvas into a draft arrow, committing it when the drag ends.
    func handleCanvasDrag(_ drag: CanvasDrag) {
        guard activeTool == .arrow else { return }

        switch drag {
        case let .changed(start, location, isConstrained):
            let start = toScreenshotSpace(start)
            var end = toScreenshotSpace(location)
            if isConstrained {
                end = ArrowAnnotation.snappedEnd(from: start, to: end)
            }
            draftArrow = ArrowAnnotation(start: start, end: end, color: annotationColor)

        case .ended:
            // Ignore clicks and tiny accidental drags.
            if let draftArrow, draftArrow.length >= 4 {
                addAnnotation(draftArrow)
            }
            draftArrow = nil
        }
    }

    func addAnnotation(_ arrow: ArrowAnnotation) {
        annotations.append(arrow)
        redoStack.removeAll()
    }

    func undo() {
        guard let last = annotations.popLast() else { return }
        redoStack.append(last)
    }

    func redo() {
        guard let next = redoStack.popLast() else { return }
        annotations.append(next)
    }

    // MARK: Zoom

    func zoomIn() { setZoom(zoom * 1.25) }
    func zoomOut() { setZoom(zoom / 1.25) }
    func zoomToActualSize() { setZoom(1) }
    func zoomToFit() { zoomToFitRequest += 1 }

    /// Canvas points → screenshot points (arrows are stored relative to the screenshot).
    private func toScreenshotSpace(_ point: CGPoint) -> CGPoint {
        CGPoint(x: point.x - padding, y: point.y - padding)
    }

    private func setZoom(_ value: CGFloat) {
        zoom = value.clamped(to: Self.zoomRange)
    }
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
