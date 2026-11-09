import AppKit
import SwiftUI

/// Annotation tools available in the editor.
enum EditorTool: String, CaseIterable, Identifiable {
    case arrow
    case rectangle
    case text
    case counter
    case pixelate

    var id: String { rawValue }

    var title: String { rawValue.capitalized }

    var systemImage: String {
        switch self {
        case .arrow: "arrow.up.right"
        case .rectangle: "rectangle"
        case .text: "textformat"
        case .counter: "1.circle"
        case .pixelate: "checkerboard.rectangle"
        }
    }

    /// Single-key shortcut that selects the tool.
    var shortcutKey: Character {
        switch self {
        case .arrow: "a"
        case .rectangle: "r"
        case .text: "t"
        case .counter: "n"
        case .pixelate: "p"
        }
    }
}

/// Colors offered for annotations.
nonisolated enum AnnotationColor: String, CaseIterable, Identifiable, Sendable {
    case red, orange, yellow, green, blue, white

    var id: String { rawValue }

    var color: Color {
        switch self {
        case .red: Color(hex: 0xFF3B30)
        case .orange: Color(hex: 0xFF9500)
        case .yellow: Color(hex: 0xFFCC00)
        case .green: Color(hex: 0x34C759)
        case .blue: Color(hex: 0x007AFF)
        case .white: .white
        }
    }

    /// Readable color for text drawn on top of this color.
    var contrastingColor: Color {
        switch self {
        case .yellow, .white: .black
        default: .white
        }
    }
}

// MARK: - Annotation types

/// Everything that can be drawn on a screenshot.
///
/// All geometry is in screenshot coordinates (points, origin at the screenshot's
/// top-left), so annotations stay attached to the same content when padding changes.
nonisolated enum Annotation: Identifiable, Sendable {
    case arrow(ArrowAnnotation)
    case rectangle(RectangleAnnotation)
    case text(TextAnnotation)
    case counter(CounterAnnotation)
    case pixelate(PixelateAnnotation)

    var id: UUID {
        switch self {
        case .arrow(let arrow): arrow.id
        case .rectangle(let rectangle): rectangle.id
        case .text(let text): text.id
        case .counter(let counter): counter.id
        case .pixelate(let pixelate): pixelate.id
        }
    }
}

/// A vector arrow from `start` to `end`.
nonisolated struct ArrowAnnotation: Identifiable, Sendable {
    let id = UUID()
    var start: CGPoint
    var end: CGPoint
    var color: AnnotationColor
    var lineWidth: CGFloat = 6

    var length: CGFloat {
        hypot(end.x - start.x, end.y - start.y)
    }

    /// Filled outline: a shaft tapering from the tail towards the head, plus a triangular head.
    var path: Path {
        let length = self.length
        guard length > 0 else { return Path() }

        let direction = CGPoint(x: (end.x - start.x) / length, y: (end.y - start.y) / length)
        let normal = CGPoint(x: -direction.y, y: direction.x)

        let headLength = min(max(lineWidth * 3.5, 14), length)
        let headHalfWidth = headLength * 0.45
        let tailHalfWidth = lineWidth * 0.2
        let shaftHalfWidth = lineWidth * 0.5

        let base = CGPoint(x: end.x - direction.x * headLength, y: end.y - direction.y * headLength)

        func offset(_ point: CGPoint, by distance: CGFloat) -> CGPoint {
            CGPoint(x: point.x + normal.x * distance, y: point.y + normal.y * distance)
        }

        var path = Path()
        path.move(to: offset(start, by: tailHalfWidth))
        path.addLine(to: offset(base, by: shaftHalfWidth))
        path.addLine(to: offset(base, by: headHalfWidth))
        path.addLine(to: end)
        path.addLine(to: offset(base, by: -headHalfWidth))
        path.addLine(to: offset(base, by: -shaftHalfWidth))
        path.addLine(to: offset(start, by: -tailHalfWidth))
        path.closeSubpath()
        return path
    }

    /// Returns `end` rotated around `start` to the nearest multiple of 45°.
    static func snappedEnd(from start: CGPoint, to end: CGPoint) -> CGPoint {
        let step = CGFloat.pi / 4
        let angle = (atan2(end.y - start.y, end.x - start.x) / step).rounded() * step
        let length = hypot(end.x - start.x, end.y - start.y)
        return CGPoint(x: start.x + cos(angle) * length, y: start.y + sin(angle) * length)
    }
}

/// An outlined rectangle.
nonisolated struct RectangleAnnotation: Identifiable, Sendable {
    let id = UUID()
    var rect: CGRect
    var color: AnnotationColor
    var lineWidth: CGFloat = 4

    var path: Path {
        Path(roundedRect: rect, cornerRadius: 4)
    }
}

