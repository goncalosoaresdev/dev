import SwiftUI

struct SettingsView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var selection: SettingsPage = .dictation
    @State private var showingUsageReset = false

    var body: some View {
        @Bindable var settings = environment.settings
        @Bindable var permissions = environment.permissions

        NavigationSplitView {
            List {
                ForEach(SettingsPage.allCases) { page in
                    Button {
                        selection = page
                    } label: {
                        HStack(spacing: 9) {
                            Image(systemName: page.symbol)
                                .symbolRenderingMode(.monochrome)
                                .foregroundStyle(selection == page ? Color.black : Color.primary)
                                .frame(width: 17)

                            Text(page.title)
                                .foregroundStyle(selection == page ? Color.black : Color.primary)
                        }
                            .font(.system(size: 13, weight: selection == page ? .semibold : .regular))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(
                                selection == page ? Color.white : Color.clear,
                                in: RoundedRectangle(cornerRadius: 9, style: .continuous)
                            )
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .listRowInsets(EdgeInsets(top: 2, leading: 8, bottom: 2, trailing: 8))
                    .listRowBackground(Color.clear)
                }
            }
            .navigationTitle("Dev")
            .navigationSplitViewColumnWidth(min: 170, ideal: 184, max: 210)
        } detail: {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    PageHeading(page: selection)

                    switch selection {
                    case .dictation:
                        dictationPage(settings: settings)
                    case .screenshots:
                        screenshotsPage(settings: settings)
                    case .clipboard:
                        clipboardPage(settings: settings)
                    case .permissions:
                        permissionsPage(permissions: permissions)
                    case .usage:
                        usagePage(usage: environment.usage)
                    case .general:
                        generalPage(settings: settings)
                    }
                }
                .padding(.horizontal, 28)
                .padding(.top, 24)
                .padding(.bottom, 32)
                .frame(maxWidth: 620, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .top)
            }
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 700, minHeight: 560)
        .tint(.accentColor)
        .alert("Reset usage data?", isPresented: $showingUsageReset) {
            Button("Cancel", role: .cancel) {}
            Button("Reset", role: .destructive) {
                environment.usage.reset()
            }
        } message: {
            Text("This permanently removes the local usage totals from this Mac.")
        }
        .onAppear { permissions.refresh() }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1.5))
                permissions.refresh()
            }
        }
    }

    private func dictationPage(settings: SettingsStore) -> some View {
        @Bindable var settings = settings

        return VStack(spacing: 16) {
            DictationHero(isEnabled: $settings.dictationEnabled)

            SettingsCard(title: "Activation", symbol: "keyboard") {
                SettingsControlRow(title: "Behavior", detail: "Choose how the shortcut starts and stops dictation.") {
                    Picker("Behavior", selection: $settings.pushToTalkMode) {
                        ForEach(PushToTalkMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 150)
                }

                SettingsDivider()

                SettingsControlRow(title: "Shortcut", detail: shortcutHelp(settings: settings)) {
                    HotkeyRecorder(
                        hotkey: $settings.hotkey,
                        conflictingHotkey: settings.screenshotHotkey,
                        conflictName: "Screenshot",
                        allowsSystemShortcuts: true
                    ) { paused in
                        environment.hotkey.paused = paused
                        environment.screenshotHotkey.paused = paused
                    }
                }
            }
            .disabled(!settings.dictationEnabled)
            .opacity(settings.dictationEnabled ? 1 : 0.48)

            SettingsCard(title: "Transcription", symbol: "waveform") {
                SettingsControlRow(title: "Provider", detail: "Speech recognition service") {
                    Picker("Provider", selection: $settings.providerID) {
                        ForEach(ProviderRegistry.all, id: \.id) { provider in
                            Text(provider.displayName).tag(provider.id)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 170)
                }

                SettingsDivider()

                VStack(alignment: .leading, spacing: 7) {
                    Text("API key")
                        .font(.system(size: 13, weight: .medium))
                    SecureField("Meta Model API key", text: $settings.apiKey)
                        .textFieldStyle(.roundedBorder)
                    Text("Stored securely in your login Keychain.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                SettingsDivider()

                SettingsControlRow(title: "Language", detail: "Optional recognition hint") {
                    Picker("Language", selection: $settings.languageBias) {
                        Text("Automatic").tag("")
                        ForEach(Self.languages, id: \.self) { language in
                            Text(language).tag(language)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 170)
                }

                SettingsDivider()

                VStack(alignment: .leading, spacing: 7) {
                    Text("Vocabulary")
                        .font(.system(size: 13, weight: .medium))
                    TextField("Swift, Xcode, project names", text: $settings.keywords)
                        .textFieldStyle(.roundedBorder)
                    Text("Comma-separated words that the transcription service should prefer.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func screenshotsPage(settings: SettingsStore) -> some View {
        @Bindable var settings = settings

        return VStack(spacing: 16) {
            ScreenshotHero(isEnabled: $settings.screenshotsEnabled)

            SettingsCard(title: "Capture", symbol: "viewfinder") {
                SettingsControlRow(
                    title: "Shortcut",
                    detail: environment.screenshotHotkey.registrationError
                        ?? "Press once, then drag to choose exactly what to capture."
                ) {
                    HotkeyRecorder(
                        hotkey: $settings.screenshotHotkey,
                        conflictingHotkey: settings.hotkey,
                        conflictName: "Dictation"
                    ) { paused in
                        environment.screenshotHotkey.paused = paused
                        environment.hotkey.paused = paused
                    }
                }

                SettingsDivider()

                SettingsControlRow(
                    title: "Recent screenshots",
                    detail: "Dev keeps the latest 20 captures locally on this Mac."
                ) {
                    Button("Show in Finder") {
                        if let item = environment.screenshots.library.items.first {
                            environment.screenshots.library.reveal(item)
                        }
                    }
                    .disabled(environment.screenshots.library.items.isEmpty)
                }
            }
            .disabled(!settings.screenshotsEnabled)
            .opacity(settings.screenshotsEnabled ? 1 : 0.48)
        }
    }

    private func clipboardPage(settings: SettingsStore) -> some View {
        @Bindable var settings = settings

        return VStack(spacing: 16) {
            ClipboardHero(isEnabled: $settings.clipboardEnabled)

            SettingsCard(title: "History", symbol: "clock") {
                SettingsControlRow(
                    title: "Recent copies",
                    detail: "Dev keeps the last 5 copied texts locally on this Mac. Password-manager copies are ignored."
                ) {
                    Button("Clear History") {
                        environment.clipboard.store.clear()
                    }
                    .disabled(environment.clipboard.store.items.isEmpty)
                }
            }
            .opacity(settings.clipboardEnabled ? 1 : 0.48)
        }
    }

    private func permissionsPage(permissions: PermissionMonitor) -> some View {
        let grantedCount = [
            permissions.microphoneGranted,
            permissions.inputMonitoringTrusted,
            permissions.accessibilityTrusted,
            permissions.screenRecordingGranted,
        ].filter { $0 }.count

        return VStack(spacing: 16) {
            ReadinessHero(granted: grantedCount, total: 4)

            SettingsCard(title: "System access", symbol: "checkmark.shield") {
                PermissionRow(
                    title: "Microphone",
                    detail: "Captures your voice while the shortcut is held.",
                    symbol: "mic",
                    granted: permissions.microphoneGranted,
                    actionTitle: permissions.microphoneGranted ? "Ready" : "Enable"
                ) {
                    if permissions.microphoneGranted { return }
                    Task {
                        let granted = await permissions.requestMicrophone()
                        if !granted { permissions.openMicrophoneSettings() }
                    }
                }

                SettingsDivider()

                PermissionRow(
                    title: "Input Monitoring",
                    detail: "Recognizes your shortcut in every app.",
                    symbol: "keyboard",
                    granted: permissions.inputMonitoringTrusted,
                    actionTitle: permissions.inputMonitoringTrusted ? "Ready" : "Open Settings"
                ) {
                    permissions.requestInputMonitoring()
                    permissions.openInputMonitoringSettings()
                }

                SettingsDivider()

                PermissionRow(
                    title: "Accessibility",
                    detail: "Inserts the finished text at the cursor.",
                    symbol: "cursorarrow.and.square.on.square.dashed",
                    granted: permissions.accessibilityTrusted,
                    actionTitle: permissions.accessibilityTrusted ? "Ready" : "Open Settings"
                ) {
                    permissions.openAccessibilitySettings()
                }

                SettingsDivider()

                PermissionRow(
                    title: "Screen Recording",
                    detail: "Captures only the screen region you select.",
                    symbol: "rectangle.dashed",
                    granted: permissions.screenRecordingGranted,
                    actionTitle: permissions.screenRecordingGranted ? "Ready" : "Enable"
                ) {
                    if !permissions.requestScreenRecording() {
                        permissions.openScreenRecordingSettings()
                    }
                }
            }

            SettingsCard(title: "Troubleshooting", symbol: "wrench.and.screwdriver") {
                DisclosureGroup("Permission remains unavailable") {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("In System Settings, remove Dev from the permission list, add /Applications/Dev.app again, then quit and reopen Dev.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        Button("Reveal Dev.app in Finder") {
                            permissions.revealAppInFinder()
                        }
                    }
                    .padding(.top, 10)
                }
            }
        }
    }

    private func generalPage(settings: SettingsStore) -> some View {
        @Bindable var settings = settings

        return VStack(spacing: 16) {
            SettingsCard(title: "Experience", symbol: "slider.horizontal.3") {
                SettingsToggleRow(
                    title: "Sound feedback",
                    detail: "Play a subtle sound when dictation starts and finishes.",
                    symbol: "speaker.wave.2",
                    isOn: $settings.soundEnabled
                )

                SettingsDivider()

                SettingsToggleRow(
                    title: "Launch at login",
                    detail: "Keep push to talk available after signing in.",
                    symbol: "power",
                    isOn: $settings.launchAtLogin
                )
            }

            VStack(spacing: 7) {
                Image(systemName: "waveform")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(.secondary)
                Text("Dev stays in the menu bar and appears only when you need it.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 16)
        }
    }

    private func usagePage(usage: UsageStore) -> some View {
        let summary = usage.currentMonthSummary()
        let monthStart = Calendar.current.dateInterval(of: .month, for: .now)?.start ?? .now
        let providers = usage.providerSummaries(since: monthStart)
        let estimatedCost = providers.reduce(0) { total, provider in
            total + ProviderRegistry.estimatedCostUSD(
                providerID: provider.providerID,
                audioSeconds: provider.summary.audioSeconds
            )
        }

        return VStack(spacing: 16) {
            UsageHero(summary: summary, days: usage.lastSevenDays())

            SettingsCard(title: "This month", symbol: "calendar") {
                HStack(spacing: 0) {
                    UsageMetric(value: "\(summary.sessions)", label: "Sessions")
                    UsageMetric(value: "\(summary.completed)", label: "Inserted")
                    UsageMetric(value: compactNumber(summary.words), label: "Words")
                    UsageMetric(value: formatCost(estimatedCost), label: "Est. cost")
                }
            }

            if !providers.isEmpty {
                SettingsCard(title: "Providers", symbol: "point.3.connected.trianglepath.dotted") {
                    ForEach(providers.indices, id: \.self) { index in
                        let provider = providers[index]
                        if index > 0 { SettingsDivider() }
                        ProviderUsageRow(
                            name: providerName(provider.providerID),
                            duration: formatDuration(provider.summary.audioSeconds),
                            sessions: provider.summary.sessions,
                            estimatedCost: formatCost(
                                ProviderRegistry.estimatedCostUSD(
                                    providerID: provider.providerID,
                                    audioSeconds: provider.summary.audioSeconds
                                )
                            )
                        )
                    }
                }
            }

            HStack {
                Text("Estimated at Muse's $0.18/audio hour rate. Audio and transcripts are never saved.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                Spacer()
                Button("Reset Usage…") {
                    showingUsageReset = true
                }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(.secondary)
                .disabled(summary.sessions == 0)
            }
            .padding(.horizontal, 4)
        }
    }

    private func providerName(_ id: String) -> String {
        ProviderRegistry.all.first(where: { $0.id == id })?.displayName ?? id.capitalized
    }

    private func formatDuration(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        if total < 60 { return "\(total)s" }
        let minutes = total / 60
        if minutes < 60 { return "\(minutes)m \(total % 60)s" }
        return "\(minutes / 60)h \(minutes % 60)m"
    }

    private func compactNumber(_ value: Int) -> String {
        if value < 1_000 { return "\(value)" }
        return String(format: "%.1fK", Double(value) / 1_000)
    }

    private func formatCost(_ cost: Double) -> String {
        if cost > 0, cost < 0.01 {
            return String(format: "$%.4f", cost)
        }
        return String(format: "$%.2f", cost)
    }

    private func shortcutHelp(settings: SettingsStore) -> String {
        let key = settings.hotkey.display
        switch settings.pushToTalkMode {
        case .hold:
            return "Hold \(key), then release to insert"
        case .toggle:
            return "Press \(key) to start and press again to insert"
        }
    }

    private static let languages = [
        "English", "French", "German", "Spanish", "Portuguese", "Italian",
        "Dutch", "Polish", "Turkish", "Arabic", "Hebrew", "Hindi", "Bengali",
        "Tamil", "Telugu", "Kannada", "Marathi", "Indonesian", "Malay",
        "Japanese", "Korean", "Mandarin Chinese", "Thai", "Vietnamese", "Tagalog"
    ]
}

private enum SettingsPage: String, CaseIterable, Identifiable {
    case dictation
    case screenshots
    case clipboard
    case permissions
    case usage
    case general

    var id: Self { self }

    var title: String {
        switch self {
        case .dictation: "Dictation"
        case .screenshots: "Screenshots"
        case .clipboard: "Clipboard"
        case .permissions: "Permissions"
        case .usage: "Usage"
        case .general: "General"
        }
    }

    var subtitle: String {
        switch self {
        case .dictation: "Shape how push to talk listens and transcribes."
        case .screenshots: "Capture exactly what you choose and keep it close."
        case .clipboard: "Keep the last five texts you copy, then insert one back."
        case .permissions: "Manage the system access Dev needs to work."
        case .usage: "See how much dictation you use without storing what you say."
        case .general: "Choose how Dev behaves on your Mac."
        }
    }

    var symbol: String {
        switch self {
        case .dictation: "waveform"
        case .screenshots: "viewfinder"
        case .clipboard: "doc.on.clipboard"
        case .permissions: "hand.raised"
        case .usage: "chart.bar.xaxis"
        case .general: "gearshape"
        }
    }
}

private struct ClipboardHero: View {
    @Binding var isEnabled: Bool

    var body: some View {
        HStack(spacing: 18) {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(.primary.opacity(0.72), lineWidth: 1.5)
                Image(systemName: "doc.on.clipboard")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .frame(width: 52, height: 34)

            VStack(alignment: .leading, spacing: 3) {
                Text(isEnabled ? "Ready to remember copies" : "Clipboard paused")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                Text("Last five texts")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Toggle("Clipboard", isOn: $isEnabled)
                .labelsHidden()
                .toggleStyle(.switch)
        }
        .padding(.horizontal, 20)
        .frame(height: 84)
        .settingsGlassSurface()
    }
}

private struct ScreenshotHero: View {
    @Binding var isEnabled: Bool

    var body: some View {
        HStack(spacing: 18) {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(.primary.opacity(0.72), lineWidth: 1.5)
                Image(systemName: "plus")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .frame(width: 52, height: 34)

            VStack(alignment: .leading, spacing: 3) {
                Text(isEnabled ? "Ready to capture" : "Screenshots paused")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                Text("Select only what you need")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Toggle("Screenshots", isOn: $isEnabled)
                .labelsHidden()
                .toggleStyle(.switch)
        }
        .padding(.horizontal, 20)
        .frame(height: 84)
        .settingsGlassSurface()
    }
}

private struct PageHeading: View {
    let page: SettingsPage

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(page.title)
                .font(.system(size: 26, weight: .bold, design: .rounded))
            Text(page.subtitle)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
    }
}

private struct DictationHero: View {
    @Binding var isEnabled: Bool

    var body: some View {
        HStack(spacing: 18) {
            SettingsWaveform()
                .frame(width: 112, height: 34)

            VStack(alignment: .leading, spacing: 3) {
                Text(isEnabled ? "Ready to listen" : "Dictation paused")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                Text("Push to talk")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Toggle("Dictation", isOn: $isEnabled)
                .labelsHidden()
                .toggleStyle(.switch)
        }
        .padding(.horizontal, 20)
        .frame(height: 84)
        .settingsGlassSurface()
    }
}

private struct ReadinessHero: View {
    let granted: Int
    let total: Int

    var body: some View {
        HStack(spacing: 15) {
            ZStack {
                Circle()
                    .fill(.primary.opacity(0.08))
                Image(systemName: granted == total ? "checkmark" : "ellipsis")
                    .font(.system(size: 16, weight: .bold))
            }
            .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: 3) {
                Text(granted == total ? "Dev is ready" : "Setup needs attention")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                Text("\(granted) of \(total) permissions available")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 20)
        .frame(height: 84)
        .settingsGlassSurface()
    }
}

private struct UsageHero: View {
    let summary: UsageSummary
    let days: [UsageDayBucket]

    var body: some View {
        HStack(spacing: 20) {
            VStack(alignment: .leading, spacing: 3) {
                Text(duration)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .contentTransition(.numericText())
                Text("dictated this month")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            UsageActivityStrip(days: days)
                .frame(width: 150, height: 42)
        }
        .padding(.horizontal, 20)
        .frame(height: 84)
        .settingsGlassSurface()
    }

    private var duration: String {
        let total = Int(summary.audioSeconds.rounded())
        if total < 60 { return "\(total)s" }
        let minutes = total / 60
        if minutes < 60 { return "\(minutes)m \(total % 60)s" }
        return "\(minutes / 60)h \(minutes % 60)m"
    }
}

private struct UsageActivityStrip: View {
    let days: [UsageDayBucket]

    var body: some View {
        let maximum = max(days.map(\.audioSeconds).max() ?? 0, 1)

        HStack(alignment: .bottom, spacing: 7) {
            ForEach(days) { day in
                VStack(spacing: 5) {
                    Capsule(style: .continuous)
                        .fill(.primary.opacity(day.audioSeconds > 0 ? 0.78 : 0.1))
                        .frame(
                            width: 9,
                            height: day.audioSeconds > 0
                                ? 7 + 23 * day.audioSeconds / maximum
                                : 4
                        )
                    Text(day.day, format: .dateTime.weekday(.narrow))
                        .font(.system(size: 8, weight: .medium))
                        .foregroundStyle(.tertiary)
                }
                .frame(maxHeight: .infinity, alignment: .bottom)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Seven day dictation activity")
    }
}

private struct UsageMetric: View {
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .contentTransition(.numericText())
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct ProviderUsageRow: View {
    let name: String
    let duration: String
    let sessions: Int
    let estimatedCost: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "waveform")
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(.secondary)
                .frame(width: 24)
            Text(name)
                .font(.system(size: 13, weight: .medium))
            Spacer()
            Text("\(sessions) sessions")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("\(estimatedCost) · \(duration)")
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .frame(minWidth: 112, alignment: .trailing)
        }
    }
}

private struct SettingsCard<Content: View>: View {
    let title: String
    let symbol: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(title, systemImage: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)

            content
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private struct SettingsControlRow<Control: View>: View {
    let title: String
    let detail: String
    @ViewBuilder let control: Control

    var body: some View {
        HStack(spacing: 20) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            control
        }
    }
}

private struct SettingsToggleRow: View {
    let title: String
    let detail: String
    let symbol: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 13) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Toggle(title, isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
        }
    }
}

private struct SettingsDivider: View {
    var body: some View {
        Rectangle()
            .fill(.primary.opacity(0.08))
            .frame(height: 1)
    }
}

private struct PermissionRow: View {
    let title: String
    let detail: String
    let symbol: String
    let granted: Bool
    let actionTitle: String
    let action: () -> Void

    var body: some View {
        HStack(spacing: 13) {
            ZStack {
                Circle()
                    .fill(granted ? Color.primary : Color.primary.opacity(0.08))
                Image(systemName: granted ? "checkmark" : symbol)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(
                        granted
                            ? Color(nsColor: .windowBackgroundColor)
                            : Color.primary.opacity(0.58)
                    )
            }
            .frame(width: 26, height: 26)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button(actionTitle, action: action)
                .disabled(granted)
        }
    }
}

private struct SettingsWaveform: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 24, paused: reduceMotion)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            HStack(spacing: 3) {
                ForEach(0..<15, id: \.self) { index in
                    let position = Double(index) / 14
                    let envelope = 0.55 + 0.45 * sin(position * .pi)
                    let motion = reduceMotion ? 0.6 : 0.5 + 0.5 * sin(time * 3.2 + Double(index) * 0.72)
                    Capsule(style: .continuous)
                        .fill(.primary.opacity(0.48 + envelope * 0.42))
                        .frame(width: 2.5, height: 4 + 20 * envelope * motion)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .accessibilityHidden(true)
    }
}

private extension View {
    @ViewBuilder
    func settingsGlassSurface() -> some View {
        if #available(macOS 26.0, *) {
            glassEffect(.regular.tint(.black.opacity(0.08)), in: .rect(cornerRadius: 20))
        } else {
            background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
    }
}

private struct HotkeyRecorder: View {
    @Binding var hotkey: Hotkey
    let conflictingHotkey: Hotkey
    let conflictName: String
    var allowsSystemShortcuts = false
    var setPaused: (Bool) -> Void
    @State private var recording = false
    @State private var validationMessage: String?

    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            HStack(spacing: 8) {
                Text(recording ? "Press shortcut…" : hotkey.display)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 7))
                    .onTapGesture { beginRecording() }
                Button(recording ? "Cancel" : "Change") {
                    if recording {
                        recording = false
                        setPaused(false)
                    } else {
                        beginRecording()
                    }
                }
            }
            if let validationMessage {
                Text(validationMessage)
                    .font(.caption2)
                    .foregroundStyle(validationMessage.contains("override") ? .orange : .red)
            }
        }
        .background(
            HotkeyCatcher(
                isRecording: $recording,
                onHotkey: accept,
                onStop: { setPaused(false) }
            )
        )
    }

    private func beginRecording() {
        validationMessage = nil
        recording = true
        setPaused(true)
    }

    private func accept(_ candidate: Hotkey) {
        if candidate.conflicts(with: conflictingHotkey) {
            validationMessage = "Overlaps the \(conflictName) shortcut."
        } else if let systemName = candidate.knownSystemShortcutName {
            if allowsSystemShortcuts {
                validationMessage = "Dev will override \(systemName) while running."
                hotkey = candidate
            } else {
                validationMessage = "Used by \(systemName). Choose another shortcut."
            }
        } else {
            validationMessage = nil
            hotkey = candidate
        }
    }
}

private struct HotkeyCatcher: NSViewRepresentable {
    @Binding var isRecording: Bool
    var onHotkey: (Hotkey) -> Void
    var onStop: () -> Void

    func makeNSView(context: Context) -> CatcherView {
        let view = CatcherView()
        view.onHotkey = { value in
            onHotkey(value)
            isRecording = false
            onStop()
        }
        view.onCancel = {
            isRecording = false
            onStop()
        }
        return view
    }

    func updateNSView(_ nsView: CatcherView, context: Context) {
        nsView.onHotkey = { value in
            onHotkey(value)
            isRecording = false
            onStop()
        }
        nsView.onCancel = {
            isRecording = false
            onStop()
        }
        nsView.recording = isRecording
    }

    final class CatcherView: NSView {
        var recording = false {
            didSet { if recording { window?.makeFirstResponder(self) } }
        }
        var onHotkey: ((Hotkey) -> Void)?
        var onCancel: (() -> Void)?
        private var monitor: Any?

        override var acceptsFirstResponder: Bool { true }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if window != nil, monitor == nil {
                monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
                    guard let self, self.recording else { return event }
                    self.handle(event)
                    return nil
                }
            }
        }

        override func viewWillMove(toWindow newWindow: NSWindow?) {
            super.viewWillMove(toWindow: newWindow)
            if newWindow == nil, let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
        }

        private func handle(_ event: NSEvent) {
            guard recording else { return }
            if event.type == .keyDown, event.keyCode == 53 {
                onCancel?()
                return
            }
            if event.type == .keyDown, let hotkey = Hotkey.from(event: event) {
                onHotkey?(hotkey)
                return
            }
            if event.type == .flagsChanged,
               let hotkey = Hotkey.from(flagsChanged: event),
               event.modifierFlags.cgEventFlags.hotkeyRelevant.rawValue != 0 {
                if hotkey.flags.hotkeyRelevant.contains(.maskControl) && hotkey.flags.contains(.maskAlternate)
                    || hotkey.flags.contains(.maskSecondaryFn) && hotkey.flags.subtracting(.maskSecondaryFn).isEmpty {
                    onHotkey?(hotkey)
                }
            }
        }
    }
}
