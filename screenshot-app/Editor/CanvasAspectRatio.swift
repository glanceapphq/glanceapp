import CoreGraphics

/// Shape of the composition, so the exported image fits a social feed without being cropped.
///
/// Raw values are stored in `UserDefaults`; don't change them.
enum CanvasAspectRatio: String, CaseIterable, Identifiable {
    /// Screenshot plus padding on every side, whatever shape that makes.
    case auto
    case widescreen = "16:9"
    case square = "1:1"
    case portrait = "4:5"
    case story = "9:16"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .auto: "Auto"
        default: rawValue
        }
    }

    /// Width divided by height, or `nil` for `auto`.
    var widthToHeight: CGFloat? {
        switch self {
        case .auto: nil
        case .widescreen: 16 / 9
        case .square: 1
        case .portrait: 4 / 5
        case .story: 9 / 16
        }
    }
}

/// Size of the canvas and where the screenshot sits on it.
///
/// Kept separate from `EditorModel` so the geometry is a pure calculation that tests can check directly.
struct CanvasLayout: Equatable {
    /// Size of the whole composition, in points.
    let size: CGSize
    /// Top-left corner of the screenshot within the canvas, in points.
    let screenshotOrigin: CGPoint

    /// - Parameter scale: Pixels per point of the export. Ratio canvases are rounded to whole pixels,
    ///   so the screenshot never lands between two pixels and turns blurry.
    init(screenshotSize: CGSize, padding: CGFloat, aspectRatio: CanvasAspectRatio, scale: CGFloat) {
        // The smallest canvas: today's "Auto" output.
        let content = CGSize(width: screenshotSize.width + padding * 2, height: screenshotSize.height + padding * 2)

        var size = content
        if let ratio = aspectRatio.widthToHeight {
            // Grow (never shrink) whichever side is too short for the ratio.
            if content.width / content.height < ratio {
                size.width = Self.roundedUp(content.height * ratio, scale: scale)
            } else {
                size.height = Self.roundedUp(content.width / ratio, scale: scale)
            }
        }

        // Split the extra space evenly; for Auto it's zero, so the origin is exactly the padding.
        let extra = CGSize(width: size.width - content.width, height: size.height - content.height)
        self.size = size
        self.screenshotOrigin = CGPoint(
            x: padding + Self.roundedDown(extra.width / 2, scale: scale),
            y: padding + Self.roundedDown(extra.height / 2, scale: scale)
        )
    }

    private static func roundedUp(_ value: CGFloat, scale: CGFloat) -> CGFloat {
        (value * scale).rounded(.up) / scale
    }

    private static func roundedDown(_ value: CGFloat, scale: CGFloat) -> CGFloat {
        (value * scale).rounded(.down) / scale
    }
}