/// A single line of text whose top-left corner is at `origin`.
nonisolated struct TextAnnotation: Identifiable, Sendable {
    static let defaultFontSize: CGFloat = 24
    static let fontSizeRange: ClosedRange<CGFloat> = 10...200

    let id = UUID()
    var origin: CGPoint
    var text: String
    var color: AnnotationColor
    var fontSize: CGFloat = Self.defaultFontSize
}

/// A numbered badge centered at `center`, for marking steps.
nonisolated struct CounterAnnotation: Identifiable, Sendable {
    static let defaultDiameter: CGFloat = 28
    static let diameterRange: ClosedRange<CGFloat> = 16...200

    let id = UUID()
    var center: CGPoint
    var number: Int
    var color: AnnotationColor
    var diameter: CGFloat = Self.defaultDiameter

    var circle: Path {
        let radius = diameter / 2
        return Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: diameter, height: diameter))
    }

    /// Font size of the number, proportional to the badge.
    var fontSize: CGFloat { diameter * 15 / 28 }
}

/// An area of the screenshot hidden behind large pixels.
nonisolated struct PixelateAnnotation: Identifiable, Sendable {
    let id = UUID()
    var rect: CGRect
}

// MARK: - Editing geometry

nonisolated extension Annotation {
    /// Area the annotation covers, in screenshot space.
    var bounds: CGRect {
        switch self {
        case .arrow(let arrow):
            arrow.path.boundingRect
        case .rectangle(let rectangle):
            rectangle.rect.insetBy(dx: -rectangle.lineWidth / 2, dy: -rectangle.lineWidth / 2)
        case .text(let text):
            CGRect(origin: text.origin, size: text.size)
        case .counter(let counter):
            counter.circle.boundingRect
        case .pixelate(let pixelate):
            pixelate.rect
        }
    }

    /// Whether `point` (screenshot space) hits the annotation.
    ///
    /// - Parameters:
    ///   - tolerance: Extra slack around thin shapes, in points.
    ///   - includeInterior: Whether the inside of outlined shapes (rectangle, pixelate) counts.
    ///     When `false` only their edges do, so new annotations can be drawn inside them.
    func contains(_ point: CGPoint, tolerance: CGFloat, includeInterior: Bool) -> Bool {
        switch self {
        case .arrow(let arrow):
            return point.distance(toSegmentFrom: arrow.start, to: arrow.end) <= arrow.lineWidth / 2 + tolerance
        case .rectangle(let rectangle):
            return Self.outline(rectangle.rect, contains: point, halfWidth: rectangle.lineWidth / 2 + tolerance, includeInterior: includeInterior)
        case .pixelate(let pixelate):
            return Self.outline(pixelate.rect, contains: point, halfWidth: tolerance, includeInterior: includeInterior)
        case .text, .counter:
            return bounds.insetBy(dx: -tolerance, dy: -tolerance).contains(point)
        }
    }

    /// The same annotation moved by `offset`.
    func offset(by offset: CGSize) -> Annotation {
        func move(_ point: CGPoint) -> CGPoint {
            CGPoint(x: point.x + offset.width, y: point.y + offset.height)
        }

        switch self {
        case .arrow(var arrow):
            arrow.start = move(arrow.start)
            arrow.end = move(arrow.end)
            return .arrow(arrow)
        case .rectangle(var rectangle):
            rectangle.rect = rectangle.rect.offsetBy(dx: offset.width, dy: offset.height)
            return .rectangle(rectangle)
        case .text(var text):
            text.origin = move(text.origin)
            return .text(text)
        case .counter(var counter):
            counter.center = move(counter.center)
            return .counter(counter)
        case .pixelate(var pixelate):
            pixelate.rect = pixelate.rect.offsetBy(dx: offset.width, dy: offset.height)
            return .pixelate(pixelate)
        }
    }

    /// The same annotation in `color`, or `nil` if it has no color (pixelate).
    func recolored(_ color: AnnotationColor) -> Annotation? {
        switch self {
        case .arrow(var arrow):
            arrow.color = color
            return .arrow(arrow)
        case .rectangle(var rectangle):
            rectangle.color = color
            return .rectangle(rectangle)
        case .text(var text):
            text.color = color
            return .text(text)
        case .counter(var counter):
            counter.color = color
            return .counter(counter)
        case .pixelate:
            return nil
        }
    }

    /// Handles offered for resizing the annotation.
    var handles: [AnnotationHandle] {
        switch self {
        case .arrow: [.start, .end]
        case .rectangle, .pixelate: [.topLeft, .top, .topRight, .right, .bottomRight, .bottom, .bottomLeft, .left]
        case .text, .counter: [.bottomRight]
        }
    }

    /// The same annotation after dragging `handle` by `offset`.
    ///
    /// Works from the drag offset rather than the pointer location, so grabbing a handle
    /// slightly off its center doesn't make the shape jump.
    ///
    /// - Parameter constrained: Snaps arrows to 45° and keeps rectangles square (corner handles only).
    func resized(_ handle: AnnotationHandle, by offset: CGSize, constrained: Bool) -> Annotation {
        switch self {
        case .arrow(var arrow):
            func moved(_ point: CGPoint, around anchor: CGPoint) -> CGPoint {
                let point = CGPoint(x: point.x + offset.width, y: point.y + offset.height)
                return constrained ? ArrowAnnotation.snappedEnd(from: anchor, to: point) : point
            }
            switch handle {
            case .start: arrow.start = moved(arrow.start, around: arrow.end)
            case .end: arrow.end = moved(arrow.end, around: arrow.start)
            default: break
            }
            return .arrow(arrow)

        case .rectangle(var rectangle):
            rectangle.rect = rectangle.rect.resized(handle, by: offset, square: constrained)
            return .rectangle(rectangle)

        case .pixelate(var pixelate):
            pixelate.rect = pixelate.rect.resized(handle, by: offset, square: constrained)
            return .pixelate(pixelate)

        case .text(var text):
            // Scale the font so the text's corner follows the pointer.
            let size = text.size
            guard size.width > 0, size.height > 0 else { return self }
            let ratio = max((size.width + offset.width) / size.width, (size.height + offset.height) / size.height)
            text.fontSize = (text.fontSize * ratio).clamped(to: TextAnnotation.fontSizeRange)
            return .text(text)

        case .counter(var counter):
            // The badge grows around its center, so the corner moves by the change in radius.
            counter.diameter = (counter.diameter + 2 * max(offset.width, offset.height)).clamped(to: CounterAnnotation.diameterRange)
            return .counter(counter)
        }
    }

    private static func outline(_ rect: CGRect, contains point: CGPoint, halfWidth: CGFloat, includeInterior: Bool) -> Bool {
        let outer = rect.insetBy(dx: -halfWidth, dy: -halfWidth)
        guard outer.contains(point) else { return false }
        if includeInterior { return true }
        let inner = rect.insetBy(dx: halfWidth, dy: halfWidth)
        return inner.isNull || !inner.contains(point)
    }
}

