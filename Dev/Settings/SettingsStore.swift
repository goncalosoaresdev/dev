import Foundation
import Observation
import ServiceManagement

@MainActor
@Observable
final class SettingsStore {
    var providerID: String {
        didSet { defaults.set(providerID, forKey: Keys.providerID) }
    }

    var dictationEnabled: Bool {
        didSet { defaults.set(dictationEnabled, forKey: Keys.dictationEnabled) }
    }

    var pushToTalkMode: PushToTalkMode {
        didSet { defaults.set(pushToTalkMode.rawValue, forKey: Keys.pushToTalkMode) }
    }

    var screenshotsEnabled: Bool {
        didSet { defaults.set(screenshotsEnabled, forKey: Keys.screenshotsEnabled) }
    }

    var clipboardEnabled: Bool {
        didSet { defaults.set(clipboardEnabled, forKey: Keys.clipboardEnabled) }
    }

    var screenshotHotkey: Hotkey {
        didSet { saveScreenshotHotkey() }
    }

    var hotkey: Hotkey {
        didSet { saveHotkey() }
    }

    var apiKey: String {
        didSet { KeychainStore.set(Keys.apiKey, apiKey.trimmingCharacters(in: .whitespacesAndNewlines)) }
    }

    var keywords: String {
        didSet { defaults.set(keywords, forKey: Keys.keywords) }
    }

    var languageBias: String {
        didSet { defaults.set(languageBias, forKey: Keys.languageBias) }
    }

    var soundEnabled: Bool {
        didSet { defaults.set(soundEnabled, forKey: Keys.soundEnabled) }
    }

    var launchAtLogin: Bool {
        didSet { applyLaunchAtLogin() }
    }

    var keywordList: [String] {
        keywords
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    var languageBiasList: [String] {
        let value = languageBias.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? [] : [value]
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        providerID = defaults.string(forKey: Keys.providerID) ?? ProviderRegistry.all[0].id
        keywords = defaults.string(forKey: Keys.keywords) ?? ""
        languageBias = defaults.string(forKey: Keys.languageBias) ?? ""
        soundEnabled = defaults.object(forKey: Keys.soundEnabled) as? Bool ?? true
        dictationEnabled = defaults.object(forKey: Keys.dictationEnabled) as? Bool ?? true
        screenshotsEnabled = defaults.object(forKey: Keys.screenshotsEnabled) as? Bool ?? true
        clipboardEnabled = defaults.object(forKey: Keys.clipboardEnabled) as? Bool ?? true
        if let raw = defaults.string(forKey: Keys.pushToTalkMode),
           let mode = PushToTalkMode(rawValue: raw) {
            pushToTalkMode = mode
        } else {
            pushToTalkMode = .hold
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
        apiKey = KeychainStore.get(Keys.apiKey) ?? ""
        if let data = defaults.data(forKey: Keys.hotkey),
           let decoded = try? JSONDecoder().decode(Hotkey.self, from: data) {
            hotkey = decoded
        } else {
            hotkey = .controlOption
        }
        if let data = defaults.data(forKey: Keys.screenshotHotkey),
           let decoded = try? JSONDecoder().decode(Hotkey.self, from: data) {
            screenshotHotkey = decoded.knownSystemShortcutName == nil ? decoded : .screenshotDefault
        } else {
            screenshotHotkey = .screenshotDefault
        }
        if hotkey.conflicts(with: screenshotHotkey) {
            hotkey = .controlOption
            screenshotHotkey = .screenshotDefault
        }
        saveHotkey()
        saveScreenshotHotkey()
    }

    private func saveHotkey() {
        if let data = try? JSONEncoder().encode(hotkey) {
            defaults.set(data, forKey: Keys.hotkey)
        }
    }

    private func saveScreenshotHotkey() {
        if let data = try? JSONEncoder().encode(screenshotHotkey) {
            defaults.set(data, forKey: Keys.screenshotHotkey)
        }
    }

    private func applyLaunchAtLogin() {
        do {
            if launchAtLogin {
                try SMAppService.mainApp.register()
            } else if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }

    private enum Keys {
        static let providerID = "providerID"
        static let hotkey = "hotkey"
        static let apiKey = "muse.apiKey"
        static let keywords = "keywords"
        static let languageBias = "languageBias"
        static let soundEnabled = "soundEnabled"
        static let dictationEnabled = "dictationEnabled"
        static let pushToTalkMode = "pushToTalkMode"
        static let screenshotsEnabled = "screenshots.enabled"
        static let screenshotHotkey = "screenshots.hotkey"
        static let clipboardEnabled = "clipboard.enabled"
    }
}

enum PushToTalkMode: String, Codable, CaseIterable, Identifiable {
    case hold
    case toggle

    var id: String { rawValue }

    var title: String {
        switch self {
        case .hold: "Hold"
        case .toggle: "Toggle"
        }
    }
}
