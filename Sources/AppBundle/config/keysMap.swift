import AppKit
import Common
import HotKey

extension Key: @unchecked @retroactive Sendable {}

let keyNotationToKeyCode: [String: Key] = [
    "sectionSign": .section,
    "0": .zero,
    "1": .one,
    "2": .two,
    "3": .three,
    "4": .four,
    "5": .five,
    "6": .six,
    "7": .seven,
    "8": .eight,
    "9": .nine,
    "minus": .minus,
    "equal": .equal,

    "q": .q,
    "w": .w,
    "e": .e,
    "r": .r,
    "t": .t,
    "y": .y,
    "u": .u,
    "i": .i,
    "o": .o,
    "p": .p,
    "leftSquareBracket": .leftBracket,
    "rightSquareBracket": .rightBracket,
    "backslash": .backslash,

    "a": .a,
    "s": .s,
    "d": .d,
    "f": .f,
    "g": .g,
    "h": .h,
    "j": .j,
    "k": .k,
    "l": .l,
    "semicolon": .semicolon,
    "quote": .quote,

    "z": .z,
    "x": .x,
    "c": .c,
    "v": .v,
    "b": .b,
    "n": .n,
    "m": .m,
    "comma": .comma,
    "period": .period,
    "slash": .slash,

    "keypad0": .keypad0,
    "keypad1": .keypad1,
    "keypad2": .keypad2,
    "keypad3": .keypad3,
    "keypad4": .keypad4,
    "keypad5": .keypad5,
    "keypad6": .keypad6,
    "keypad7": .keypad7,
    "keypad8": .keypad8,
    "keypad9": .keypad9,
    "keypadClear": .keypadClear,
    "keypadDecimalMark": .keypadDecimal,
    "keypadDivide": .keypadDivide,
    "keypadEnter": .keypadEnter,
    "keypadEqual": .keypadEquals,
    "keypadMinus": .keypadMinus,
    "keypadMultiply": .keypadMultiply,
    "keypadPlus": .keypadPlus,

    "pageUp": .pageUp,
    "pageDown": .pageDown,
    "home": .home,
    "end": .end,
    "forwardDelete": .forwardDelete,

    "f1": .f1,
    "f2": .f2,
    "f3": .f3,
    "f4": .f4,
    "f5": .f5,
    "f6": .f6,
    "f7": .f7,
    "f8": .f8,
    "f9": .f9,
    "f10": .f10,
    "f11": .f11,
    "f12": .f12,
    "f13": .f13,
    "f14": .f14,
    "f15": .f15,
    "f16": .f16,
    "f17": .f17,
    "f18": .f18,
    "f19": .f19,
    "f20": .f20,

    "backtick": .grave,
    "space": .space,
    "enter": .return,
    "esc": .escape,
    "backspace": .delete,
    "tab": .tab,

    "left": .leftArrow,
    "down": .downArrow,
    "up": .upArrow,
    "right": .rightArrow,
]

let modifiersMap: [String: NSEvent.ModifierFlags] = [
    "shift": .shift,
    "alt": .option,
    "ctrl": .control,
    "cmd": .command,
]

extension NSEvent.ModifierFlags {
    func toString() -> String {
        var result: [String] = []
        if contains(.option) { result.append("alt") }
        if contains(.control) { result.append("ctrl") }
        if contains(.command) { result.append("cmd") }
        if contains(.shift) { result.append("shift") }
        return result.joined(separator: "-")
    }
}

extension Key {
    func toString() -> String {
        switch self {
        case .a: "a"
        case .b: "b"
        case .c: "c"
        case .d: "d"
        case .e: "e"
        case .f: "f"
        case .g: "g"
        case .h: "h"
        case .i: "i"
        case .j: "j"
        case .k: "k"
        case .l: "l"
        case .m: "m"
        case .n: "n"
        case .o: "o"
        case .p: "p"
        case .q: "q"
        case .r: "r"
        case .s: "s"
        case .t: "t"
        case .u: "u"
        case .v: "v"
        case .w: "w"
        case .x: "x"
        case .y: "y"
        case .z: "z"

        case .zero: "0"
        case .one: "1"
        case .two: "2"
        case .three: "3"
        case .four: "4"
        case .five: "5"
        case .six: "6"
        case .seven: "7"
        case .eight: "8"
        case .nine: "9"

        case .period: "period"
        case .quote: "quote"
        case .leftBracket: "leftSquareBracket"
        case .rightBracket: "rightSquareBracket"
        case .semicolon: "semicolon"
        case .slash: "slash"
        case .backslash: "backslash"
        case .comma: "comma"
        case .equal: "equal"
        case .grave: "backtick"
        case .minus: "minus"
        case .space: "space"
        case .tab: "tab"
        case .return: "enter"
        case .pageUp: "pageUp"
        case .pageDown: "pageDown"
        case .home: "home"
        case .end: "end"
        case .leftArrow: "left"
        case .downArrow: "down"
        case .upArrow: "up"
        case .rightArrow: "right"
        case .escape: "esc"
        case .delete: "backspace"
        case .section: "sectionSign"

        case .f1: "f1"
        case .f2: "f2"
        case .f3: "f3"
        case .f4: "f4"
        case .f5: "f5"
        case .f6: "f6"
        case .f7: "f7"
        case .f8: "f8"
        case .f9: "f9"
        case .f10: "f10"
        case .f11: "f11"
        case .f12: "f12"
        case .f13: "f13"
        case .f14: "f14"
        case .f15: "f15"
        case .f16: "f16"
        case .f17: "f17"
        case .f18: "f18"
        case .f19: "f19"
        case .f20: "f20"

        case .keypad0: "keypad0"
        case .keypad1: "keypad1"
        case .keypad2: "keypad2"
        case .keypad3: "keypad3"
        case .keypad4: "keypad4"
        case .keypad5: "keypad5"
        case .keypad6: "keypad6"
        case .keypad7: "keypad7"
        case .keypad8: "keypad8"
        case .keypad9: "keypad9"
        case .keypadClear: "keypadClear"
        case .keypadDecimal: "keypadDecimalMark"
        case .keypadDivide: "keypadDivide"
        case .keypadEnter: "keypadEnter"
        case .keypadEquals: "keypadEqual"
        case .keypadMinus: "keypadMinus"
        case .keypadMultiply: "keypadMultiply"
        case .keypadPlus: "keypadPlus"

        // wtf
        case .command: "cmd"
        case .rightCommand: "rCmd"
        case .option: "alt"
        case .rightOption: "rAlt"
        case .control: "ctrl"
        case .rightControl: "rCtrl"
        case .shift: "shift"
        case .rightShift: "rShift"
        case .function: "function"
        case .capsLock: "capsLock"
        case .forwardDelete: "forwardDelete"
        case .help: "help"
        case .volumeUp: "volumeUp"
        case .volumeDown: "volumeDown"
        case .mute: "mute"
        }
    }
}
