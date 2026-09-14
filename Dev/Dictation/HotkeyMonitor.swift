import AppKit
import Carbon.HIToolbox
import CoreGraphics
import Foundation
import os

final class HotkeyMonitor: NSObject, @unchecked Sendable {
    static let carbonSignature: OSType = 0x44455648 // DEVH
    static let carbonID: UInt32 = 1

    var onBegin: (@MainActor @Sendable () -> Void)?
    var onEnd: (@MainActor @Sendable () -> Void)?
    var onCancel: (@MainActor @Sendable () -> Void)?
    var onTapFailed: (@MainActor @Sendable () -> Void)?
    var onTapReady: (@MainActor @Sendable () -> Void)?

    var isListening: Bool {
        lock.withLock { tap != nil || globalMonitor != nil }
    }

    var paused: Bool {
        get { lock.withLock { _paused } }
        set {
            let shouldCancel = lock.withLock { () -> Bool in
                let wasActive = isDown || pendingModifierBegin
                _paused = newValue
                if newValue {
                    isDown = false
                    pendingModifierBegin = false
                    pendingBeginGeneration &+= 1
                }
                return newValue && wasActive
            }
            if shouldCancel { fire(onCancel) }
        }
    }

    func setHotkey(_ hotkey: Hotkey) {
        lock.withLock {
            _hotkey = hotkey
            pendingModifierBegin = false
            pendingBeginGeneration &+= 1
        }
        DispatchQueue.main.async { [weak self] in
            self?.refreshCarbonHotkey()
        }
    }

    func setReservedKeyedHotkeys(_ hotkeys: [Hotkey]) {
        lock.withLock {
            reservedKeyedHotkeys = hotkeys.filter { !$0.modifiersOnly }
            pendingModifierBegin = false
            pendingBeginGeneration &+= 1
        }
    }

    private var thread: Thread?
    private var runLoop: CFRunLoop?
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var tapConsumes = false
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var carbonHotkey: EventHotKeyRef?
    private var carbonHandler: EventHandlerRef?
    private var isDown = false
    private var pendingModifierBegin = false
    private var pendingBeginGeneration: UInt64 = 0
    private var reservedKeyedHotkeys: [Hotkey] = []
    private var _paused = false
    private var started = false
    private var _hotkey = Hotkey.controlOption
    private let lock = NSLock()
    private let log = Logger(subsystem: "com.goncalosoares.Dev", category: "hotkey")

    func start() {
        let shouldStart = lock.withLock { () -> Bool in
            guard !started else { return false }
            started = true
            return true
        }
        guard shouldStart else { return }

        paused = false
        DispatchQueue.main.async { [weak self] in
            self?.refreshCarbonHotkey()
        }
        startTapThreadIfNeeded()
    }

