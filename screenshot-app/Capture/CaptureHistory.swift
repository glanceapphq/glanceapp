import AppKit
import ImageIO
import UniformTypeIdentifiers

/// Recent captures, newest first, so they can be reopened from the menu bar.
///
/// Kept in memory only and gone when the app quits: nothing is written to disk
/// unless the user saves. Images are compressed to PNG in the background, so a
/// full history of Retina screenshots stays small.
final class CaptureHistory {
    static let limit = 10

    private(set) var entries: [CaptureHistoryEntry] = []

    /// Records a new capture and returns its entry.
    func add(_ screenshot: Screenshot) -> CaptureHistoryEntry {
        let entry = CaptureHistoryEntry(screenshot: screenshot)
        entries.insert(entry, at: 0)
        if entries.count > Self.limit {
            entries.removeLast(entries.count - Self.limit)
        }
        return entry
    }

    func entry(id: UUID) -> CaptureHistoryEntry? {
        entries.first { $0.id == id }
    }

    func removeAll() {
        entries.removeAll()
    }
}

/// One captured screenshot and the edits made to it.
final class CaptureHistoryEntry: Identifiable {
    /// Largest size of the menu thumbnail, in points.
    static let thumbnailSize = CGSize(width: 64, height: 40)

    let id = UUID()
    let date = Date()
    /// Image size in points.
    let size: CGSize
    let thumbnail: NSImage
    /// Annotations and style from when its editor last closed, unless the user discarded them.
    var document: EditorDocument?

    private let scale: CGFloat
    /// The full image, kept only until compression finishes.
    private var image: CGImage?
    private var pngData: Data?

    init(screenshot: Screenshot) {
        size = screenshot.size
        scale = screenshot.scale
        thumbnail = Self.makeThumbnail(of: screenshot)
        image = screenshot.image
        compress(screenshot.image)
    }

    /// The captured screenshot, decompressed if needed.
    var screenshot: Screenshot? {
        if let image {
            return Screenshot(image: image, scale: scale)
        }
        guard let pngData,
              let source = CGImageSourceCreateWithData(pngData as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { return nil }
        return Screenshot(image: image, scale: scale)
    }

    // MARK: - Private

    private func compress(_ image: CGImage) {
        Task { [weak self] in
            guard let data = await Self.pngData(for: image), let self else { return }
            pngData = data
            // Also releases the full screen behind cropped area captures, which share its pixels.
            self.image = nil
        }
    }

    @concurrent
    private nonisolated static func pngData(for image: CGImage) async -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        return CGImageDestinationFinalize(destination) ? data as Data : nil
    }

    /// A small bitmap copy, so the menu never holds on to the full image.
    private static func makeThumbnail(of screenshot: Screenshot) -> NSImage {
        let fit = min(thumbnailSize.width / screenshot.size.width, thumbnailSize.height / screenshot.size.height, 1)
        let size = CGSize(width: max(screenshot.size.width * fit, 1), height: max(screenshot.size.height * fit, 1))
        let pixelScale: CGFloat = 2

        guard let context = CGContext(
            data: nil,
            width: Int((size.width * pixelScale).rounded()),
            height: Int((size.height * pixelScale).rounded()),
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return NSImage(size: size) }

        context.interpolationQuality = .high
        context.draw(screenshot.image, in: CGRect(x: 0, y: 0, width: context.width, height: context.height))
        guard let thumbnail = context.makeImage() else { return NSImage(size: size) }
        return NSImage(cgImage: thumbnail, size: size)
    }
}
