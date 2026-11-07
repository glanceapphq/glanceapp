import AppKit
import SwiftUI

/// What the user picked in the selection overlay.
enum SelectionResult {
    /// An area in the screen's local coordinate space (points, top-left origin).
    case area(CGRect)
    case window(CGWindowID)
}

/// Drag, hover and snapping state of the selection overlay.
@Observable
final class SelectionModel {
    /// Distance within which selection edges snap to window and screen edges.
    static let snapDistance: CGFloat = 6

    var start: CGPoint?
    var current: CGPoint?
    /// Mouse position while not dragging, for highlighting the window under it.
    var hoverLocation: CGPoint?
    /// Edges the dragged corner is currently snapped to, shown as guides.
    private(set) var snappedX: CGFloat?
    private(set) var snappedY: CGFloat?

    /// Windows that can be picked, frontmost first.
    var windows: [SelectableWindow] = [] {
        didSet { updateSnapEdges() }
    }
    /// Size of the screen, whose edges are snap targets too.
    var screenSize: CGSize = .zero {
        didSet { updateSnapEdges() }
    }

    @ObservationIgnored private var snapEdgesX: [CGFloat] = []
    @ObservationIgnored private var snapEdgesY: [CGFloat] = []

    var isDragging: Bool { start != nil }

    /// Where the pointer is: the dragged corner while dragging, otherwise the hover location.
    var pointerLocation: CGPoint? { isDragging ? current : hoverLocation }

    /// Normalized selection rectangle in view coordinates, snapped to whole points.
    var rect: CGRect? {
        guard let start, let current else { return nil }
        return CGRect(
            x: min(start.x, current.x),
            y: min(start.y, current.y),
            width: abs(current.x - start.x),
            height: abs(current.y - start.y)
        ).integral
    }

    /// The window that a click would capture, if any.
    var hoveredWindow: SelectableWindow? {
        guard !isDragging, let hoverLocation else { return nil }
        return window(at: hoverLocation)
    }

    /// Frontmost window containing `point`.
    func window(at point: CGPoint) -> SelectableWindow? {
        windows.first { $0.frame.contains(point) }
    }

    /// Updates the drag, snapping both corners to nearby edges unless `snapping` is off.
    func drag(from start: CGPoint, to location: CGPoint, snapping: Bool) {
        if snapping {
            self.start = CGPoint(x: snap(start.x, to: snapEdgesX) ?? start.x, y: snap(start.y, to: snapEdgesY) ?? start.y)
            snappedX = snap(location.x, to: snapEdgesX)
            snappedY = snap(location.y, to: snapEdgesY)
            current = CGPoint(x: snappedX ?? location.x, y: snappedY ?? location.y)
        } else {
            self.start = start
            current = location
            snappedX = nil
            snappedY = nil
        }
    }

    private func snap(_ value: CGFloat, to edges: [CGFloat]) -> CGFloat? {
        edges
            .filter { abs($0 - value) <= Self.snapDistance }
            .min { abs($0 - value) < abs($1 - value) }
    }

    private func updateSnapEdges() {
        let frames = windows.map(\.frame)
        snapEdgesX = [0, screenSize.width] + frames.flatMap { [$0.minX, $0.maxX] }
        snapEdgesY = [0, screenSize.height] + frames.flatMap { [$0.minY, $0.maxY] }
    }
}

/// Full-screen overlay over a frozen screenshot: drag out a rectangle to capture an area,
/// or click to capture the window under the pointer.
///
/// Coordinates are local to the view (top-left origin), which matches the
/// screen's local coordinate space because the view fills the whole screen.
struct SelectionView: View {
    let model: SelectionModel
    /// The screen as it was when capture started, shown underneath everything.
    let frozenScreen: Screenshot
    /// Called once when the user finishes; `nil` means nothing was picked.
    let onComplete: (SelectionResult?) -> Void

