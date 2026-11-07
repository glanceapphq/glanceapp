import SwiftUI

/// The composition plus the interaction needed to annotate it.
///
/// Kept separate from `CompositionView` so export renders the image without any gesture layers.
struct EditorCanvas: View {
    let model: EditorModel

    var body: some View {
        CompositionView(model: model)
            .overlay {
                if model.activeTool == .arrow {
                    Color.clear
                        .contentShape(.rect)
                        .gesture(arrowGesture)
                        .pointerStyle(.rectSelection)
                }
            }
    }

    private var arrowGesture: some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                // Gesture locations are in canvas space; arrows live in screenshot space.
                let start = toScreenshotSpace(value.startLocation)
                var end = toScreenshotSpace(value.location)
                if NSEvent.modifierFlags.contains(.shift) {
                    end = ArrowAnnotation.snappedEnd(from: start, to: end)
                }
                model.draftArrow = ArrowAnnotation(start: start, end: end, color: model.annotationColor)
            }
            .onEnded { _ in
                if let draft = model.draftArrow, draft.length >= 4 {
                    model.addAnnotation(draft)
                }
                model.draftArrow = nil
            }
    }

    private func toScreenshotSpace(_ point: CGPoint) -> CGPoint {
        CGPoint(x: point.x - model.padding, y: point.y - model.padding)
    }
}
