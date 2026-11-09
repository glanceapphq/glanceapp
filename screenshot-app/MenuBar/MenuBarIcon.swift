import AppKit

/// Glance's mark for the menu bar: a focus dot inside viewfinder corners, as in the app icon.
///
/// Drawn in code as a template image, so the menu bar tints it for light and dark
/// appearances and it stays sharp at any scale.
enum MenuBarIcon {
    static func make() -> NSImage {
        let image = NSImage(size: CGSize(width: 18, height: 18), flipped: true) { rect in
            NSColor.black.set()

            // Viewfinder corners.
            let frame = rect.insetBy(dx: 1.75, dy: 1.75)
            let arm: CGFloat = 4.25
            let corners = NSBezierPath()
            corners.lineWidth = 1.5
            corners.lineCapStyle = .round
            corners.lineJoinStyle = .round
            for (corner, horizontal, vertical) in [
                (CGPoint(x: frame.minX, y: frame.minY), arm, arm),
                (CGPoint(x: frame.maxX, y: frame.minY), -arm, arm),
                (CGPoint(x: frame.maxX, y: frame.maxY), -arm, -arm),
                (CGPoint(x: frame.minX, y: frame.maxY), arm, -arm),
            ] {
                corners.move(to: CGPoint(x: corner.x, y: corner.y + vertical))
                corners.line(to: corner)
                corners.line(to: CGPoint(x: corner.x + horizontal, y: corner.y))
            }
            corners.stroke()

            // Focus dot in the centre.
            let center = CGPoint(x: rect.midX, y: rect.midY)
            let dot: CGFloat = 2.4
            NSBezierPath(ovalIn: CGRect(x: center.x - dot, y: center.y - dot, width: dot * 2, height: dot * 2)).fill()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Glance"
        return image
    }
}
