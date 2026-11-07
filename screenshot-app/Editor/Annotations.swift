import SwiftUI

/// Annotation tools available in the editor.
enum EditorTool {
    case arrow
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
}

/// A vector arrow in screenshot coordinates (points, origin at the screenshot's top-left),
/// so it stays attached to the same content when padding changes.
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

/// Draws arrows over the composition.
struct AnnotationLayer: View {
    let arrows: [ArrowAnnotation]
    /// Position of the screenshot's top-left corner within the layer.
    let origin: CGPoint

    var body: some View {
        Canvas { context, _ in
            context.translateBy(x: origin.x, y: origin.y)
            context.addFilter(.shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 1))
            for arrow in arrows {
                context.fill(arrow.path, with: .color(arrow.color.color))
            }
        }
        .allowsHitTesting(false)
    }
}
