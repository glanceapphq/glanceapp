import AppKit
import Carbon.HIToolbox

/// The kinds of capture the app supports.
enum CaptureMode: UInt32, CaseIterable, Identifiable {
    case area = 1
    case fullScreen = 2

    var id: UInt32 { rawValue }

    var title: String {
        switch self {
        case .area: "Capture Area"
        case .fullScreen: "Capture Full Screen"
        }
    }

    var defaultHotKey: HotKey {
        switch self {
        case .area: HotKey(keyCode: UInt32(kVK_ANSI_1), key: "1", modifiers: [.command, .shift])
        case .fullScreen: HotKey(keyCode: UInt32(kVK_ANSI_2), key: "2", modifiers: [.command, .shift])
        }
    }
}
