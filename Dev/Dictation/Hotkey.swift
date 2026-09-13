import AppKit
import CoreGraphics
import Foundation

struct Hotkey: Codable, Equatable, Sendable {
    var keyCode: UInt16
    var modifiers: UInt64
    var modifiersOnly: Bool

    static let controlOption = Hotkey(
        keyCode: 0,
        modifiers: CGEventFlags.maskControl.rawValue | CGEventFlags.maskAlternate.rawValue,
        modifiersOnly: true
    )

    var flags: CGEventFlags {
        CGEventFlags(rawValue: modifiers)
    }

    var display: String {
        var parts: [String] = []
        let flags = self.flags
        if flags.contains(.maskControl) { parts.append("⌃") }
        if flags.contains(.maskAlternate) { parts.append("⌥") }
        if flags.contains(.maskShift) { parts.append("⇧") }
        if flags.contains(.maskCommand) { parts.append("⌘") }
        if flags.contains(.maskSecondaryFn) { parts.append("fn") }
        if !modifiersOnly {
            parts.append(Self.keyName(keyCode))
        }
        return parts.isEmpty ? "None" : parts.joined()
    }

    func isHeld(flags: CGEventFlags, keyIsDown: (UInt16) -> Bool) -> Bool {
        let current = flags.hotkeyRelevant
        let wanted = self.flags.hotkeyRelevant
        guard current == wanted else { return false }
        if modifiersOnly { return true }
        return keyIsDown(keyCode)
    }

    func isActive(type: CGEventType, keyCode: UInt16, flags: CGEventFlags, wasDown: Bool) -> Bool {
        let wanted = self.flags.hotkeyRelevant
        if modifiersOnly {
            return flags == wanted
        }
        switch type {
        case .keyDown:
            if keyCode == self.keyCode, flags == wanted { return true }
            return wasDown && flags == wanted
        case .keyUp:
            if keyCode == self.keyCode { return false }
            return wasDown && flags == wanted
        case .flagsChanged:
            return wasDown && flags == wanted
        default:
            return wasDown
        }
    }

    static func from(event: NSEvent) -> Hotkey? {
        if event.keyCode == 53 { return nil }
        let flags = event.modifierFlags.cgEventFlags.hotkeyRelevant
        let isModifierKey = Self.modifierKeyCodes.contains(event.keyCode)
        if isModifierKey {
            guard !flags.isEmpty else { return nil }
            return Hotkey(keyCode: 0, modifiers: flags.rawValue, modifiersOnly: true)
        }
        guard !flags.isEmpty else { return nil }
        return Hotkey(keyCode: event.keyCode, modifiers: flags.rawValue, modifiersOnly: false)
    }

    static func from(flagsChanged event: NSEvent) -> Hotkey? {
        let flags = event.modifierFlags.cgEventFlags.hotkeyRelevant
        guard !flags.isEmpty else { return nil }
        return Hotkey(keyCode: 0, modifiers: flags.rawValue, modifiersOnly: true)
    }

    private static let modifierKeyCodes: Set<UInt16> = [54, 55, 56, 57, 58, 59, 60, 61, 62, 63]

    static func keyName(_ code: UInt16) -> String {
        names[code] ?? "Key \(code)"
    }

    private static let names: [UInt16: String] = [
        0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C", 9: "V",
        11: "B", 12: "Q", 13: "W", 14: "E", 15: "R", 16: "Y", 17: "T", 31: "O", 32: "U",
        34: "I", 35: "P", 37: "L", 38: "J", 40: "K", 45: "N", 46: "M",
        18: "1", 19: "2", 20: "3", 21: "4", 22: "6", 23: "5", 26: "7", 28: "8", 25: "9", 29: "0",
        36: "↩", 48: "⇥", 49: "Space", 51: "⌫", 53: "Esc",
        123: "←", 124: "→", 125: "↓", 126: "↑"
    ]
}

extension CGEventFlags {
    var hotkeyRelevant: CGEventFlags {
        intersection([.maskShift, .maskControl, .maskAlternate, .maskCommand, .maskSecondaryFn])
    }
}

extension NSEvent.ModifierFlags {
    var cgEventFlags: CGEventFlags {
        var flags: CGEventFlags = []
        if contains(.shift) { flags.insert(.maskShift) }
        if contains(.control) { flags.insert(.maskControl) }
        if contains(.option) { flags.insert(.maskAlternate) }
        if contains(.command) { flags.insert(.maskCommand) }
        if contains(.function) { flags.insert(.maskSecondaryFn) }
        return flags
    }
}
