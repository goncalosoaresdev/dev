import AppKit
import Observation
import SwiftUI

@MainActor
final class MenuBarController: NSObject, NSPopoverDelegate {
    private let environment: AppEnvironment
    private let item: NSStatusItem
    private let popover = NSPopover()
    private var closeWaiters: [CheckedContinuation<Void, Never>] = []

    init(environment: AppEnvironment) {
        self.environment = environment
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        if let button = item.button {
            button.image = Self.icon(recording: false)
            button.image?.isTemplate = true
            button.imagePosition = .imageOnly
            button.action = #selector(togglePopover)
            button.target = self
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        popover.behavior = .semitransient
        popover.animates = true
        popover.delegate = self
        popover.contentSize = NSSize(width: 340, height: 360)
        popover.contentViewController = NSHostingController(
            rootView: MenuPopoverView(
                environment: environment,
                onOpenSettings: { [weak self] in
                    self?.openSettings()
                },
                onInsertClip: { [weak self] item in
                    Task { @MainActor in
                        await self?.insertClip(item)
                    }
                }
            )
        )

        observePhase()
        observeScreenshotPhase()
    }

    @objc private func togglePopover(_ sender: NSStatusBarButton) {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showMenu()
            return
        }
        guard let button = item.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            environment.clipboard.rememberFrontmostApp()
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }

    private func showMenu() {
        let menu = NSMenu()
        menu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Dev", action: #selector(quit), keyEquivalent: "q")
        for entry in menu.items {
            entry.target = self
        }
        item.menu = menu
        item.button?.performClick(nil)
        item.menu = nil
    }

    @objc private func openSettings() {
        popover.performClose(nil)
        DispatchQueue.main.async { [environment] in
            environment.openSettings()
        }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    func popoverDidClose(_ notification: Notification) {
        finishCloseWaiters()
    }

    private func insertClip(_ item: ClipboardItem) async {
        await closePopover()
        _ = await environment.clipboard.insert(item)
    }

    private func closePopover() async {
        guard popover.isShown else { return }
        await withCheckedContinuation { continuation in
            closeWaiters.append(continuation)
            let wasAnimating = popover.animates
            popover.animates = false
            popover.performClose(nil)
            popover.animates = wasAnimating
            if !popover.isShown {
                finishCloseWaiters()
            } else {
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(250))
                    self.finishCloseWaiters()
                }
            }
        }
    }

    private func finishCloseWaiters() {
        let waiters = closeWaiters
        closeWaiters.removeAll()
        waiters.forEach { $0.resume() }
    }

    private func observePhase() {
        withObservationTracking {
            _ = environment.dictation.phase
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.applyIcon()
                self?.observePhase()
            }
        }
        applyIcon()
    }

    private func observeScreenshotPhase() {
        withObservationTracking {
            _ = environment.screenshots.phase
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                if self.environment.screenshots.phase == .selecting {
                    self.popover.performClose(nil)
                }
                self.observeScreenshotPhase()
            }
        }
    }

    private func applyIcon() {
        let recording = environment.dictation.phase == .starting
            || environment.dictation.phase == .recording
            || environment.dictation.phase == .finishing
        item.button?.image = Self.icon(recording: recording)
        item.button?.image?.isTemplate = true
        item.button?.contentTintColor = nil
    }

    private static func icon(recording: Bool) -> NSImage? {
        let name = recording ? "waveform.circle.fill" : "waveform"
        let image = NSImage(systemSymbolName: name, accessibilityDescription: "Dev")
        return image?.withSymbolConfiguration(.init(pointSize: 14, weight: .medium))
    }
}
