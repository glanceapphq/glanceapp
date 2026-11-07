import AppKit

/// Folder that "Save" writes screenshots to.
enum SaveLocation: String, CaseIterable, Identifiable {
    case desktop
    case downloads

    /// `UserDefaults` key holding the user's choice.
    static let defaultsKey = "saveLocation"

    static var current: SaveLocation {
        UserDefaults.standard.string(forKey: defaultsKey).flatMap(SaveLocation.init) ?? .desktop
    }

    var id: String { rawValue }

    var title: String {
        switch self {
        case .desktop: "Desktop"
        case .downloads: "Downloads"
        }
    }

    var directory: URL {
        switch self {
        case .desktop: .desktopDirectory
        case .downloads: .downloadsDirectory
        }
    }
}

/// Delivers rendered images to the clipboard or disk.
struct ExportService {
    func copyToPasteboard(_ image: RenderedImage) {
        let item = NSPasteboardItem()
        item.setData(image.pngData, forType: .png)
        if let tiff = image.tiffData {
            // Some apps only read TIFF from the pasteboard.
            item.setData(tiff, forType: .tiff)
        }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([item])
    }

    /// Writes the image as PNG into `location`, never overwriting existing files.
    /// - Returns: The URL of the saved file.
    @discardableResult
    func save(_ image: RenderedImage, to location: SaveLocation = .current) throws -> URL {
        let url = uniqueFileURL(in: location.directory, baseName: Self.fileBaseName(for: .now))
        try image.pngData.write(to: url, options: .withoutOverwriting)
        return url
    }

    // MARK: - Private

    /// macOS-style name, e.g. "Screenshot 2026-11-07 at 15.04.32".
    private static func fileBaseName(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        return "Screenshot \(formatter.string(from: date))"
    }

    private func uniqueFileURL(in directory: URL, baseName: String) -> URL {
        var url = directory.appending(path: "\(baseName).png")
        var counter = 2
        while FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) {
            url = directory.appending(path: "\(baseName) (\(counter)).png")
            counter += 1
        }
        return url
    }
}
