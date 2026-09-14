import AppKit
import CoreGraphics
import Observation

@MainActor
@Observable
final class ScreenshotController {
    private(set) var phase: ScreenshotPhase = .idle
    private(set) var failureNeedsScreenRecordingSettings = false
    let library = ScreenshotLibrary()

    private let settings: SettingsStore
    private let permissions: PermissionMonitor
    private let selection = RegionSelectionController()
    private let captureService = ScreenshotCaptureService()
    private let editor = ScreenshotEditorController()
    private let captureResult = CaptureResultController()
    private var captureTask: Task<Void, Never>?
    private var captureGeneration = 0

    init(settings: SettingsStore, permissions: PermissionMonitor) {
        self.settings = settings
        self.permissions = permissions
    }

    func beginSelection() {
        guard settings.screenshotsEnabled else { return }
        guard phase == .idle || isFailure else { return }

        failureNeedsScreenRecordingSettings = false
        permissions.refreshScreenRecording()
        guard permissions.screenRecordingGranted else {
            phase = .requestingPermission
            let granted = permissions.requestScreenRecording()
            guard granted else {
                fail("Enable Screen Recording in System Settings", opensScreenRecordingSettings: true)
                return
            }
            permissions.refreshScreenRecording()
            guard permissions.screenRecordingGranted else {
                fail("Quit and reopen Dev to finish enabling capture", opensScreenRecordingSettings: true)
                return
            }
            startSelection()
            return
        }
        startSelection()
    }

    func cancel() {
        captureGeneration &+= 1
        captureTask?.cancel()
        captureTask = nil
        selection.cancel()
        captureResult.dismiss()
        phase = .idle
    }

    func openScreenRecordingSettings() {
        permissions.openScreenRecordingSettings()
    }

    func dismissFailure() {
        guard isFailure else { return }
        failureNeedsScreenRecordingSettings = false
        phase = .idle
    }

    func edit(_ item: ScreenshotItem) {
        editor.open(item: item, library: library)
    }

    private var isFailure: Bool {
        if case .failed = phase { return true }
        return false
    }

    private func startSelection() {
        phase = .selecting
        selection.begin { [weak self] result in
            guard let self else { return }
            guard let result else {
                self.phase = .idle
                return
            }
            self.capture(result)
        }
    }

    private func capture(_ selection: RegionSelectionController.Selection) {
        phase = .capturing
        captureTask?.cancel()
        captureGeneration &+= 1
        let generation = captureGeneration
        captureTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                if self.captureGeneration == generation {
                    self.captureTask = nil
                }
            }
            do {
                try await Task.sleep(for: .milliseconds(60))
                let image = try await captureService.capture(
                    screen: selection.screen,
                    rect: selection.rect
                )
                try Task.checkCancellation()
                guard captureGeneration == generation else { return }
                phase = .saving
                let item = try library.save(image)
                try Task.checkCancellation()
                guard captureGeneration == generation else { return }
                library.copy(item)
                phase = .idle
                captureResult.show(item: item, on: selection.screen) { [weak self] in
                    self?.edit(item)
                }
            } catch is CancellationError {
                if captureGeneration == generation { phase = .idle }
            } catch {
                if captureGeneration == generation { fail(error.localizedDescription) }
            }
        }
    }

    private func fail(_ message: String, opensScreenRecordingSettings: Bool = false) {
        failureNeedsScreenRecordingSettings = opensScreenRecordingSettings
        phase = .failed(message)
    }
}
