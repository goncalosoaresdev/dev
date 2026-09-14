import AppKit
import ApplicationServices
import CoreGraphics

enum InsertResult: Equatable, Sendable {
    case pasted
    case copied
}

@MainActor
enum TextInserter {
    static var onPasteboardMutation: (() -> Void)?

    private static var generation = 0
    private static let transientType = NSPasteboard.PasteboardType("org.nspasteboard.TransientType")

    static func insert(_ text: String, into target: NSRunningApplication?) async -> InsertResult {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .copied }

        generation += 1
        let generation = self.generation
        let pasteboard = NSPasteboard.general
        let previous = snapshot(pasteboard)
        write(trimmed, onto: pasteboard, transient: true)
        let writtenCount = pasteboard.changeCount
        onPasteboardMutation?()

        resignOurWindows()
        if let target, !target.isTerminated,
           target.bundleIdentifier != Bundle.main.bundleIdentifier {
            _ = target.activate(options: [])
            try? await Task.sleep(for: .milliseconds(80))
        }

        let pasted = insertViaAccessibility(trimmed) || postPaste()

        if pasted {
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(1.2))
                guard self.generation == generation else { return }
                guard pasteboard.changeCount == writtenCount else { return }
                restore(previous, onto: pasteboard)
                onPasteboardMutation?()
            }
            return .pasted
        }

        write(trimmed, onto: pasteboard, transient: false)
        onPasteboardMutation?()
        return .copied
    }

    private static func write(_ text: String, onto pasteboard: NSPasteboard, transient: Bool) {
        pasteboard.clearContents()
        let item = NSPasteboardItem()
        item.setString(text, forType: .string)
        if transient {
            item.setString("", forType: transientType)
        }
        pasteboard.writeObjects([item])
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
