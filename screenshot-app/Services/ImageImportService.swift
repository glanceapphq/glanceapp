import AppKit
import ImageIO
import UniformTypeIdentifiers

enum ImageImportError: LocalizedError {
    /// The file or data isn't an image ImageIO can decode (unsupported type or corrupt).
    case unreadable(fileName: String?)
    case noImageOnClipboard

    var errorDescription: String? {
        switch self {
        case .unreadable(let fileName?):
            "“\(fileName)” isn’t an image Glance can open. Try a PNG, JPEG, HEIC, TIFF, GIF or WebP file."
        case .unreadable(nil):
            "The image is damaged or in a format Glance can’t open."
        case .noImageOnClipboard:
            "The clipboard doesn’t contain an image."
        }
    }
}

/// Turns existing images (files, clipboard contents) into a `Screenshot`, so they can be
/// edited exactly like a capture.
///
/// Everything goes through ImageIO, which reads the image's DPI: that's how a Retina
/// screenshot exported by Glance (144 DPI) comes back at scale 2 and the same on-screen size.
struct ImageImportService {
    /// What the open panel offers. GIFs open at their first frame.
    static let supportedTypes: [UTType] = [.png, .jpeg, .heic, .heif, .tiff, .gif, .webP]

    /// Clipboard types to look for, best first: PNG is lossless and keeps the DPI.
    private static let pasteboardTypes = supportedTypes.map { NSPasteboard.PasteboardType($0.identifier) }

    /// Reading options that keep only files of a supported image type.
    private static let imageFileOptions: [NSPasteboard.ReadingOptionKey: Any] = [
        .urlReadingFileURLsOnly: true,
        .urlReadingContentsConformToTypes: supportedTypes.map(\.identifier),
    ]

    // MARK: - Files

    func screenshot(contentsOf url: URL) throws -> Screenshot {
        // Not needed for files from the open panel or a drop, but files read from the
        // clipboard may carry a security scope the sandbox wants us to claim.
        let isAccessing = url.startAccessingSecurityScopedResource()
        defer { if isAccessing { url.stopAccessingSecurityScopedResource() } }

        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            throw ImageImportError.unreadable(fileName: url.lastPathComponent)
        }
        return try screenshot(from: source, fileName: url.lastPathComponent)
    }

    /// Image files on `pasteboard` (e.g. a drag from Finder), in their original order.
    static func imageFileURLs(on pasteboard: NSPasteboard) -> [URL] {
        pasteboard.readObjects(forClasses: [NSURL.self], options: imageFileOptions) as? [URL] ?? []
    }

    // MARK: - Data and clipboard

    func screenshot(from data: Data) throws -> Screenshot {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            throw ImageImportError.unreadable(fileName: nil)
        }
        return try screenshot(from: source, fileName: nil)
    }

    /// The image on `pasteboard`: a copied image file, or image data copied from an app.
    func screenshot(from pasteboard: NSPasteboard) throws -> Screenshot {
        // Copying a file in Finder also puts its *icon* on the clipboard as TIFF.
        // So when there are files, only an image file counts, never that icon.
        if Self.hasFiles(on: pasteboard) {
            guard let url = Self.imageFileURLs(on: pasteboard).first else { throw ImageImportError.noImageOnClipboard }
            return try screenshot(contentsOf: url)
        }

        guard let type = pasteboard.availableType(from: Self.pasteboardTypes),
              let data = pasteboard.data(forType: type)
        else { throw ImageImportError.noImageOnClipboard }
        return try screenshot(from: data)
    }

    /// A quick check for enabling "Open from Clipboard": looks at types only, decodes nothing.
    static func canReadImage(from pasteboard: NSPasteboard) -> Bool {
        if hasFiles(on: pasteboard) {
            return pasteboard.canReadObject(forClasses: [NSURL.self], options: imageFileOptions)
        }
        return pasteboard.availableType(from: pasteboardTypes) != nil
    }

    // MARK: - Scale

    /// Pixels per point for an image with these ImageIO properties: its DPI / 72.
    ///
    /// 144 DPI → 2, like a Retina capture. No DPI, or less than 72, → 1: such images are
    /// shown pixel for pixel, never enlarged. Rounded to 0.01 because PNG stores DPI as
    /// whole pixels per metre, so 144 DPI comes back as 143.99.
    static func scale(fromProperties properties: [CFString: Any]) -> CGFloat {
        guard let dpi = (properties[kCGImagePropertyDPIWidth] as? NSNumber)?.doubleValue, dpi > 0 else { return 1 }
        return max(1, (dpi / 72 * 100).rounded() / 100)
    }

    // MARK: - Private

    private static func hasFiles(on pasteboard: NSPasteboard) -> Bool {
        pasteboard.canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true])
    }

    private func screenshot(from source: CGImageSource, fileName: String?) throws -> Screenshot {
        guard CGImageSourceGetCount(source) > 0,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
              let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue,
              width > 0, height > 0
        else { throw ImageImportError.unreadable(fileName: fileName) }

        // A "thumbnail" as large as the image itself is the simplest way to get ImageIO to
        // apply the EXIF orientation, so iPhone photos aren't shown on their side.
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(width, height),
            kCGImageSourceShouldCacheImmediately: true,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw ImageImportError.unreadable(fileName: fileName)
        }
        return Screenshot(image: image, scale: Self.scale(fromProperties: properties))
    }
}
