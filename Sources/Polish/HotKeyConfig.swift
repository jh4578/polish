import AppKit
import Carbon

/// The user-configurable global hotkey, persisted in UserDefaults.
struct HotKeyConfig {
    var keyCode: UInt32
    var carbonModifiers: UInt32

    static let `default` = HotKeyConfig(keyCode: UInt32(kVK_ANSI_P),
                                        carbonModifiers: UInt32(optionKey)) // ⌥P

    static var current: HotKeyConfig {
        get {
            let defaults = UserDefaults.standard
            guard defaults.object(forKey: "HotKeyCode") != nil else { return .default }
            return HotKeyConfig(
                keyCode: UInt32(defaults.integer(forKey: "HotKeyCode")),
                carbonModifiers: UInt32(defaults.integer(forKey: "HotKeyModifiers"))
            )
        }
        set {
            let defaults = UserDefaults.standard
            defaults.set(Int(newValue.keyCode), forKey: "HotKeyCode")
            defaults.set(Int(newValue.carbonModifiers), forKey: "HotKeyModifiers")
        }
    }

    static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var mods: UInt32 = 0
        if flags.contains(.control) { mods |= UInt32(controlKey) }
        if flags.contains(.option)  { mods |= UInt32(optionKey) }
        if flags.contains(.shift)   { mods |= UInt32(shiftKey) }
        if flags.contains(.command) { mods |= UInt32(cmdKey) }
        return mods
    }

    /// e.g. "⌥P", "⌃⇧Space"
    var displayString: String {
        var s = ""
        if carbonModifiers & UInt32(controlKey) != 0 { s += "⌃" }
        if carbonModifiers & UInt32(optionKey)  != 0 { s += "⌥" }
        if carbonModifiers & UInt32(shiftKey)   != 0 { s += "⇧" }
        if carbonModifiers & UInt32(cmdKey)     != 0 { s += "⌘" }
        return s + Self.keyName(for: keyCode)
    }

    private static let specialKeyNames: [UInt32: String] = [
        36: "↩", 48: "⇥", 49: "Space", 51: "⌫", 53: "⎋", 76: "⌤",
        114: "Help", 115: "↖", 116: "⇞", 117: "⌦", 119: "↘", 121: "⇟",
        123: "←", 124: "→", 125: "↓", 126: "↑",
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6",
        98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12",
    ]

    /// Human-readable name for a virtual key code, using the current keyboard layout.
    static func keyName(for keyCode: UInt32) -> String {
        if let name = specialKeyNames[keyCode] { return name }

        guard
            let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
            let layoutPtr = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
        else { return "Key\(keyCode)" }

        let layoutData = Unmanaged<CFData>.fromOpaque(layoutPtr).takeUnretainedValue() as Data
        var deadKeyState: UInt32 = 0
        var chars = [UniChar](repeating: 0, count: 4)
        var length = 0

        let status = layoutData.withUnsafeBytes { (buf: UnsafeRawBufferPointer) -> OSStatus in
            let layout = buf.bindMemory(to: UCKeyboardLayout.self).baseAddress!
            return UCKeyTranslate(layout, UInt16(keyCode), UInt16(kUCKeyActionDisplay), 0,
                                  UInt32(LMGetKbdType()), OptionBits(kUCKeyTranslateNoDeadKeysBit),
                                  &deadKeyState, chars.count, &length, &chars)
        }

        guard status == noErr, length > 0 else { return "Key\(keyCode)" }
        return String(utf16CodeUnits: chars, count: length).uppercased()
    }
}
