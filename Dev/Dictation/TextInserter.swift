import AppKit
import ApplicationServices
import CoreGraphics

enum InsertResult: Equatable, Sendable {
    case pasted
    case copied
}

@MainActor
enum TextInserter {
    static func insert(_ text: String, into target: NSRunningApplication?) async -> InsertResult {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .copied }

        let pasteboard = NSPasteboard.general
        let previous = snapshot(pasteboard)
        pasteboard.clearContents()
        pasteboard.setString(trimmed, forType: .string)

        resignOurWindows()
        if let target, target.bundleIdentifier != Bundle.main.bundleIdentifier {
            _ = target.activate(options: [.activateIgnoringOtherApps])
            try? await Task.sleep(for: .milliseconds(80))
        }

        let pasted = insertViaAccessibility(trimmed) || postPaste()

        if pasted {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                restore(previous, onto: pasteboard)
            }
            return .pasted
        }

        return .copied
    }

    private static func resignOurWindows() {
        for window in NSApp.windows {
            guard window.title == "Dev Settings" || window.level == .floating else { continue }
            window.orderBack(nil)
        }
        NSApp.setActivationPolicy(.accessory)
    }

    private static func insertViaAccessibility(_ text: String) -> Bool {
        let system = AXUIElementCreateSystemWide()
        var focused: AnyObject?
        guard AXUIElementCopyAttributeValue(
            system,
            kAXFocusedUIElementAttribute as CFString,
            &focused
        ) == .success,
            let focused
        else {
            return false
        }

        let element = focused as! AXUIElement
        if AXUIElementSetAttributeValue(
            element,
            kAXSelectedTextAttribute as CFString,
            text as CFTypeRef
        ) == .success {
            return true
        }
        return false
    }

    @discardableResult
    private static func postPaste() -> Bool {
        guard let source = CGEventSource(stateID: .hidSystemState) else { return false }
        source.localEventsSuppressionInterval = 0

        guard let down = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false)
        else {
            return false
        }
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
        return true
    }

    private static func snapshot(_ pasteboard: NSPasteboard) -> [[NSPasteboard.PasteboardType: Data]] {
        pasteboard.pasteboardItems?.compactMap { item in
            var values: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) {
                    values[type] = data
                }
            }
            return values.isEmpty ? nil : values
        } ?? []
    }

    private static func restore(
        _ items: [[NSPasteboard.PasteboardType: Data]],
        onto pasteboard: NSPasteboard
    ) {
        guard !items.isEmpty else { return }
        pasteboard.clearContents()
        for values in items {
            let item = NSPasteboardItem()
            for (type, data) in values {
                item.setData(data, forType: type)
            }
            pasteboard.writeObjects([item])
        }
    }
}
