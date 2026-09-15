import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private weak var environment: AppEnvironment?
    private var window: NSWindow?

    init(environment: AppEnvironment) {
        self.environment = environment
        super.init()
    }

    func show() {
        guard let environment else { return }
        NSApp.setActivationPolicy(.regular)
        ApplicationIcon.refresh()
        NSApp.activate(ignoringOtherApps: true)

        if window == nil {
            window = makeWindow(environment: environment)
        }

        guard let window else { return }
        if !window.isVisible {
            window.center()
        }
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        window.makeFirstResponder(window.contentView)
    }

    func windowWillClose(_ notification: Notification) {
        environment?.hotkey.paused = false
        NSApp.setActivationPolicy(.accessory)
    }

    private func makeWindow(environment: AppEnvironment) -> NSWindow {
        let root = SettingsView()
            .environment(environment)
        let hosting = NSHostingController(rootView: root)
        hosting.preferredContentSize = NSSize(width: 760, height: 620)

        let window = NSWindow(contentViewController: hosting)
        window.title = "Dev Settings"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(hosting.preferredContentSize)
        window.minSize = NSSize(width: 700, height: 560)
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        window.level = .normal
        return window
    }
}
