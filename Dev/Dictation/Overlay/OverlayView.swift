import SwiftUI

struct OverlayView: View {
    @Bindable var model: OverlayModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        Group {
            if #available(macOS 26.0, *) {
                if reduceTransparency {
                    pillContent
                        .background(.black, in: Capsule(style: .continuous))
                } else {
                    pillContent
                        .glassEffect(
                            .regular.tint(.black.opacity(0.48)),
                            in: Capsule(style: .continuous)
                        )
                }
            } else if reduceTransparency {
                pillContent
                    .background(.black, in: Capsule(style: .continuous))
            } else {
                pillContent
                    .background(.regularMaterial, in: Capsule(style: .continuous))
                    .background(.black.opacity(0.74), in: Capsule(style: .continuous))
            }
        }
        .animation(reduceMotion ? nil : .snappy(duration: 0.28), value: model.kind)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.1), value: model.level)
    }

    @ViewBuilder
    private var pillContent: some View {
        switch model.kind {
        case .live:
            recordingContent
        case .busy:
            processingContent
        case .done, .mute, .fault:
            resultContent
        }
    }

    private var recordingContent: some View {
        Waveform(
            level: CGFloat(model.level),
            mode: .recording,
            reduceMotion: reduceMotion
        )
        .frame(width: 106, height: 28)
        .frame(width: 138, height: 44)
        .background(ambientWaveColor, in: Capsule(style: .continuous))
        .accessibilityLabel("Dictation recording")
    }

    private var processingContent: some View {
        Waveform(level: 0.36, mode: .processing, reduceMotion: reduceMotion)
            .frame(width: 106, height: 26)
            .frame(width: 138, height: 44)
        .background(.black.opacity(0.12), in: Capsule(style: .continuous))
        .accessibilityLabel(model.status)
    }

    private var resultContent: some View {
        HStack(spacing: 9) {
            resultSymbol

            Text(model.status)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .padding(.horizontal, 14)
        .frame(width: 218, height: 48)
        .background(.black.opacity(0.2), in: Capsule(style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private var ambientWaveColor: Color {
        let energy = min(1, max(0, Double(model.level)))
        return Color.white.opacity(0.025 + energy * 0.07)
    }

    @ViewBuilder
    private var resultSymbol: some View {
        switch model.kind {
        case .done:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.white)
        case .mute:
            Image(systemName: "waveform.slash")
                .foregroundStyle(.white.opacity(0.58))
        case .fault:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.white)
        case .live, .busy:
            EmptyView()
        }
    }
}

private struct Waveform: View {
    enum Mode {
        case recording
        case processing
    }

    var level: CGFloat
    var mode: Mode
    var reduceMotion: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            HStack(spacing: 2.4) {
                ForEach(0..<17, id: \.self) { index in
                    Capsule(style: .continuous)
                        .fill(barColor(index: index))
                        .frame(width: 2.4, height: barHeight(index: index, time: time))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .accessibilityHidden(true)
    }

    private func barHeight(index: Int, time: TimeInterval) -> CGFloat {
        let position = CGFloat(index) / 16
        let centerEnvelope = 0.62 + 0.38 * sin(position * .pi)
        let phase = Double(index) * 0.82

        switch mode {
        case .recording:
            let energy = min(1, max(0.08, level))
            let movement = reduceMotion ? 0.72 : 0.55 + 0.45 * sin(time * 10 + phase)
            return 3 + 22 * energy * centerEnvelope * CGFloat(movement)
        case .processing:
            let movement = reduceMotion ? 0.55 : 0.5 + 0.5 * sin(time * 5.5 - phase)
            return 3 + 13 * centerEnvelope * CGFloat(movement)
        }
    }

    private func barColor(index: Int) -> Color {
        let distanceFromCenter = abs(CGFloat(index) - 8) / 8
        let opacity = 0.58 + (1 - distanceFromCenter) * 0.42
        return Color.white.opacity(opacity)
    }
}
