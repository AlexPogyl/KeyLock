import Cocoa
import Carbon.HIToolbox

/// Modifier keys we care about. Everything else (Fn, Caps Lock, NumPad) is ignored
/// on purpose so a stuck Caps Lock can never break the unlock combination.
enum Mod: String, Codable, CaseIterable, Hashable {
    case control
    case option
    case shift
    case command

    var symbol: String {
        switch self {
        case .control: return "⌃"
        case .option:  return "⌥"
        case .shift:   return "⇧"
        case .command: return "⌘"
        }
    }

    var flag: CGEventFlags {
        switch self {
        case .control: return .maskControl
        case .option:  return .maskAlternate
        case .shift:   return .maskShift
        case .command: return .maskCommand
        }
    }

    var name: String {
        switch self {
        case .control: return "Control"
        case .option:  return "Option"
        case .shift:   return "Shift"
        case .command: return "Command"
        }
    }
}

/// A key combination: one key code plus a set of modifiers.
struct KeyCombo: Codable, Equatable, Hashable {
    var keyCode: UInt16
    var mods: Set<Mod>

    static let `default` = KeyCombo(keyCode: UInt16(kVK_ANSI_K), mods: [.control, .option, .command])

    /// Canonical display order: ⌃⌥⇧⌘
    var orderedMods: [Mod] {
        [.control, .option, .shift, .command].filter { mods.contains($0) }
    }

    var modifierSymbols: String { orderedMods.map(\.symbol).joined() }

    var display: String { modifierSymbols + KeyCodeTranslator.shared.label(for: keyCode) }

    var flags: CGEventFlags {
        mods.reduce(into: CGEventFlags()) { $0.formUnion($1.flag) }
    }

    /// A combination without modifiers would fire on every keystroke — refuse it,
    /// except for a handful of keys that are inherently "safe" as a standalone trigger.
    var isUsable: Bool {
        if !mods.isEmpty { return true }
        return [UInt16(kVK_Escape), UInt16(kVK_F13), UInt16(kVK_F14), UInt16(kVK_F15),
                UInt16(kVK_F16), UInt16(kVK_F17), UInt16(kVK_F18), UInt16(kVK_F19)].contains(keyCode)
    }

    var validationMessage: String? {
        if mods.isEmpty && !isUsable {
            return "Добавьте хотя бы один модификатор (⌃ ⌥ ⇧ ⌘)"
        }
        return nil
    }

    /// Normalises a raw CGEvent flag set into our tiny model.
    static func mods(from flags: CGEventFlags) -> Set<Mod> {
        var result = Set<Mod>()
        if flags.contains(.maskControl)   { result.insert(.control) }
        if flags.contains(.maskAlternate) { result.insert(.option) }
        if flags.contains(.maskShift)     { result.insert(.shift) }
        if flags.contains(.maskCommand)   { result.insert(.command) }
        return result
    }
}

/// Turns virtual key codes into human readable labels, honouring the current
/// keyboard layout for printable keys.
final class KeyCodeTranslator {
    static let shared = KeyCodeTranslator()

    private let specials: [UInt16: String] = [
        UInt16(kVK_Return): "↩", UInt16(kVK_Tab): "⇥", UInt16(kVK_Space): "Space",
        UInt16(kVK_Delete): "⌫", UInt16(kVK_ForwardDelete): "⌦", UInt16(kVK_Escape): "⎋",
        UInt16(kVK_LeftArrow): "←", UInt16(kVK_RightArrow): "→",
        UInt16(kVK_UpArrow): "↑", UInt16(kVK_DownArrow): "↓",
        UInt16(kVK_Home): "↖", UInt16(kVK_End): "↘", UInt16(kVK_PageUp): "⇞",
        UInt16(kVK_PageDown): "⇟", UInt16(kVK_Help): "?⃝",
        UInt16(kVK_ANSI_KeypadEnter): "⌤", UInt16(kVK_ANSI_KeypadClear): "⌧",
        UInt16(kVK_ANSI_KeypadPlus): "＋", UInt16(kVK_ANSI_KeypadMinus): "－",
        UInt16(kVK_ANSI_KeypadMultiply): "＊", UInt16(kVK_ANSI_KeypadDivide): "／",
        UInt16(kVK_ANSI_KeypadEquals): "＝", UInt16(kVK_ANSI_KeypadDecimal): "．",
        UInt16(kVK_ANSI_Comma): ",", UInt16(kVK_ANSI_Period): ".",
        UInt16(kVK_ANSI_Slash): "/", UInt16(kVK_ANSI_Semicolon): ";",
        UInt16(kVK_ANSI_Quote): "'", UInt16(kVK_ANSI_LeftBracket): "[",
        UInt16(kVK_ANSI_RightBracket): "]", UInt16(kVK_ANSI_Backslash): "\\",
        UInt16(kVK_ANSI_Minus): "-", UInt16(kVK_ANSI_Equal): "=",
        UInt16(kVK_ANSI_Grave): "`",
    ]

