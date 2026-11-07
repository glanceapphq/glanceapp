import AppKit
import Carbon.HIToolbox

/// A global keyboard shortcut.
struct HotKey: Equatable {
    /// Virtual key code (`kVK_*`).
    let keyCode: UInt32
    /// Character shown in menus, e.g. `"1"`.
    let key: String
    let modifiers: NSEvent.ModifierFlags

    /// Human-readable form, e.g. `⇧⌘1`.
    var displayString: String {
        var result = ""
        if modifiers.contains(.control) { result += "⌃" }
        if modifiers.contains(.option) { result += "⌥" }
        if modifiers.contains(.shift) { result += "⇧" }
        if modifiers.contains(.command) { result += "⌘" }
        return result + (key.count == 1 ? key.uppercased() : key)
    }

    /// Modifiers a shortcut can use; others (Caps Lock, Fn, …) are ignored.
    static let relevantModifiers: NSEvent.ModifierFlags = [.command, .shift, .option, .control]

    init(keyCode: UInt32, key: String, modifiers: NSEvent.ModifierFlags) {
        self.keyCode = keyCode
        self.key = key
        self.modifiers = modifiers.intersection(Self.relevantModifiers)
    }

    /// Builds a shortcut from a key press, or returns `nil` if it isn't a usable global shortcut:
    /// it needs ⌘, ⌃ or ⌥ (Shift alone would block normal typing), except for function keys.
    init?(event: NSEvent) {
        let keyCode = Int(event.keyCode)
        let modifiers = event.modifierFlags.intersection(Self.relevantModifiers)
        let isFunctionKey = Self.functionKeyNames[keyCode] != nil
        guard isFunctionKey || !modifiers.isDisjoint(with: [.command, .option, .control]) else { return nil }

        // `characters(byApplyingModifiers: [])` gives "1" for ⇧1, where `charactersIgnoringModifiers` gives "!".
        guard let key = Self.functionKeyNames[keyCode] ?? Self.specialKeyNames[keyCode]
            ?? event.characters(byApplyingModifiers: [])?.uppercased(),
            !key.isEmpty
        else { return nil }

        self.init(keyCode: UInt32(keyCode), key: key, modifiers: modifiers)
    }

    /// Key equivalent for menu items, or empty when the key can't be shown as a single character.
    var menuKeyEquivalent: String {
        key.count == 1 ? key.lowercased() : ""
    }

    private static let functionKeyNames: [Int: String] = [
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6",
        kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
    ]

    private static let specialKeyNames: [Int: String] = [
        kVK_Space: "Space", kVK_Return: "↩", kVK_Tab: "⇥", kVK_Delete: "⌫", kVK_ForwardDelete: "⌦",
        kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
        kVK_Home: "↖", kVK_End: "↘", kVK_PageUp: "⇞", kVK_PageDown: "⇟",
    ]

    fileprivate var carbonModifiers: UInt32 {
        var result: UInt32 = 0
        if modifiers.contains(.command) { result |= UInt32(cmdKey) }
        if modifiers.contains(.shift) { result |= UInt32(shiftKey) }
        if modifiers.contains(.option) { result |= UInt32(optionKey) }
        if modifiers.contains(.control) { result |= UInt32(controlKey) }
        return result
    }
}

/// Registers system-wide hot keys via Carbon's `RegisterEventHotKey`.
///
/// Unlike `NSEvent.addGlobalMonitorForEvents`, this needs no Accessibility
/// permission and consumes the key press, so it doesn't leak into the frontmost app.
///
/// The Carbon handler keeps an unretained pointer to this object: keep the
/// service alive while hot keys are registered and call `unregisterAll()` before
/// releasing it.
final class HotKeyService {
    /// Four-char code identifying our hot keys ('SCRT').
    private static let signature: OSType = 0x5343_5254

    private let onTrigger: (UInt32) -> Void
    private var handlerRef: EventHandlerRef?
    private var registeredHotKeys: [UInt32: EventHotKeyRef] = [:]

    /// - Parameter onTrigger: Called on the main thread with the id passed to `register(_:id:)`.
    init(onTrigger: @escaping (UInt32) -> Void) {
        self.onTrigger = onTrigger
        installEventHandler()
    }

    /// Registers `hotKey` under `id`, replacing any hot key previously registered with that id.
    /// - Returns: `false` if the shortcut is unavailable (e.g. already taken by another app).
    @discardableResult
    func register(_ hotKey: HotKey, id: UInt32) -> Bool {
        unregister(id: id)

        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: Self.signature, id: id)
        let status = RegisterEventHotKey(hotKey.keyCode, hotKey.carbonModifiers, hotKeyID, GetApplicationEventTarget(), 0, &ref)
        guard status == noErr, let ref else { return false }

        registeredHotKeys[id] = ref
        return true
    }

    func unregister(id: UInt32) {
        if let ref = registeredHotKeys.removeValue(forKey: id) {
            UnregisterEventHotKey(ref)
        }
    }

    /// Unregisters every hot key and removes the Carbon event handler.
    func unregisterAll() {
        registeredHotKeys.values.forEach { UnregisterEventHotKey($0) }
        registeredHotKeys.removeAll()
        if let handlerRef {
            RemoveEventHandler(handlerRef)
            self.handlerRef = nil
        }
    }

    // MARK: - Private

    private func installEventHandler() {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let userData = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), hotKeyEventHandler, 1, &eventType, userData, &handlerRef)
    }

    fileprivate func handle(_ event: EventRef) -> OSStatus {
        var hotKeyID = EventHotKeyID()
        let status = GetEventParameter(
            event,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &hotKeyID
        )
        guard status == noErr, hotKeyID.signature == Self.signature else {
            return OSStatus(eventNotHandledErr)
        }

        onTrigger(hotKeyID.id)
        return noErr
    }
}

/// C callback for Carbon hot key events. Carbon dispatches these on the main run loop.
private nonisolated func hotKeyEventHandler(
    _ nextHandler: EventHandlerCallRef?,
    _ event: EventRef?,
    _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let event, let userData else { return OSStatus(eventNotHandledErr) }
    // Raw pointers aren't Sendable; pass their addresses across the isolation boundary.
    // Safe because they're used synchronously on the main thread, which `assumeIsolated` asserts.
    let eventAddress = UInt(bitPattern: event)
    let serviceAddress = UInt(bitPattern: userData)
    return MainActor.assumeIsolated {
        guard let event = EventRef(bitPattern: eventAddress),
              let pointer = UnsafeMutableRawPointer(bitPattern: serviceAddress) else {
            return OSStatus(eventNotHandledErr)
        }
        return Unmanaged<HotKeyService>.fromOpaque(pointer).takeUnretainedValue().handle(event)
    }
}
