import AppKit
import Carbon.HIToolbox

/// A global shortcut as Carbon modifier flags (cmdKey, optionKey, …) plus a virtual key code.
struct Hotkey: Equatable {
    var modifiers: UInt32
    var keyCode: UInt32

    static let `default` = Hotkey(modifiers: UInt32(cmdKey | shiftKey), keyCode: UInt32(kVK_ANSI_V)) // ⇧⌘V

    var isValid: Bool { keyCode < 0x80 && modifiers & UInt32(cmdKey | optionKey | controlKey) != 0 }

    init(modifiers: UInt32, keyCode: UInt32) {
        self.modifiers = modifiers
        self.keyCode = keyCode
    }

    init(event: NSEvent) {
        let flags = event.modifierFlags
        var mods = 0
        if flags.contains(.control) { mods |= controlKey }
        if flags.contains(.option) { mods |= optionKey }
        if flags.contains(.shift) { mods |= shiftKey }
        if flags.contains(.command) { mods |= cmdKey }
        self.init(modifiers: UInt32(mods), keyCode: UInt32(event.keyCode))
    }

    /// "⇧⌘V", in the order macOS uses in menus.
    var description: String {
        var text = ""
        if modifiers & UInt32(controlKey) != 0 { text += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { text += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { text += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { text += "⌘" }
        return text + KeyboardLayout.name(of: UInt16(keyCode))
    }
}

/// Key names and characters for the keyboard layout the user types with.
enum KeyboardLayout {
    private static let specialKeys: [Int: String] = [
        kVK_Return: "↩", kVK_Tab: "⇥", kVK_Delete: "⌫", kVK_ForwardDelete: "⌦", kVK_Escape: "⎋",
        kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
        kVK_Home: "↖", kVK_End: "↘", kVK_PageUp: "⇞", kVK_PageDown: "⇟", kVK_Help: "Help",
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6",
        kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
        kVK_F13: "F13", kVK_F14: "F14", kVK_F15: "F15", kVK_F16: "F16", kVK_F17: "F17", kVK_F18: "F18",
        kVK_F19: "F19", kVK_F20: "F20", kVK_ANSI_KeypadEnter: "⌤",
    ]

    static func name(of keyCode: UInt16) -> String {
        if Int(keyCode) == kVK_Space { return Loc.t("key.space") }
        if let name = specialKeys[Int(keyCode)] { return name }
        return character(for: keyCode)?.uppercased() ?? "#\(keyCode)"
    }

    /// The key code that types `text` in the current layout ("v" is not on the same key in Dvorak).
    static func keyCode(typing text: String, fallback: UInt16) -> UInt16 {
        (0..<UInt16(0x80)).first { KeyboardLayout.character(for: $0) == text } ?? fallback
    }

    /// The character a key types without modifiers in the current keyboard layout.
    static func character(for keyCode: UInt16) -> String? {
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let pointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return nil }
        let layoutData = Unmanaged<CFData>.fromOpaque(pointer).takeUnretainedValue() as Data
        return layoutData.withUnsafeBytes { raw -> String? in
            guard let layout = raw.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else { return nil }
            var deadKeyState: UInt32 = 0
            var chars = [UniChar](repeating: 0, count: 4)
            var length = 0
            let status = UCKeyTranslate(layout, keyCode, UInt16(kUCKeyActionDisplay), 0, UInt32(LMGetKbdType()),
                                        OptionBits(1 << kUCKeyTranslateNoDeadKeysBit), &deadKeyState, chars.count, &length, &chars)
            guard status == noErr, length > 0 else { return nil }
            let text = String(utf16CodeUnits: chars, count: length)
            return text.trimmingCharacters(in: .controlCharacters).isEmpty ? nil : text
        }
    }
}