    var body: some View {
        GeometryReader { geometry in
            let bounds = CGRect(origin: .zero, size: geometry.size)
            let selection = model.rect?.intersection(bounds)
            let hoveredFrame = model.hoveredWindow?.frame.intersection(bounds)

            ZStack(alignment: .topLeading) {
                Image(decorative: frozenScreen.image, scale: frozenScreen.scale)

                DimmingShape(cutout: model.isDragging ? selection : hoveredFrame)
                    .fill(.black.opacity(0.35), style: FillStyle(eoFill: true))

                if model.isDragging {
                    SnapGuides(x: model.snappedX, y: model.snappedY)
                } else if let location = model.hoverLocation {
                    Crosshair(location: location)
                }

                if let selection, !selection.isEmpty {
                    Rectangle()
                        .strokeBorder(.white, lineWidth: 1)
                        .frame(width: selection.width, height: selection.height)
                        .offset(x: selection.minX, y: selection.minY)

                    SizeLabel(size: selection.size)
                        .offset(x: selection.minX, y: labelY(for: selection, in: bounds))
                } else if let hoveredFrame, !hoveredFrame.isEmpty {
                    Rectangle()
                        .fill(Color.accentColor.opacity(0.12))
                        .strokeBorder(Color.accentColor, lineWidth: 2)
                        .frame(width: hoveredFrame.width, height: hoveredFrame.height)
                        .offset(x: hoveredFrame.minX, y: hoveredFrame.minY)
                }

                if let location = model.pointerLocation {
                    Magnifier(screenshot: frozenScreen, location: location)
                        .offset(Magnifier.offset(for: location, in: bounds))
                }
            }
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                switch phase {
                case .active(let location): model.hoverLocation = location
                case .ended: model.hoverLocation = nil
                }
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        // Hold Option to place edges freely, without snapping.
                        let snapping = !NSEvent.modifierFlags.contains(.option)
                        model.drag(from: value.startLocation, to: value.location, snapping: snapping)
                    }
                    .onEnded { value in
                        onComplete(result(endingAt: value, in: bounds))
                    }
            )
        }
        .ignoresSafeArea()
        .pointerStyle(.rectSelection)
    }

    /// A real drag selects an area; a click (or tiny drag) picks the window under it.
    private func result(endingAt value: DragGesture.Value, in bounds: CGRect) -> SelectionResult? {
        if let rect = model.rect?.intersection(bounds), rect.width >= 4, rect.height >= 4 {
            return .area(rect)
        }
        if let window = model.window(at: value.startLocation) {
            return .window(window.id)
        }
        return nil
    }

    /// Places the size label below the selection, or inside it near the screen's bottom edge.
    private func labelY(for selection: CGRect, in bounds: CGRect) -> CGFloat {
        let below = selection.maxY + 6
        return below + 24 > bounds.maxY ? selection.maxY - 30 : below
    }
}

/// Covers the whole area except `cutout` (when filled with the even-odd rule).
/// `Shape` is nonisolated (paths may be computed off the main thread), so opt out of default MainActor isolation.
private nonisolated struct DimmingShape: Shape {
    let cutout: CGRect?

    func path(in rect: CGRect) -> Path {
        var path = Path(rect)
        if let cutout { path.addRect(cutout) }
        return path
    }
}

/// Full-screen horizontal and vertical lines through the pointer.
private struct Crosshair: View {
    let location: CGPoint

    var body: some View {
        Canvas { context, size in
            var path = Path()
            path.move(to: CGPoint(x: location.x, y: 0))
            path.addLine(to: CGPoint(x: location.x, y: size.height))
            path.move(to: CGPoint(x: 0, y: location.y))
            path.addLine(to: CGPoint(x: size.width, y: location.y))
            // Dark under light keeps the lines visible on any background.
            context.stroke(path, with: .color(.black.opacity(0.35)), lineWidth: 2)
            context.stroke(path, with: .color(.white.opacity(0.7)), lineWidth: 1)
        }
        .allowsHitTesting(false)
    }
}

