import Foundation
import AppKit

enum JoyConSide: String, CaseIterable, Codable {
    case left = "left"
    case right = "right"

    var displayName: String {
        switch self {
        case .left: return "Left"
        case .right: return "Right"
        }
    }
}

enum JoyConInput: String, CaseIterable, Codable, Hashable {
    case dpadUp
    case dpadDown
    case dpadLeft
    case dpadRight

    case buttonA
    case buttonB
    case buttonX
    case buttonY

    case leftShoulder
    case rightShoulder
    case leftTrigger
    case rightTrigger

    case leftThumbstickButton
    case rightThumbstickButton

    case buttonMenu
    case buttonOptions
    case buttonHome
    case buttonCapture

    case leftStickUp
    case leftStickDown
    case leftStickLeft
    case leftStickRight

    case rightStickUp
    case rightStickDown
    case rightStickLeft
    case rightStickRight

    var displayName: String {
        switch self {
        case .dpadUp: return "D-Pad Up"
        case .dpadDown: return "D-Pad Down"
        case .dpadLeft: return "D-Pad Left"
        case .dpadRight: return "D-Pad Right"
        case .buttonA: return "Button A"
        case .buttonB: return "Button B"
        case .buttonX: return "Button X"
        case .buttonY: return "Button Y"
        case .leftShoulder: return "Left Shoulder"
        case .rightShoulder: return "Right Shoulder"
        case .leftTrigger: return "Left Trigger"
        case .rightTrigger: return "Right Trigger"
        case .leftThumbstickButton: return "Left Stick Button"
        case .rightThumbstickButton: return "Right Stick Button"
        case .buttonMenu: return "Menu (Plus)"
        case .buttonOptions: return "Options (Minus)"
        case .buttonHome: return "Home"
        case .buttonCapture: return "Capture"
        case .leftStickUp: return "Left Stick Up"
        case .leftStickDown: return "Left Stick Down"
        case .leftStickLeft: return "Left Stick Left"
        case .leftStickRight: return "Left Stick Right"
        case .rightStickUp: return "Right Stick Up"
        case .rightStickDown: return "Right Stick Down"
        case .rightStickLeft: return "Right Stick Left"
        case .rightStickRight: return "Right Stick Right"
        }
    }
}

struct JoyConBindingKey: Codable, Hashable {
    let side: JoyConSide
    let input: JoyConInput

    var displayName: String {
        "\(side.displayName) - \(input.displayName)"
    }
}

struct KeyChord: Codable, Hashable {
    let keyCode: UInt16
    let modifiersRaw: UInt64

    var modifiers: CGEventFlags {
        CGEventFlags(rawValue: modifiersRaw)
    }

    init(keyCode: UInt16, modifiers: CGEventFlags) {
        self.keyCode = keyCode
        self.modifiersRaw = modifiers.rawValue
    }

    static func from(event: NSEvent) -> KeyChord? {
        let keyCode = event.keyCode
        if isModifierKeyCode(keyCode) {
            return nil
        }

        let modifiers = cgModifiers(from: event.modifierFlags)
        return KeyChord(keyCode: keyCode, modifiers: modifiers)
    }

    func displayString() -> String {
        var parts: [String] = []
        if modifiers.contains(.maskCommand) {
            parts.append("Cmd")
        }
        if modifiers.contains(.maskControl) {
            parts.append("Ctrl")
        }
        if modifiers.contains(.maskAlternate) {
            parts.append("Option")
        }
        if modifiers.contains(.maskShift) {
            parts.append("Shift")
        }
        if modifiers.contains(.maskSecondaryFn) {
            parts.append("Fn")
        }

        let keyName = KeyCodeDisplay.name(for: keyCode)
        parts.append(keyName)
        return parts.joined(separator: "+")
    }

    private static func cgModifiers(from flags: NSEvent.ModifierFlags) -> CGEventFlags {
        var result: CGEventFlags = []
        if flags.contains(.command) { result.insert(.maskCommand) }
        if flags.contains(.control) { result.insert(.maskControl) }
        if flags.contains(.option) { result.insert(.maskAlternate) }
        if flags.contains(.shift) { result.insert(.maskShift) }
        if flags.contains(.function) { result.insert(.maskSecondaryFn) }
        return result
    }

    private static func isModifierKeyCode(_ keyCode: UInt16) -> Bool {
        let modifierKeyCodes: Set<UInt16> = [54, 55, 56, 57, 58, 59, 60, 61, 62, 63]
        return modifierKeyCodes.contains(keyCode)
    }
}

enum KeyCodeDisplay {
    private static let mapping: [UInt16: String] = [
        // Modifiers (for modifier-only bindings)
        54: "Right Cmd",
        55: "Cmd",
        56: "Shift",
        57: "Caps Lock",
        58: "Option",
        59: "Control",
        60: "Right Shift",
        61: "Right Option",
        62: "Right Control",
        63: "Fn",

        36: "Enter",
        48: "Tab",
        49: "Space",
        51: "Backspace",
        53: "Escape",
        123: "Left",
        124: "Right",
        125: "Down",
        126: "Up",
        115: "Home",
        119: "End",
        116: "Page Up",
        121: "Page Down",
        122: "F1",
        120: "F2",
        99: "F3",
        118: "F4",
        96: "F5",
        97: "F6",
        98: "F7",
        100: "F8",
        101: "F9",
        109: "F10",
        103: "F11",
        111: "F12",
        0: "A",
        1: "S",
        2: "D",
        3: "F",
        4: "H",
        5: "G",
        6: "Z",
        7: "X",
        8: "C",
        9: "V",
        11: "B",
        12: "Q",
        13: "W",
        14: "E",
        15: "R",
        16: "Y",
        17: "T",
        18: "1",
        19: "2",
        20: "3",
        21: "4",
        22: "6",
        23: "5",
        24: "=",
        25: "9",
        26: "7",
        27: "-",
        28: "8",
        29: "0",
        30: "]",
        31: "O",
        32: "U",
        33: "[",
        34: "I",
        35: "P",
        37: "L",
        38: "J",
        39: "'",
        40: "K",
        41: ";",
        42: "\\",
        43: ",",
        44: "/",
        45: "N",
        46: "M",
        47: ".",
        50: "`"
    ]

    static func name(for keyCode: UInt16) -> String {
        if let name = mapping[keyCode] {
            return name
        }
        return "KeyCode(\(keyCode))"
    }
}
