import AppKit
import Carbon.HIToolbox
import XCTest
@testable import Glance

@MainActor
final class HotKeyTests: XCTestCase {
    private func keyDown(_ code: Int, _ characters: String, _ modifiers: NSEvent.ModifierFlags) -> NSEvent {
        NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: 0, windowNumber: 0, context: nil,
            characters: characters, charactersIgnoringModifiers: characters, isARepeat: false, keyCode: UInt16(code)
        )!
    }

    func testAcceptsShortcutAndDropsIrrelevantModifiers() throws {
        let hotKey = try XCTUnwrap(HotKey(event: keyDown(kVK_ANSI_4, "$", [.command, .shift, .capsLock])))
        XCTAssertEqual(hotKey.modifiers, [.command, .shift])
        XCTAssertEqual(hotKey.displayString, "⇧⌘4")
    }

    func testRejectsShortcutsWithoutCommandControlOrOption() {
        XCTAssertNil(HotKey(event: keyDown(kVK_ANSI_A, "A", [.shift])))
        XCTAssertNil(HotKey(event: keyDown(kVK_ANSI_A, "a", [])))
    }

    func testFunctionKeysNeedNoModifiers() {
        let f5 = HotKey(event: keyDown(kVK_F5, "\u{F708}", []))
        XCTAssertEqual(f5?.displayString, "F5")
        XCTAssertEqual(f5?.menuKeyEquivalent, "")
    }

    func testSpecialKeyNames() {
        XCTAssertEqual(HotKey(event: keyDown(kVK_Space, " ", [.control, .option]))?.displayString, "⌃⌥Space")
    }

    func testSettingsRoundTrip() {
        let store = makeIsolatedDefaults()
        let custom = HotKey(event: keyDown(kVK_ANSI_4, "$", [.command, .shift]))

        XCTAssertEqual(HotKeySettings.hotKey(for: .area, in: store), CaptureMode.area.defaultHotKey)
        HotKeySettings.setHotKey(custom, for: .area, in: store)
        XCTAssertEqual(HotKeySettings.hotKey(for: .area, in: store), custom)

        HotKeySettings.setHotKey(nil, for: .area, in: store)
        XCTAssertEqual(HotKeySettings.hotKey(for: .area, in: store), CaptureMode.area.defaultHotKey)
        XCTAssertNil(store.dictionary(forKey: "hotKey.\(CaptureMode.area.rawValue)"), "the default isn't stored")
    }
}
