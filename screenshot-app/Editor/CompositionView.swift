import SwiftUI

/// The final image: background, padding, the screenshot with rounded corners and a soft shadow, and annotations.
///
/// Drawn at 1 point = 1 screenshot point. The editor shows it inside a zoomable
/// scroll view, and export renders the very same view, so what you see is what you get.
struct CompositionView: View {
    let model: EditorModel

    var body: some View {
        let screenshot = model.screenshot
        let pixelatedRects = model.pixelatedRects

        Image(decorative: screenshot.image, scale: screenshot.scale)
            .overlay {
                if !pixelatedRects.isEmpty, let pixelated = model.pixelatedScreenshot {
                    PixelationLayer(pixelatedImage: pixelated, scale: screenshot.scale, rects: pixelatedRects)
                }
            }
            .clipShape(.rect(cornerRadius: model.cornerRadius))
            // Flatten first: `.shadow` otherwise shadows each layer separately, including the pixelation overlay.
            .compositingGroup()
            .shadow(color: .black.opacity(0.3), radius: 20, x: 0, y: 10)
            .padding(model.padding)
            .frame(width: model.canvasSize.width, height: model.canvasSize.height)
            .background {
                if let style = model.background.style {
                    Rectangle().fill(style)
                }
            }
            .overlay {
                AnnotationLayer(
                    annotations: model.visibleAnnotations,
                    origin: CGPoint(x: model.padding, y: model.padding)
                )
            }
            .clipped()
    }
}
