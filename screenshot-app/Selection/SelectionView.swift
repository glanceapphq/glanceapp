import SwiftUI

/// Drag state of the area selection.
@Observable
final class SelectionModel {
    var start: CGPoint?
    var current: CGPoint?

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
}

/// Full-screen overlay that lets the user drag out a rectangle.
///
/// Coordinates are local to the view (top-left origin), which matches the
/// screen's local coordinate space because the view fills the whole screen.
struct SelectionView: View {
    let model: SelectionModel
    /// Called with the selected rectangle when the drag ends.
    let onSelect: (CGRect) -> Void

    var body: some View {
        GeometryReader { geometry in
            let bounds = CGRect(origin: .zero, size: geometry.size)
            let selection = model.rect?.intersection(bounds)

            ZStack(alignment: .topLeading) {
                DimmingShape(cutout: selection)
                    .fill(.black.opacity(0.35), style: FillStyle(eoFill: true))

                if let selection, !selection.isEmpty {
                    Rectangle()
                        .strokeBorder(.white, lineWidth: 1)
                        .frame(width: selection.width, height: selection.height)
                        .offset(x: selection.minX, y: selection.minY)

                    SizeLabel(size: selection.size)
                        .offset(x: selection.minX, y: labelY(for: selection, in: bounds))
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        model.start = value.startLocation
                        model.current = value.location
                    }
                    .onEnded { _ in
                        onSelect(model.rect?.intersection(bounds) ?? .null)
                    }
            )
        }
        .ignoresSafeArea()
        .pointerStyle(.rectSelection)
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