/// Full-screen guides along the edges the selection corner is snapped to.
private struct SnapGuides: View {
    let x: CGFloat?
    let y: CGFloat?

    var body: some View {
        Canvas { context, size in
            var path = Path()
            if let x {
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))
            }
            if let y {
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
            }
            context.stroke(path, with: .color(.accentColor), style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
        }
        .allowsHitTesting(false)
    }
}

/// Zoomed-in view of the pixels around the pointer, with the pointer's coordinates.
private struct Magnifier: View {
    /// Pixels shown along each side; odd so one pixel sits exactly in the center.
    static let pixelCount = 21
    static let cellSize: CGFloat = 6
    static let loupeSize = CGFloat(pixelCount) * cellSize
    private static let gap: CGFloat = 24
    private static let labelHeight: CGFloat = 22

    let screenshot: Screenshot
    let location: CGPoint

    var body: some View {
        VStack(spacing: 4) {
            if let sample = sample() {
                Image(decorative: sample.image, scale: 1)
                    .resizable()
                    .interpolation(.none)
                    .frame(width: Self.loupeSize, height: Self.loupeSize)
                    .overlay(alignment: .topLeading) {
                        // Outline the pixel under the pointer.
                        Rectangle()
                            .strokeBorder(.white, lineWidth: 1)
                            .background(Rectangle().strokeBorder(.black.opacity(0.6), lineWidth: 2))
                            .frame(width: Self.cellSize, height: Self.cellSize)
                            .offset(x: CGFloat(sample.center.x) * Self.cellSize, y: CGFloat(sample.center.y) * Self.cellSize)
                    }
                    .clipShape(.rect(cornerRadius: 10))
                    .overlay {
                        RoundedRectangle(cornerRadius: 10).strokeBorder(.white.opacity(0.8), lineWidth: 1.5)
                    }
                    // Flatten first so the shadow is cast by the loupe as a whole, not by each layer.
                    .compositingGroup()
                    .shadow(color: .black.opacity(0.4), radius: 8, y: 3)
            }

            Text("\(Int(location.x)), \(Int(location.y))")
                .font(.system(size: 11, weight: .medium).monospacedDigit())
                .foregroundStyle(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(.black.opacity(0.7), in: .rect(cornerRadius: 4))
                .frame(height: Self.labelHeight)
        }
        .frame(width: Self.loupeSize)
        .allowsHitTesting(false)
    }

    /// Pixels around the pointer, plus the pointer's pixel within them. The window
    /// is clamped inside the image, so near edges the pointer pixel moves off-center.
    private func sample() -> (image: CGImage, center: (x: Int, y: Int))? {
        let image = screenshot.image
        let count = Self.pixelCount
        guard image.width >= count, image.height >= count else { return nil }

        let pixelX = min(max(Int(location.x * screenshot.scale), 0), image.width - 1)
        let pixelY = min(max(Int(location.y * screenshot.scale), 0), image.height - 1)
        let originX = min(max(pixelX - count / 2, 0), image.width - count)
        let originY = min(max(pixelY - count / 2, 0), image.height - count)

        guard let cropped = image.cropping(to: CGRect(x: originX, y: originY, width: count, height: count)) else { return nil }
        return (cropped, (pixelX - originX, pixelY - originY))
    }

    /// Below-right of the pointer, flipped to the other side near screen edges.
    static func offset(for location: CGPoint, in bounds: CGRect) -> CGSize {
        let height = loupeSize + 4 + labelHeight
        var x = location.x + gap
        var y = location.y + gap
        if x + loupeSize > bounds.maxX { x = location.x - gap - loupeSize }
        if y + height > bounds.maxY { y = location.y - gap - height }
        return CGSize(width: x, height: y)
    }
}

private struct SizeLabel: View {
    let size: CGSize

    var body: some View {
        Text("\(Int(size.width)) × \(Int(size.height))")
            .font(.system(size: 11, weight: .medium).monospacedDigit())
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(.black.opacity(0.7), in: .rect(cornerRadius: 4))
    }
}