/// A point on an annotation that can be dragged to resize it.
nonisolated enum AnnotationHandle: Sendable {
    /// Arrow endpoints.
    case start, end
    /// Points on the selection frame.
    case topLeft, top, topRight, right, bottomRight, bottom, bottomLeft, left
}

nonisolated extension TextAnnotation {
    /// Rendered size of the text (bold system font, matching `AnnotationLayer`).
    var size: CGSize {
        let font = NSFont.systemFont(ofSize: fontSize, weight: .bold)
        return (text as NSString).size(withAttributes: [.font: font])
    }
}

nonisolated extension CGPoint {
    /// Shortest distance from this point to the segment `a`–`b`.
    func distance(toSegmentFrom a: CGPoint, to b: CGPoint) -> CGFloat {
        let dx = b.x - a.x
        let dy = b.y - a.y
        let lengthSquared = dx * dx + dy * dy
        guard lengthSquared > 0 else { return hypot(x - a.x, y - a.y) }

        let t = (((x - a.x) * dx + (y - a.y) * dy) / lengthSquared).clamped(to: 0...1)
        return hypot(x - (a.x + t * dx), y - (a.y + t * dy))
    }
}

extension CGRect {
    /// Rectangle spanning two corner points; `square` makes it a square along the longer side.
    nonisolated init(corner start: CGPoint, to end: CGPoint, square: Bool = false) {
        var width = end.x - start.x
        var height = end.y - start.y
        if square {
            let side = max(abs(width), abs(height))
            width = width < 0 ? -side : side
            height = height < 0 ? -side : side
        }
        self = CGRect(x: start.x, y: start.y, width: width, height: height).standardized
    }
}

