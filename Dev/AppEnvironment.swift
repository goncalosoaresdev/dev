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
    private var settingsWindow: SettingsWindowController?

    init() {
        dictation = DictationController(
            settings: settings,
            permissions: permissions,
            overlay: overlay,
            usage: usage
        )
    }

    func start() {
        hotkey.setHotkey(settings.hotkey)
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
        observeHotkey()
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
                self.observeHotkey()
            }
        }
    }

    func stop() {
        hotkey.stop()
        dictation.cancel()
        overlay.hide()
    }

    func openSettings() {
        if settingsWindow == nil {
            settingsWindow = SettingsWindowController(environment: self)
        }
        settingsWindow?.show()
    }
}
