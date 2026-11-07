import SwiftUI

/// What the user picked in the selection overlay.
enum SelectionResult {
    /// An area in the screen's local coordinate space (points, top-left origin).
    case area(CGRect)
    case window(CGWindowID)
}

/// Drag and hover state of the selection overlay.
@Observable
final class SelectionModel {
    var start: CGPoint?
    var current: CGPoint?
    /// Mouse position while not dragging, for highlighting the window under it.
    var hoverLocation: CGPoint?
    /// Windows that can be picked, frontmost first.
    var windows: [SelectableWindow] = []

    var isDragging: Bool { start != nil }

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
}

/// Full-screen overlay: drag out a rectangle to capture an area, or click to capture the window under the pointer.
///
/// Coordinates are local to the view (top-left origin), which matches the
/// screen's local coordinate space because the view fills the whole screen.
struct SelectionView: View {
    let model: SelectionModel
    /// Called once when the user finishes; `nil` means nothing was picked.
    let onComplete: (SelectionResult?) -> Void

    var body: some View {
        GeometryReader { geometry in
            let bounds = CGRect(origin: .zero, size: geometry.size)
            let selection = model.rect?.intersection(bounds)
            let hoveredFrame = model.hoveredWindow?.frame.intersection(bounds)

            ZStack(alignment: .topLeading) {
                DimmingShape(cutout: model.isDragging ? selection : hoveredFrame)
                    .fill(.black.opacity(0.35), style: FillStyle(eoFill: true))

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
                        model.start = value.startLocation
                        model.current = value.location
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