    private func startTapThreadIfNeeded() {
        lock.lock()
        let alreadyRunning = thread != nil || tap != nil
        lock.unlock()
        guard !alreadyRunning else { return }

        let worker = Thread(target: self, selector: #selector(runTapLoop), object: nil)
        worker.name = "dev.hotkey"
        worker.qualityOfService = .userInteractive
        lock.lock()
        thread = worker
        lock.unlock()
        worker.start()
    }

    func stop() {
        lock.lock()
        let tap = self.tap
        let source = self.source
        let runLoop = self.runLoop
        let globalMonitor = self.globalMonitor
        let localMonitor = self.localMonitor
        self.tap = nil
        self.source = nil
        self.runLoop = nil
        self.thread = nil
        self.globalMonitor = nil
        self.localMonitor = nil
        let carbonHotkey = self.carbonHotkey
        let carbonHandler = self.carbonHandler
        self.carbonHotkey = nil
        self.carbonHandler = nil
        started = false
        isDown = false
        tapConsumes = false
        lock.unlock()

        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let runLoop {
            if let source {
                CFRunLoopRemoveSource(runLoop, source, .commonModes)
            }
            CFRunLoopStop(runLoop)
        }
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
        }
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
        }
        if let carbonHotkey {
            UnregisterEventHotKey(carbonHotkey)
        }
        if let carbonHandler {
            RemoveEventHandler(carbonHandler)
        }
    }

    @MainActor
    private func refreshCarbonHotkey() {
        let state = lock.withLock { (started, _hotkey) }

        if let carbonHotkey {
            UnregisterEventHotKey(carbonHotkey)
            self.carbonHotkey = nil
        }
        if let carbonHandler {
            RemoveEventHandler(carbonHandler)
            self.carbonHandler = nil
        }

        guard state.0, !state.1.modifiersOnly else { return }

        var eventTypes = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased))
        ]
        let callback: EventHandlerUPP = { _, event, userData in
            guard let event, let userData else { return OSStatus(eventNotHandledErr) }
            guard HotkeyMonitor.owns(event) else { return OSStatus(eventNotHandledErr) }
            let monitor = Unmanaged<HotkeyMonitor>.fromOpaque(userData).takeUnretainedValue()
            switch GetEventKind(event) {
            case UInt32(kEventHotKeyPressed):
                monitor.carbonPressed()
            case UInt32(kEventHotKeyReleased):
                monitor.carbonReleased()
            default:
                return OSStatus(eventNotHandledErr)
            }
            return noErr
        }

        var handler: EventHandlerRef?
        let handlerStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            callback,
            eventTypes.count,
            &eventTypes,
            Unmanaged.passUnretained(self).toOpaque(),
            &handler
        )
        guard handlerStatus == noErr, let handler else {
            log.error("Carbon hotkey handler failed: \(handlerStatus)")
            return
        }
        carbonHandler = handler

        let hotkeyID = EventHotKeyID(signature: Self.carbonSignature, id: Self.carbonID)
        var hotkeyRef: EventHotKeyRef?
        let registerStatus = RegisterEventHotKey(
            UInt32(state.1.keyCode),
            Self.carbonModifiers(for: state.1.flags),
            hotkeyID,
            GetApplicationEventTarget(),
            0,
            &hotkeyRef
        )
        guard registerStatus == noErr, let hotkeyRef else {
            log.error("Carbon hotkey registration failed: \(registerStatus)")
            RemoveEventHandler(handler)
            carbonHandler = nil
            return
        }
        carbonHotkey = hotkeyRef
        log.info("Carbon hotkey registered: \(state.1.display, privacy: .public)")
    }

    private static func carbonModifiers(for flags: CGEventFlags) -> UInt32 {
        var modifiers: UInt32 = 0
        if flags.contains(.maskControl) { modifiers |= UInt32(controlKey) }
        if flags.contains(.maskAlternate) { modifiers |= UInt32(optionKey) }
        if flags.contains(.maskShift) { modifiers |= UInt32(shiftKey) }
        if flags.contains(.maskCommand) { modifiers |= UInt32(cmdKey) }
        return modifiers
    }

    static func owns(_ hotkeyID: EventHotKeyID) -> Bool {
        hotkeyID.signature == carbonSignature && hotkeyID.id == carbonID
    }

    private static func owns(_ event: EventRef) -> Bool {
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

    private func carbonPressed() {
        let shouldBegin = lock.withLock { () -> Bool in
            guard !_paused, !isDown else { return false }
            isDown = true
            return true
        }
        if shouldBegin {
            log.info("hotkey began")
            fire(onBegin)
        }
    }

    private func carbonReleased() {
        let shouldEnd = lock.withLock { () -> Bool in
            guard !_paused, isDown else { return false }
            isDown = false
            return true
        }
        if shouldEnd {
            log.info("hotkey ended")
            fire(onEnd)
        }
    }

    @objc private func runTapLoop() {
        installHIDTap()
        if lock.withLock({ tap != nil }) {
            removeGlobalMonitor()
            fire(onTapReady)
            CFRunLoopRun()
        } else {
            lock.withLock { thread = nil }
            installGlobalMonitor()
        }
    }

    private func installHIDTap() {
        let mask: CGEventMask =
            (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.keyUp.rawValue) |
            (1 << CGEventType.flagsChanged.rawValue)
        let refcon = Unmanaged.passUnretained(self).toOpaque()

        let attempts: [(CGEventTapLocation, CGEventTapOptions)] = [
            (.cghidEventTap, .defaultTap),
            (.cgSessionEventTap, .defaultTap),
            (.cghidEventTap, .listenOnly),
            (.cgSessionEventTap, .listenOnly)
        ]

        for (location, options) in attempts {
            guard let tap = CGEvent.tapCreate(
                tap: location,
                place: .headInsertEventTap,
                options: options,
                eventsOfInterest: mask,
                callback: { _, type, event, refcon in
                    guard let refcon else { return Unmanaged.passUnretained(event) }
                    let monitor = Unmanaged<HotkeyMonitor>.fromOpaque(refcon).takeUnretainedValue()
                    let consume = monitor.process(
                        type: type,
                        keyCode: UInt16(event.getIntegerValueField(.keyboardEventKeycode)),
                        flags: event.flags
                    )
                    if consume, monitor.lock.withLock({ monitor.tapConsumes }) {
                        return nil
                    }
                    return Unmanaged.passUnretained(event)
                },
                userInfo: refcon
            ) else {
                continue
            }

            let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
            let loop = CFRunLoopGetCurrent()
            CFRunLoopAddSource(loop, source, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
            lock.lock()
            self.tap = tap
            self.source = source
            self.runLoop = loop
            self.tapConsumes = options == .defaultTap
            lock.unlock()
            log.info("HID tap installed")
            return
        }
    }

    private func installGlobalMonitor() {
        if lock.withLock({ globalMonitor != nil }) { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, self.lock.withLock({ self.globalMonitor == nil }) else { return }
            let global = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown, .keyUp, .flagsChanged]) { [weak self] event in
                self?.processNSEvent(event)
            }
            self.lock.lock()
            self.globalMonitor = global
            self.lock.unlock()
            if global != nil, CGPreflightListenEventAccess() || AXIsProcessTrusted() {
                self.fire(self.onTapReady)
            } else {
                self.log.error("Global keyboard monitor is not authorized")
                self.fire(self.onTapFailed)
            }
        }
    }

    private func removeGlobalMonitor() {
        let monitor = lock.withLock { () -> Any? in
            let monitor = globalMonitor
            globalMonitor = nil
            return monitor
        }
        if let monitor {
            DispatchQueue.main.async {
                NSEvent.removeMonitor(monitor)
            }
        }
    }

    @discardableResult
    private func processNSEvent(_ event: NSEvent) -> Bool {
        let type: CGEventType
        switch event.type {
        case .keyDown: type = .keyDown
        case .keyUp: type = .keyUp
        case .flagsChanged: type = .flagsChanged
        default: return false
        }
        return process(type: type, keyCode: event.keyCode, flags: event.modifierFlags.cgEventFlags)
    }

    @discardableResult
    private func process(type: CGEventType, keyCode: UInt16, flags: CGEventFlags) -> Bool {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = lock.withLock({ self.tap }) {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return false
        }

        enum Transition {
            case none, begin, delayedBegin(UInt64), end, cancel
        }

        let result: (Transition, Bool) = lock.withLock {
            if _paused { return (.none, false) }

            let relevant = flags.hotkeyRelevant
            if reservedKeyedHotkeys.contains(where: {
                $0.matchesKeyDown(type: type, keyCode: keyCode, flags: relevant)
            }) {
                pendingModifierBegin = false
                pendingBeginGeneration &+= 1
                if isDown {
                    isDown = false
                    return (.cancel, false)
                }
                return (.none, false)
            }
            if isDown, type == .keyDown, keyCode == 53 {
                isDown = false
                return (.cancel, true)
            }

            let held = _hotkey.isActive(
                type: type,
                keyCode: keyCode,
                flags: relevant,
                wasDown: isDown
            )
            if held, !isDown {
                if _hotkey.modifiersOnly {
                    guard type == .flagsChanged else { return (.none, false) }
                    let hasReservedChord = reservedKeyedHotkeys.contains {
                        $0.isKeyedChord(using: relevant)
                    }
                    if hasReservedChord {
                        if pendingModifierBegin { return (.none, false) }
                        pendingModifierBegin = true
                        pendingBeginGeneration &+= 1
                        return (.delayedBegin(pendingBeginGeneration), false)
                    }
                }
                isDown = true
                return (.begin, true)
            }
            if !held, isDown {
                isDown = false
                return (.end, true)
            }
            if !held, pendingModifierBegin {
                pendingModifierBegin = false
                pendingBeginGeneration &+= 1
            }
            return (.none, held)
        }

        switch result.0 {
        case .none: break
        case .begin: fire(onBegin)
        case .delayedBegin(let generation): scheduleModifierBegin(generation: generation)
        case .end: fire(onEnd)
        case .cancel: fire(onCancel)
        }
        return result.1
    }

    private func scheduleModifierBegin(generation: UInt64) {
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(160)) { [weak self] in
            guard let self else { return }
            let shouldBegin = self.lock.withLock { () -> Bool in
                guard !self._paused,
                      self.pendingModifierBegin,
                      self.pendingBeginGeneration == generation else { return false }
                self.pendingModifierBegin = false
                self.isDown = true
                return true
            }
            if shouldBegin { self.fire(self.onBegin) }
        }
    }

    private func fire(_ handler: (@MainActor @Sendable () -> Void)?) {
        guard let handler else { return }
        DispatchQueue.main.async { handler() }
    }
}
