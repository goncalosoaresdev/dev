import Carbon.HIToolbox
import Foundation
import Observation
import os

@MainActor
@Observable
final class ScreenshotHotkeyMonitor: @unchecked Sendable {
    nonisolated static let carbonSignature: OSType = 0x44565353 // DVSS
    nonisolated static let carbonID: UInt32 = 1

    var onTrigger: (@MainActor @Sendable () -> Void)?
    var paused = false
    private(set) var registrationError: String?

    private var hotkey = Hotkey.screenshotDefault
    private var hotkeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private var started = false

    func start() {
        guard !started else { return }
        started = true
        install()
    }

    func stop() {
        if let hotkeyRef { UnregisterEventHotKey(hotkeyRef) }
        if let handlerRef { RemoveEventHandler(handlerRef) }
        hotkeyRef = nil
        handlerRef = nil
        started = false
    }

    func setHotkey(_ hotkey: Hotkey) {
        self.hotkey = hotkey
        guard started else { return }
        stop()
        started = true
        install()
    }

    private func install() {
        registrationError = nil
        guard !hotkey.modifiersOnly else {
            registrationError = "Screenshot shortcuts must include a regular key."
            return
        }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let callback: EventHandlerUPP = { _, event, userData in
            guard let event, let userData,
                  GetEventKind(event) == UInt32(kEventHotKeyPressed),
                  ScreenshotHotkeyMonitor.owns(event) else {
                return OSStatus(eventNotHandledErr)
            }
            let monitor = Unmanaged<ScreenshotHotkeyMonitor>
                .fromOpaque(userData)
                .takeUnretainedValue()
            monitor.trigger()
            return noErr
        }

        var handler: EventHandlerRef?
        let handlerStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            callback,
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &handler
        )
        guard handlerStatus == noErr, let handler else {
            registrationError = "Couldn’t start the screenshot shortcut listener (\(handlerStatus))."
            Self.log.error("Carbon handler installation failed: \(handlerStatus)")
            return
        }
        handlerRef = handler

        let hotkeyID = EventHotKeyID(signature: Self.carbonSignature, id: Self.carbonID)
        var registered: EventHotKeyRef?
        let status = RegisterEventHotKey(
            UInt32(hotkey.keyCode),
            Self.carbonModifiers(for: hotkey.flags),
            hotkeyID,
            GetApplicationEventTarget(),
            0,
            &registered
        )
        if status == noErr {
            hotkeyRef = registered
        } else {
            RemoveEventHandler(handler)
            handlerRef = nil
            registrationError = "That screenshot shortcut is already used by macOS or another app."
            Self.log.error("Carbon hotkey registration failed: \(status)")
        }
    }

    nonisolated private func trigger() {
        Task { @MainActor [weak self] in
            guard let self, !self.paused else { return }
            self.onTrigger?()
        }
    }

    private static func carbonModifiers(for flags: CGEventFlags) -> UInt32 {
        var modifiers: UInt32 = 0
        if flags.contains(.maskControl) { modifiers |= UInt32(controlKey) }
        if flags.contains(.maskAlternate) { modifiers |= UInt32(optionKey) }
        if flags.contains(.maskShift) { modifiers |= UInt32(shiftKey) }
        if flags.contains(.maskCommand) { modifiers |= UInt32(cmdKey) }
        return modifiers
    }

    nonisolated static func owns(_ hotkeyID: EventHotKeyID) -> Bool {
        hotkeyID.signature == carbonSignature && hotkeyID.id == carbonID
    }

    nonisolated private static func owns(_ event: EventRef) -> Bool {
        var hotkeyID = EventHotKeyID(signature: 0, id: 0)
        let status = GetEventParameter(
            event,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &hotkeyID
        )
        return status == noErr && owns(hotkeyID)
    }

    private nonisolated static let log = Logger(
        subsystem: "com.goncalosoares.Dev",
        category: "screenshot-hotkey"
    )
}
