import AppKit
import SwiftUI

enum RenderError: LocalizedError {
    case renderingFailed
    case encodingFailed

    var errorDescription: String? {
        switch self {
        case .renderingFailed: "Could not render the image."
        case .encodingFailed: "Could not encode the image as PNG."
        }
    }
}

/// A rendered composition ready for export.
struct RenderedImage {
    let pngData: Data
    let tiffData: Data?
}

/// Turns the editor's composition into image data.
///
/// Renders the same `CompositionView` the editor displays, at the screenshot's
/// native scale, so the output matches what's on screen pixel for pixel.
struct RenderService {
    func render(_ model: EditorModel) throws -> RenderedImage {
        let renderer = ImageRenderer(content: CompositionView(model: model))
        renderer.scale = model.screenshot.scale
        renderer.proposedSize = ProposedViewSize(model.canvasSize)

        guard let image = renderer.cgImage else { throw RenderError.renderingFailed }

        let bitmap = NSBitmapImageRep(cgImage: image)
        // Point size sets the PNG's DPI, so Retina captures open at their on-screen size.
        bitmap.size = model.canvasSize
        guard let png = bitmap.representation(using: .png, properties: [:]) else {
            throw RenderError.encodingFailed
        }
        return RenderedImage(pngData: png, tiffData: bitmap.tiffRepresentation)
    }
}
