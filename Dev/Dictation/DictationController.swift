import AppKit
import Foundation
import Observation
import os

@MainActor
@Observable
final class DictationController {
    enum Phase: Equatable {
        case idle
        case starting
        case recording
        case finishing
        case error(String)
    }

    private(set) var phase: Phase = .idle
    private(set) var lastTranscript = ""
    private(set) var partial = ""
    private(set) var level: Float = 0

    private let settings: SettingsStore
    private let permissions: PermissionMonitor
    private let overlay: OverlayController
    private let usage: UsageStore
    private let log = Logger(subsystem: "com.goncalosoares.Dev", category: "dictation")
    private var capture: AudioCapture?
    private var stream: (any TranscriptionStream)?
    private var sessionTask: Task<Void, Never>?
    private var finishTimeoutTask: Task<Void, Never>?
    private var hideTask: Task<Void, Never>?
    private var targetApp: NSRunningApplication?
    private var usageMeter: UsageSessionMeter?

    init(
        settings: SettingsStore,
        permissions: PermissionMonitor,
        overlay: OverlayController,
        usage: UsageStore
    ) {
        self.settings = settings
        self.permissions = permissions
        self.overlay = overlay
        self.usage = usage
    }

    func begin() {
        guard settings.dictationEnabled else { return }
        guard phase == .idle || isError else { return }
        hideTask?.cancel()
        finishTimeoutTask?.cancel()
        sessionTask?.cancel()
        rememberTarget()
        phase = .starting
        partial = ""
        level = 0
        let provider = ProviderRegistry.provider(id: settings.providerID)
        usageMeter = UsageSessionMeter(providerID: provider.id, sampleRate: provider.sampleRate)
        overlay.show(status: "Starting", text: "", level: 0, kind: .busy)
        sessionTask = Task { await run() }
    }

    func end() {
        guard phase == .starting || phase == .recording else { return }
        phase = .finishing
        overlay.setStatus("Transcribing", text: partial, level: 0, kind: .busy)
        capture?.stop()
        stream?.finish()
        scheduleFinishTimeout()
    }

    func cancel() {
        guard phase == .starting || phase == .recording || phase == .finishing else { return }
        sessionTask?.cancel()
        tearDown()
        recordUsage(outcome: .cancelled)
        overlay.hide()
        phase = .idle
    }

    private var isError: Bool {
        if case .error = phase { return true }
        return false
    }

    private func rememberTarget() {
        if let app = NSWorkspace.shared.frontmostApplication,
           app.bundleIdentifier != Bundle.main.bundleIdentifier {
            targetApp = app
        }
    }

    private func run() async {
        do {
            let key = settings.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty else { throw TranscriptionError.missingAPIKey }

            permissions.refresh()
            if !permissions.microphoneGranted {
                let granted = await permissions.requestMicrophone()
                if !granted {
                    throw AudioCaptureError.engine("Microphone access is required.")
                }
            }

            let provider = ProviderRegistry.provider(id: settings.providerID)
            let options = TranscriptionOptions(
                languageBias: settings.languageBiasList,
                keywords: settings.keywordList
            )
            let capture = AudioCapture(sampleRate: provider.sampleRate)
            let bridge = AudioBridge()
            self.capture = capture

            if phase == .starting {
                phase = .recording
                overlay.setStatus("Listening", text: "", level: 0, kind: .live)
                playSound("Tink")
            }

            let meter = usageMeter
            capture.onFrame = { pcm in
                meter?.addAudioBytes(pcm.count)
                bridge.send(pcm)
            }
            capture.onLevel = { [weak self] value in
                DispatchQueue.main.async {
                    self?.level = value
                    if self?.phase == .recording {
                        self?.overlay.setLevel(value)
                    }
                }
            }
            if phase == .recording {
                try capture.start()
            }

            let stream = try await provider.connect(apiKey: key, options: options)
            if Task.isCancelled { throw CancellationError() }
            self.stream = stream
            bridge.attach(stream)

            if phase == .idle {
                stream.cancel()
                overlay.hide()
                tearDown()
                return
            }

            if phase == .finishing {
                capture.stop()
                stream.finish()
            }

            for await event in stream.events {
                if Task.isCancelled { break }
                switch event {
                case .partial(let text):
                    log.debug("partial: \(text, privacy: .public)")
                    partial = text
                    if phase == .recording {
                        overlay.setStatus("Listening", text: text, level: level, kind: .live)
                    } else {
                        overlay.setStatus("Transcribing", text: text, level: 0, kind: .busy)
                    }
                case .final(let text):
                    log.info("final: \(text, privacy: .public)")
                    await finish(with: text)
                    return
                case .failure(let message):
                    throw TranscriptionError.closed(message)
                }
            }

            if phase == .finishing || phase == .recording {
                await finish(with: partial)
            }
        } catch is CancellationError {
            tearDown()
            recordUsage(outcome: .cancelled)
            overlay.hide()
            phase = .idle
        } catch {
            log.error("session failed: \(error.localizedDescription, privacy: .public)")
            fail(error.localizedDescription)
        }
    }

    private func finish(with text: String) async {
        guard phase == .recording || phase == .finishing else { return }
        capture?.stop()
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.isEmpty {
            overlay.setStatus("Nothing to insert", text: "No speech detected", level: 0, kind: .mute)
            playSound("Pop")
            scheduleHide(after: 1.6)
            recordUsage(outcome: .empty)
            tearDown()
            phase = .idle
            return
        }

        lastTranscript = cleaned
        overlay.setStatus("Inserting", text: cleaned, level: 0, kind: .busy)
        let result = await TextInserter.insert(cleaned, into: targetApp)
        if result == .copied {
            overlay.setStatus("Copied — ⌘V to paste", text: cleaned, level: 0, kind: .done)
            scheduleHide(after: 1.8)
        } else {
            overlay.hide()
        }
        playSound("Pop")
        recordUsage(outcome: .completed, transcript: cleaned)
        tearDown()
        phase = .idle
    }

    private func fail(_ message: String) {
        tearDown()
        recordUsage(outcome: .failed)
        phase = .error(message)
        overlay.setStatus("Can't transcribe", text: message, level: 0, kind: .fault)
        scheduleHide(after: 2.8)
    }

    private func tearDown() {
        finishTimeoutTask?.cancel()
        finishTimeoutTask = nil
        capture?.stop()
        capture?.onFrame = nil
        capture?.onLevel = nil
        capture = nil
        stream?.cancel()
        stream = nil
        level = 0
    }

    private func recordUsage(outcome: UsageOutcome, transcript: String = "") {
        guard let meter = usageMeter else { return }
        usageMeter = nil
        usage.record(
            providerID: meter.providerID,
            audioSeconds: meter.audioSeconds,
            outcome: outcome,
            transcript: transcript
        )
    }

    private func scheduleFinishTimeout() {
        finishTimeoutTask?.cancel()
        finishTimeoutTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(8))
            guard !Task.isCancelled, phase == .finishing else { return }
            log.error("timed out waiting for Muse")
            await finish(with: partial)
        }
    }

    private func scheduleHide(after seconds: Double = 0.9) {
        hideTask?.cancel()
        hideTask = Task {
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            overlay.hide()
        }
    }

    private func playSound(_ name: String) {
        guard settings.soundEnabled else { return }
        NSSound(named: name)?.play()
    }
}
