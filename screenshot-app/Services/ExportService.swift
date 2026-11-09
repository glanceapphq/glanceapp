import AppKit

/// Folder that "Save" writes screenshots to: Downloads, or a folder the user picked.
///
/// The app is sandboxed: an entitlement allows writing to Downloads, but any other
/// folder (Desktop included) has to be picked by the user in an open panel. Access to
/// it is kept across launches with a security-scoped bookmark.
struct SaveFolder {
    /// `UserDefaults` key holding the bookmark of the picked folder; absent for Downloads.
    static let bookmarkKey = "saveFolderBookmark"

    private let store: UserDefaults

    init(store: UserDefaults = .standard) {
        self.store = store
    }

    /// The picked folder, or `nil` when saving to Downloads (or when it can't be found).
    var customFolder: URL? {
        guard let bookmark = store.data(forKey: Self.bookmarkKey) else { return nil }
        var isStale = false
        return try? URL(resolvingBookmarkData: bookmark, options: .withSecurityScope, bookmarkDataIsStale: &isStale)
    }

    var isCustom: Bool { store.data(forKey: Self.bookmarkKey) != nil }

    /// Where screenshots are saved. (In the sandbox, Downloads is reached through a
    /// symlink in the app's container; resolve it to show the real folder.)
    var folder: URL {
        customFolder ?? URL.downloadsDirectory.resolvingSymlinksInPath()
    }

    /// Folder name as Finder shows it, e.g. "Desktop".
    var title: String {
        FileManager.default.displayName(atPath: folder.path(percentEncoded: false))
    }

    /// Saves to `folder` from now on. `folder` must come from an open panel, which grants access to it.
    func choose(_ folder: URL) throws {
        store.set(try folder.bookmarkData(options: .withSecurityScope), forKey: Self.bookmarkKey)
    }

    /// Goes back to saving to Downloads.
    func reset() {
        store.removeObject(forKey: Self.bookmarkKey)
    }

    /// Runs `body` with write access to the folder.
    func withAccess<Result>(_ body: (URL) throws -> Result) throws -> Result {
        guard let bookmark = store.data(forKey: Self.bookmarkKey) else {
            return try body(.downloadsDirectory)
        }

        var isStale = false
        guard let folder = try? URL(resolvingBookmarkData: bookmark, options: .withSecurityScope, bookmarkDataIsStale: &isStale),
              folder.startAccessingSecurityScopedResource()
        else { throw ExportError.saveFolderUnavailable }
        defer { folder.stopAccessingSecurityScopedResource() }

        // The folder was moved or renamed; refresh the bookmark while we have access.
        if isStale {
            try? choose(folder)
        }
        return try body(folder)
    }
}

enum ExportError: LocalizedError {
    case saveFolderUnavailable

    var errorDescription: String? {
        switch self {
        case .saveFolderUnavailable: "The folder for saving screenshots is no longer available. Choose it again in Settings."
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

    /// Writes the image as PNG into `folder`, never overwriting existing files.
    /// - Returns: The URL of the saved file.
    @discardableResult
    func save(_ image: RenderedImage, to folder: SaveFolder = SaveFolder()) throws -> URL {
        try folder.withAccess { directory in
            let url = uniqueFileURL(in: directory, baseName: Self.fileBaseName(for: .now))
            try image.pngData.write(to: url, options: .withoutOverwriting)
            return url
        }
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
