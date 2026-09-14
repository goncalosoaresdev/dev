import SwiftUI

struct MenuPopoverView: View {
    @Bindable var environment: AppEnvironment
    var onOpenSettings: () -> Void = {}

    var body: some View {
        VStack(spacing: 16) {
            header
            dictationAction
            shortcutHint
            Divider()
            screenshotAction
            ScreenshotShelfView(screenshots: environment.screenshots)
            footer
        }
        .padding(16)
        .frame(width: 340, height: 405)
        .tint(.accentColor)
    }

    private var header: some View {
        HStack(spacing: 13) {
            MenuWaveform(
                level: CGFloat(environment.dictation.level),
                phase: environment.dictation.phase
            )
            .frame(width: 72, height: 28)
            .frame(width: 92, height: 48)
            .background(.primary.opacity(0.06), in: Capsule(style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(statusTitle)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                Text(statusDetail)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var dictationAction: some View {
        Button(action: toggleDictation) {
            HStack(spacing: 8) {
                Image(systemName: dictationButtonIcon)
                    .symbolRenderingMode(.monochrome)
                Text(dictationButtonTitle)
            }
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .frame(maxWidth: .infinity)
            .frame(height: 38)
        }
        .buttonStyle(MonochromePrimaryButtonStyle())
        .disabled(!environment.settings.dictationEnabled || environment.dictation.phase == .finishing)
    }

    private var shortcutHint: some View {
        HStack(spacing: 7) {
            Image(systemName: "keyboard")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)

            Text(shortcutLead)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            Text(environment.settings.hotkey.display)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 6))

            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var footer: some View {
        HStack(spacing: 8) {
            MenuFooterButton(title: "Settings", symbol: "gearshape") {
                onOpenSettings()
            }
            .keyboardShortcut(",", modifiers: .command)

            MenuFooterButton(title: "Quit", symbol: "power") {
                NSApp.terminate(nil)
            }
        }
    }

    private var screenshotAction: some View {
        Button {
            environment.screenshots.beginSelection()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "viewfinder")
                    .symbolRenderingMode(.monochrome)
                Text("Capture Selection")
                Spacer()
                Text(environment.settings.screenshotHotkey.display)
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 6))
            }
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity)
            .frame(height: 38)
        }
        .buttonStyle(.plain)
        .background(.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        .disabled(!environment.settings.screenshotsEnabled || screenshotBusy)
    }

    private var screenshotBusy: Bool {
        switch environment.screenshots.phase {
        case .idle, .failed: false
        case .requestingPermission, .selecting, .capturing, .saving: true
        }
    }

    private func toggleDictation() {
        switch environment.dictation.phase {
        case .idle, .error:
            environment.dictation.begin()
        case .starting, .recording:
            environment.dictation.end()
        case .finishing:
            break
        }
    }

    private var dictationButtonTitle: String {
        switch environment.dictation.phase {
        case .idle, .error: "Start Dictation"
        case .starting, .recording: "Stop & Insert"
        case .finishing: "Transcribing"
        }
    }

    private var dictationButtonIcon: String {
        switch environment.dictation.phase {
        case .idle, .error: "waveform"
        case .starting, .recording: "stop.fill"
        case .finishing: "ellipsis"
        }
    }

    private var statusTitle: String {
        switch environment.dictation.phase {
        case .idle: readinessIssue == nil ? "Ready" : "Setup needed"
        case .starting: "Starting"
        case .recording: "Listening"
        case .finishing: "Transcribing"
        case .error: "Needs attention"
        }
    }

    private var statusDetail: String {
        if let readinessIssue { return readinessIssue }
        if case .error(let message) = environment.dictation.phase { return message }
        return switch environment.dictation.phase {
        case .idle, .error: "Dictation is available in every app"
        case .starting: "Preparing the microphone"
        case .recording: "Release the shortcut to insert"
        case .finishing: "Preparing your text"
        }
    }

    private var readinessIssue: String? {
        if environment.settings.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Add your Muse API key in Settings"
        }
        if !environment.permissions.microphoneGranted {
            return "Enable Microphone access in Settings"
        }
        if !environment.permissions.inputMonitoringTrusted {
            return "Enable Input Monitoring in Settings"
        }
        if !environment.permissions.accessibilityTrusted {
            return "Enable Accessibility in Settings"
        }
        return nil
    }

    private var shortcutLead: String {
        environment.settings.pushToTalkMode == .hold ? "Hold to dictate" : "Press to dictate"
    }
}

private struct MenuWaveform: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let level: CGFloat
    let phase: DictationController.Phase

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 24, paused: reduceMotion || isIdle)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            HStack(spacing: 2.5) {
                ForEach(0..<13, id: \.self) { index in
                    Capsule(style: .continuous)
                        .fill(.primary.opacity(barOpacity(index)))
                        .frame(width: 2.3, height: barHeight(index, time: time))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .accessibilityHidden(true)
    }

    private var isIdle: Bool {
        if case .idle = phase { return true }
        if case .error = phase { return true }
        return false
    }

    private func barHeight(_ index: Int, time: TimeInterval) -> CGFloat {
        let position = CGFloat(index) / 12
        let envelope = 0.58 + 0.42 * sin(position * .pi)

        switch phase {
        case .recording:
            let energy = min(1, max(0.08, level))
            let movement = reduceMotion ? 0.7 : 0.55 + 0.45 * sin(time * 9 + Double(index) * 0.9)
            return 3 + 21 * energy * envelope * CGFloat(movement)
        case .starting, .finishing:
            let movement = reduceMotion ? 0.55 : 0.5 + 0.5 * sin(time * 5 - Double(index) * 0.7)
            return 3 + 13 * envelope * CGFloat(movement)
        case .idle, .error:
            return 4 + 10 * envelope * (0.55 + 0.25 * sin(Double(index) * 1.1))
        }
    }

    private func barOpacity(_ index: Int) -> Double {
        let distance = abs(Double(index) - 6) / 6
        return 0.5 + (1 - distance) * 0.45
    }
}

private struct MonochromePrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(Color(nsColor: .windowBackgroundColor))
            .background(
                Color.primary.opacity(isEnabled ? (configuration.isPressed ? 0.78 : 1) : 0.28),
                in: RoundedRectangle(cornerRadius: 11, style: .continuous)
            )
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

private struct MenuFooterButton: View {
    let title: String
    let symbol: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.system(size: 11, weight: .medium))
                .frame(maxWidth: .infinity)
                .frame(height: 30)
                .background(.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 9))
        }
        .buttonStyle(.plain)
    }
}
