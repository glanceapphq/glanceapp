import AppKit

/// Persists the user's capture shortcuts in `UserDefaults`.
enum HotKeySettings {
    /// The saved shortcut for `mode`, or its default.
    static func hotKey(for mode: CaptureMode, in store: UserDefaults = .standard) -> HotKey {
        guard let stored = store.dictionary(forKey: key(for: mode)),
              let keyCode = stored["keyCode"] as? Int,
              let key = stored["key"] as? String,
              let modifiers = stored["modifiers"] as? Int
        else { return mode.defaultHotKey }

        return HotKey(keyCode: UInt32(keyCode), key: key, modifiers: NSEvent.ModifierFlags(rawValue: UInt(modifiers)))
    }

    /// Saves `hotKey` for `mode`; `nil` restores the default.
    static func setHotKey(_ hotKey: HotKey?, for mode: CaptureMode, in store: UserDefaults = .standard) {
        guard let hotKey, hotKey != mode.defaultHotKey else {
            store.removeObject(forKey: key(for: mode))
            return
        }

        store.set([
            "keyCode": Int(hotKey.keyCode),
            "key": hotKey.key,
            "modifiers": Int(hotKey.modifiers.rawValue),
        ], forKey: key(for: mode))
    }

    private static func key(for mode: CaptureMode) -> String {
        "hotKey.\(mode.rawValue)"
    }
}
