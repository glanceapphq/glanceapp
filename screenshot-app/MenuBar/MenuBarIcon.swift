import AppKit

/// Glance's mark for the menu bar: an eye inside viewfinder corners, as in the app icon.
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

            // Almond-shaped eye outline.
            let center = CGPoint(x: rect.midX, y: rect.midY)
            let eye = NSBezierPath()
            eye.lineWidth = 1.25
            eye.move(to: CGPoint(x: center.x - 5, y: center.y))
            eye.curve(to: CGPoint(x: center.x + 5, y: center.y), controlPoint1: CGPoint(x: center.x - 2.5, y: center.y - 3.6), controlPoint2: CGPoint(x: center.x + 2.5, y: center.y - 3.6))
            eye.curve(to: CGPoint(x: center.x - 5, y: center.y), controlPoint1: CGPoint(x: center.x + 2.5, y: center.y + 3.6), controlPoint2: CGPoint(x: center.x - 2.5, y: center.y + 3.6))
            eye.close()
            eye.stroke()

            // Iris with a highlight cut out of it.
            let iris: CGFloat = 2.3
            NSBezierPath(ovalIn: CGRect(x: center.x - iris, y: center.y - iris, width: iris * 2, height: iris * 2)).fill()
            NSGraphicsContext.current?.compositingOperation = .clear
            NSBezierPath(ovalIn: CGRect(x: center.x + 0.2, y: center.y - 1.6, width: 1.2, height: 1.2)).fill()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Glance"
        return image
    }
}
