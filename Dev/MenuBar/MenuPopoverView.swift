import SwiftUI

struct MenuPopoverView: View {
  @Bindable var environment: AppEnvironment
  var onOpenSettings: () -> Void = {}
  var onInsertClip: (ClipboardItem) -> Void = { _ in }
  @State private var selectedTool: Tool = .dictation
  @Namespace private var tabSelection
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  private enum Tool: String, CaseIterable {
    case dictation = "Dictation"
    case screenshots = "Screenshots"
    case clipboard = "Clipboard"
    var symbol: String {
      switch self {
      case .dictation: "waveform"
      case .screenshots: "viewfinder"
      case .clipboard: "doc.on.clipboard"
      }
    }
    var key: KeyEquivalent {
      switch self {
      case .dictation: "1"
      case .screenshots: "2"
      case .clipboard: "3"
      }
    }
  }

  var body: some View {
    VStack(spacing: 0) {
      tabRail
      Group {
        switch selectedTool {
        case .dictation: dictationWorkspace
        case .screenshots: screenshotWorkspace
        case .clipboard:
          ClipboardShelfView(clipboard: environment.clipboard, onInsert: onInsertClip)
        }
      }
      .padding(.top, 14)
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
      footer
    }
    .padding(14)
    .frame(width: 340, height: 360, alignment: .top)
    .background {
      LinearGradient(
        colors: [.primary.opacity(0.035), .clear], startPoint: .topLeading,
        endPoint: .bottomTrailing)
    }
    .tint(.primary)
  }

  private func select(_ tool: Tool) {
    withAnimation(reduceMotion ? nil : .snappy(duration: 0.24)) { selectedTool = tool }
  }

  private var tabRail: some View {
    HStack(spacing: 3) {
      ForEach(Tool.allCases, id: \.self) { tool in
        Button {
          select(tool)
        } label: {
          HStack(spacing: 5) {
            Image(systemName: tool.symbol).font(.system(size: 12, weight: .medium))
              .overlay(alignment: .topTrailing) {
                if tool == .dictation, dictationActive {
                  Circle().fill(.primary).frame(width: 4, height: 4).offset(x: 3, y: -3)
                }
              }
            Text(tool.rawValue).font(.system(size: 10, weight: .semibold))
          }
          .foregroundStyle(selectedTool == tool ? .primary : .secondary)
          .frame(maxWidth: .infinity)
          .frame(height: 32)
          .background {
            if selectedTool == tool {
              RoundedRectangle(cornerRadius: 9)
                .fill(.regularMaterial)
                .overlay { RoundedRectangle(cornerRadius: 9).strokeBorder(.primary.opacity(0.08)) }
                .shadow(color: .black.opacity(0.08), radius: 3, y: 2)
                .matchedGeometryEffect(id: "tool", in: tabSelection)
            }
          }
          .contentShape(RoundedRectangle(cornerRadius: 9))
        }
        .buttonStyle(.plain)
        .keyboardShortcut(tool.key, modifiers: .command)
        .help(tool == .dictation && dictationActive ? statusTitle : tool.rawValue)
        .accessibilityAddTraits(selectedTool == tool ? .isSelected : [])
      }
    }
    .padding(3)
    .background(.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 12))
    .accessibilityElement(children: .contain)
    .accessibilityLabel("Tools")
  }

  private var dictationActive: Bool {
    environment.dictation.phase == .starting || environment.dictation.phase == .recording
      || environment.dictation.phase == .finishing
  }

  private var dictationWorkspace: some View {
    GeometryReader { geometry in
      ScrollView {
        VStack(spacing: 8) {
          ZStack {
            Capsule().strokeBorder(.primary.opacity(0.05)).frame(width: 164, height: 60)
            Capsule().fill(.primary.opacity(0.035)).frame(width: 144, height: 46)
            MenuWaveform(
              level: CGFloat(environment.dictation.level), phase: environment.dictation.phase
            )
            .scaleEffect(1.3)
            .frame(width: 100, height: 30)
          }
          .frame(height: 68)
          Text(statusTitle)
            .font(.system(size: 18, weight: .semibold, design: .rounded))
          if !statusDetail.isEmpty {
            Text(statusDetail)
              .font(.system(size: 11))
              .foregroundStyle(.secondary)
              .multilineTextAlignment(.center)
              .fixedSize(horizontal: false, vertical: true)
          }
          if readinessIssue != nil || !environment.settings.dictationEnabled {
            Button("Open Settings", action: onOpenSettings)
              .buttonStyle(.plain)
              .font(.system(size: 11, weight: .semibold))
          }
          VStack(spacing: 8) {
            dictationAction
            shortcutHint
          }
          .padding(.top, 12)
        }
        .frame(maxWidth: .infinity, minHeight: geometry.size.height)
      }
      .scrollIndicators(.hidden)
    }
    .padding(.bottom, 12)
  }

  private var screenshotWorkspace: some View {
    VStack(alignment: .leading, spacing: 12) {
      if !environment.settings.screenshotsEnabled {
        Text("Screenshots paused")
          .font(.system(size: 11)).foregroundStyle(.secondary)
      }
      screenshotAction
      ScreenshotShelfView(screenshots: environment.screenshots)
    }
    .padding(.bottom, 12)
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
      Text(shortcutLead)
        .font(.system(size: 11))
        .foregroundStyle(.secondary)

      Text(environment.settings.hotkey.display)
        .font(.system(size: 10, weight: .semibold, design: .monospaced))
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 6))

    }
    .frame(maxWidth: .infinity)
  }

  private var footer: some View {
    VStack(spacing: 8) {
      Rectangle().fill(.primary.opacity(0.08)).frame(height: 1)
      HStack {
        Button(action: onOpenSettings) {
          Image(systemName: "gearshape")
        }
        .keyboardShortcut(",", modifiers: .command)
        .help("Settings")
        .accessibilityLabel("Settings")
        Spacer()
        Button {
          NSApp.terminate(nil)
        } label: {
          Image(systemName: "power")
        }
        .help("Quit Dev")
        .accessibilityLabel("Quit Dev")
      }
      .font(.system(size: 11, weight: .medium))
      .foregroundStyle(.secondary)
      .buttonStyle(.plain)
    }
  }

  private var screenshotAction: some View {
    Button {
      environment.dictation.cancel()
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
    .buttonStyle(MonochromePrimaryButtonStyle())
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
    if !environment.settings.dictationEnabled { return "Paused" }
    return switch environment.dictation.phase {
    case .idle: readinessIssue == nil ? "Ready" : "Setup needed"
    case .starting: "Starting"
    case .recording: "Listening"
    case .finishing: "Transcribing"
    case .error: "Needs attention"
    }
  }

  private var statusDetail: String {
    if !environment.settings.dictationEnabled {
      return "Enable Dictation in Settings to start speaking."
    }
    if case .error(let message) = environment.dictation.phase { return message }
    if environment.dictation.phase == .idle, let readinessIssue { return readinessIssue }
    return switch environment.dictation.phase {
    case .idle, .error, .starting, .recording, .finishing: ""
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
