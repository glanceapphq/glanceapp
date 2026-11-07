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
        return result + key.uppercased()
    }

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
