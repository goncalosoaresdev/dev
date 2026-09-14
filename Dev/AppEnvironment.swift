import AppKit
import Observation

@MainActor
@Observable
final class AppEnvironment {
    let settings = SettingsStore()
    let permissions = PermissionMonitor()
    let overlay = OverlayController()
    let usage = UsageStore()
    let dictation: DictationController
    let hotkey = HotkeyMonitor()
    let screenshots: ScreenshotController
    let screenshotHotkey = ScreenshotHotkeyMonitor()
    private var settingsWindow: SettingsWindowController?

    init() {
        dictation = DictationController(
            settings: settings,
            permissions: permissions,
            overlay: overlay,
            usage: usage
        )
        screenshots = ScreenshotController(settings: settings, permissions: permissions)
    }

    func start() {
        hotkey.setHotkey(settings.hotkey)
        hotkey.setReservedKeyedHotkeys([settings.screenshotHotkey])
        hotkey.onBegin = { [dictation, settings] in
            guard settings.dictationEnabled else { return }
            if settings.pushToTalkMode == .toggle, dictation.phase == .recording {
                dictation.end()
            } else {
                dictation.begin()
            }
        }
        hotkey.onEnd = { [dictation, settings] in
            guard settings.dictationEnabled, settings.pushToTalkMode == .hold else { return }
            dictation.end()
        }
        hotkey.onCancel = { [dictation] in dictation.cancel() }
        hotkey.onTapReady = { [permissions] in
            permissions.markEventTap(active: true)
        }
        hotkey.onTapFailed = { [permissions] in
            permissions.markEventTap(active: false)
        }
        hotkey.start()
        screenshotHotkey.setHotkey(settings.screenshotHotkey)
        screenshotHotkey.onTrigger = { [dictation, screenshots, settings] in
            guard settings.screenshotsEnabled else { return }
            dictation.cancel()
            screenshots.beginSelection()
        }
        screenshotHotkey.start()
        observeHotkey()
        observeScreenshotHotkey()
        permissions.refresh()
        if settings.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            DispatchQueue.main.async { [weak self] in
                self?.openSettings()
            }
        }
    }

    private func observeHotkey() {
        withObservationTracking {
            _ = settings.hotkey
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.hotkey.setHotkey(self.settings.hotkey)
                self.hotkey.setReservedKeyedHotkeys([self.settings.screenshotHotkey])
                self.observeHotkey()
            }
        }
    }

    private func observeScreenshotHotkey() {
        withObservationTracking {
            _ = settings.screenshotHotkey
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.screenshotHotkey.setHotkey(self.settings.screenshotHotkey)
                self.hotkey.setReservedKeyedHotkeys([self.settings.screenshotHotkey])
                self.observeScreenshotHotkey()
            }
        }
    }

    func stop() {
        hotkey.stop()
        screenshotHotkey.stop()
        dictation.cancel()
        screenshots.cancel()
        overlay.hide()
    }

    func openSettings() {
        if settingsWindow == nil {
            settingsWindow = SettingsWindowController(environment: self)
        }
        settingsWindow?.show()
    }
}