    private let functionKeys: [UInt16: String] = [
        UInt16(kVK_F1): "F1", UInt16(kVK_F2): "F2", UInt16(kVK_F3): "F3", UInt16(kVK_F4): "F4",
        UInt16(kVK_F5): "F5", UInt16(kVK_F6): "F6", UInt16(kVK_F7): "F7", UInt16(kVK_F8): "F8",
        UInt16(kVK_F9): "F9", UInt16(kVK_F10): "F10", UInt16(kVK_F11): "F11", UInt16(kVK_F12): "F12",
        UInt16(kVK_F13): "F13", UInt16(kVK_F14): "F14", UInt16(kVK_F15): "F15",
        UInt16(kVK_F16): "F16", UInt16(kVK_F17): "F17", UInt16(kVK_F18): "F18",
        UInt16(kVK_F19): "F19", UInt16(kVK_F20): "F20",
    ]

    private var layoutCache: (source: TISInputSource, map: [UInt16: String])?

    /// Modifier keys themselves can be used as the "key" of a combination.
    private let pureModifiers: Set<UInt16> = [
        UInt16(kVK_Command), UInt16(kVK_RightCommand),
        UInt16(kVK_Shift), UInt16(kVK_RightShift),
        UInt16(kVK_Option), UInt16(kVK_RightOption),
        UInt16(kVK_Control), UInt16(kVK_RightControl),
        UInt16(kVK_CapsLock), UInt16(kVK_Function),
    ]

    func label(for keyCode: UInt16) -> String {
        if let s = specials[keyCode] { return s }
        if let f = functionKeys[keyCode] { return f }
        if pureModifiers.contains(keyCode) {
            switch Int(keyCode) {
            case kVK_Command, kVK_RightCommand: return "⌘"
            case kVK_Shift, kVK_RightShift:     return "⇧"
            case kVK_Option, kVK_RightOption:   return "⌥"
            case kVK_Control, kVK_RightControl: return "⌃"
            case kVK_CapsLock:                  return "⇪"
            case kVK_Function:                  return "fn"
            default: break
            }
        }
        if let cached = layoutCache, let value = cached.map[keyCode] { return value }
        return String(format: "0x%02X", keyCode)
    }

    /// Rebuilds the printable-key map for the currently selected input source.
    func refreshLayout() {
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let rawLayout = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
        else { return }
        let layoutData = Unmanaged<CFData>.fromOpaque(rawLayout).takeUnretainedValue() as Data

        var map: [UInt16: String] = [:]
        layoutData.withUnsafeBytes { buffer in
            guard let base = buffer.baseAddress else { return }
            let layout = base.assumingMemoryBound(to: UCKeyboardLayout.self)
            for code in 0..<128 {
                var deadKeyState: UInt32 = 0
                var chars = [UniChar](repeating: 0, count: 4)
                var length = 0
                let status = UCKeyTranslate(layout, UInt16(code), UInt16(kUCKeyActionDisplay), 0,
                                            UInt32(LMGetKbdType()), OptionBits(kUCKeyTranslateNoDeadKeysBit),
                                            &deadKeyState, chars.count, &length, &chars)
                if status == noErr, length > 0 {
                    let s = String(utf16CodeUnits: chars, count: length)
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    if !s.isEmpty { map[UInt16(code)] = s.uppercased() }
                }
            }
        }
        layoutCache = (source, map)
    }
}
