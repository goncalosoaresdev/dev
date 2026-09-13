import AppKit
import AVFoundation
import ApplicationServices
import CoreGraphics
import IOKit
import IOKit.hid
import Observation

@MainActor
@Observable
final class PermissionMonitor {
    private(set) var microphone: AVAuthorizationStatus
    private(set) var accessibilityTrusted: Bool
    private(set) var inputMonitoringTrusted: Bool
    private var eventTapActive = false

    var microphoneGranted: Bool {
        microphone == .authorized
    }

    init() {
        microphone = AVCaptureDevice.authorizationStatus(for: .audio)
        accessibilityTrusted = Self.accessibilityGranted()
        inputMonitoringTrusted = Self.listenEventsGranted()
    }

    func refresh() {
        microphone = AVCaptureDevice.authorizationStatus(for: .audio)
        accessibilityTrusted = Self.accessibilityGranted()
        inputMonitoringTrusted = eventTapActive || Self.listenEventsGranted()
    }

    func markEventTap(active: Bool) {
        eventTapActive = active
        inputMonitoringTrusted = active || Self.listenEventsGranted()
    }

    private static func listenEventsGranted() -> Bool {
        if IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted {
            return true
        }
        return CGPreflightListenEventAccess()
    }

    static func accessibilityGranted() -> Bool {
        if AXIsProcessTrusted() { return true }
        if IOHIDCheckAccess(kIOHIDRequestTypePostEvent) == kIOHIDAccessTypeGranted {
            return true
        }
        let system = AXUIElementCreateSystemWide()
        var value: AnyObject?
        let status = AXUIElementCopyAttributeValue(
            system,
            kAXFocusedApplicationAttribute as CFString,
            &value
        )
        return status == .success && value != nil
    }

    func requestMicrophone() async -> Bool {
        let granted = await AVCaptureDevice.requestAccess(for: .audio)
        microphone = AVCaptureDevice.authorizationStatus(for: .audio)
        return granted
    }

    func openMicrophoneSettings() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")
    }

    func openAccessibilitySettings() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
    }

    func requestInputMonitoring() {
        inputMonitoringTrusted = CGRequestListenEventAccess()
    }

    func openInputMonitoringSettings() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")
    }

    func revealAppInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
    }

    private func open(_ url: String) {
        if let parsed = URL(string: url) {
            NSWorkspace.shared.open(parsed)
        }
    }
}
