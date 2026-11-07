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
        let delegate = AppDelegate()
        // `NSApplication.delegate` is weak; keep the delegate alive for the run loop's lifetime.
        app.delegate = delegate
        withExtendedLifetime(delegate) {
            app.run()
        }
    }
}
