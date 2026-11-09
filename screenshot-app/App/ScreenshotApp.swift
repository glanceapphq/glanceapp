import AppKit

/// Application entry point.
///
/// The app is a menu bar–only agent (`LSUIElement = YES`), so it has no main
/// window and no SwiftUI `Scene`. We drive `NSApplication` directly and host
/// SwiftUI views inside AppKit windows where needed.
@main
enum ScreenshotApp {
    static func main() {
        let app = NSApplication.shared

        // As the host of unit tests, run without the menu bar item and global hot keys,
        // so tests don't interfere with a copy of the app that's already running.
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else {
            app.run()
            return
        }

        let delegate = AppDelegate()
        // `NSApplication.delegate` is weak; keep the delegate alive for the run loop's lifetime.
        app.delegate = delegate
        withExtendedLifetime(delegate) {
            app.run()
        }
    }
}