nonisolated extension CGRect {
    /// Position of a frame handle on this rectangle.
    func point(for handle: AnnotationHandle) -> CGPoint {
        switch handle {
        case .topLeft: CGPoint(x: minX, y: minY)
        case .top: CGPoint(x: midX, y: minY)
        case .topRight: CGPoint(x: maxX, y: minY)
        case .right: CGPoint(x: maxX, y: midY)
        case .bottomRight: CGPoint(x: maxX, y: maxY)
        case .bottom: CGPoint(x: midX, y: maxY)
        case .bottomLeft: CGPoint(x: minX, y: maxY)
        case .left: CGPoint(x: minX, y: midY)
        case .start, .end: CGPoint(x: midX, y: midY)
        }
    }

    /// The rectangle with the edges under `handle` moved by `offset`. Dragging past the
    /// opposite edge flips it; `square` keeps corner drags square.
    func resized(_ handle: AnnotationHandle, by offset: CGSize, square: Bool) -> CGRect {
        var left = minX, right = maxX, top = minY, bottom = maxY

        switch handle {
        case .topLeft, .left, .bottomLeft: left += offset.width
        case .topRight, .right, .bottomRight: right += offset.width
        default: break
        }
        switch handle {
        case .topLeft, .top, .topRight: top += offset.height
        case .bottomLeft, .bottom, .bottomRight: bottom += offset.height
        default: break
        }

        switch handle {
        case .topLeft: return CGRect(corner: CGPoint(x: maxX, y: maxY), to: CGPoint(x: left, y: top), square: square)
        case .topRight: return CGRect(corner: CGPoint(x: minX, y: maxY), to: CGPoint(x: right, y: top), square: square)
        case .bottomRight: return CGRect(corner: CGPoint(x: minX, y: minY), to: CGPoint(x: right, y: bottom), square: square)
        case .bottomLeft: return CGRect(corner: CGPoint(x: maxX, y: minY), to: CGPoint(x: left, y: bottom), square: square)
        default: return CGRect(corner: CGPoint(x: left, y: top), to: CGPoint(x: right, y: bottom))
        }
    }
}

// MARK: - Rendering

/// Draws vector annotations (everything except pixelation) over the composition.
struct AnnotationLayer: View {
    let annotations: [Annotation]
    /// Position of the screenshot's top-left corner within the layer.
    let origin: CGPoint

    var body: some View {
        Canvas { context, _ in
            context.translateBy(x: origin.x, y: origin.y)
            context.addFilter(.shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 1))

            for annotation in annotations {
                switch annotation {
                case .arrow(let arrow):
                    context.fill(arrow.path, with: .color(arrow.color.color))

                case .rectangle(let rectangle):
                    context.stroke(rectangle.path, with: .color(rectangle.color.color), lineWidth: rectangle.lineWidth)

                case .text(let text):
                    let label = Text(text.text)
                        .font(.system(size: text.fontSize, weight: .bold))
                        .foregroundStyle(text.color.color)
                    context.draw(label, at: text.origin, anchor: .topLeading)

                case .counter(let counter):
                    context.fill(counter.circle, with: .color(counter.color.color))
                    let label = Text("\(counter.number)")
                        .font(.system(size: counter.fontSize, weight: .bold).monospacedDigit())
                        .foregroundStyle(counter.color.contrastingColor)
                    context.draw(label, at: counter.center, anchor: .center)

                case .pixelate:
                    // Drawn by `PixelationLayer`, underneath everything else.
                    break
                }
            }
        }
        .allowsHitTesting(false)
    }
}

/// Shows the pixelated screenshot only inside `rects`. Sized and positioned like the screenshot.
struct PixelationLayer: View {
    let pixelatedImage: CGImage
    let scale: CGFloat
    let rects: [CGRect]

    var body: some View {
        Image(decorative: pixelatedImage, scale: scale)
            .mask { RectsShape(rects: rects) }
            .allowsHitTesting(false)
    }
}

private nonisolated struct RectsShape: Shape {
    let rects: [CGRect]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addRects(rects)
        return path
    }
}

/// Creates pixelated copies of screenshots for `PixelateAnnotation`.
nonisolated enum Pixelator {
    /// Returns `image` made of square blocks `blockSize` pixels wide, each the average color of its area.
    ///
    /// Averages by downscaling with high-quality interpolation, then upscales without interpolation.
    /// (`CIPixellate` samples one pixel per block instead, which lets thin text vanish or flicker.)
    static func pixelate(_ image: CGImage, blockSize: CGFloat) -> CGImage? {
        let block = max(Int(blockSize.rounded()), 1)
        let width = image.width
        let height = image.height
        let smallWidth = (width + block - 1) / block
        let smallHeight = (height + block - 1) / block

        let colorSpace = image.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue

        guard let small = CGContext(data: nil, width: smallWidth, height: smallHeight, bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace, bitmapInfo: bitmapInfo),
              let large = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace, bitmapInfo: bitmapInfo)
        else { return nil }

        small.interpolationQuality = .high
        small.draw(image, in: CGRect(x: 0, y: 0, width: smallWidth, height: smallHeight))
        guard let smallImage = small.makeImage() else { return nil }

        large.interpolationQuality = .none
        // Anchor the block grid at the top-left; partial blocks fall off the bottom/right edges.
        let gridHeight = smallHeight * block
        large.draw(smallImage, in: CGRect(x: 0, y: height - gridHeight, width: smallWidth * block, height: gridHeight))
        return large.makeImage()
    }
}
