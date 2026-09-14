import XCTest
import Carbon.HIToolbox
@testable import Dev

final class MuseEventTests: XCTestCase {
    func testHandshakeHasNoType() throws {
        let frame = try XCTUnwrap(MuseServerFrame.parse(#"{"sessionId":"abc"}"#))
        XCTAssertTrue(frame.isHandshake)
        XCTAssertEqual(frame.sessionId, "abc")
        XCTAssertNil(frame.asTranscriptEvent())
    }

    func testPartialReplaces() throws {
        let frame = try XCTUnwrap(MuseServerFrame.parse(
            #"{"type":"transcript","transcript":"how is the weather","final":false}"#
        ))
        XCTAssertEqual(frame.asTranscriptEvent(), .partial("how is the weather"))
    }

    func testFinalTranscript() throws {
        let frame = try XCTUnwrap(MuseServerFrame.parse(
            #"{"type":"transcript","transcript":"How is the weather?","final":true}"#
        ))
        XCTAssertEqual(frame.asTranscriptEvent(), .final("How is the weather?"))
    }

    func testFinalAsNumberStillCounts() throws {
        let frame = try XCTUnwrap(MuseServerFrame.parse(
            #"{"type":"transcript","transcript":"Done","final":1}"#
        ))
        XCTAssertEqual(frame.asTranscriptEvent(), .final("Done"))
    }

    func testSpeechCompleteIsFinal() throws {
        let frame = try XCTUnwrap(MuseServerFrame.parse(
            #"{"type":"speechComplete","turnId":1,"transcript":"Done."}"#
        ))
        XCTAssertEqual(frame.asTranscriptEvent(), .final("Done."))
    }

    func testErrorEvent() throws {
        let frame = try XCTUnwrap(MuseServerFrame.parse(
            #"{"type":"error","message":"nope","sessionId":"x"}"#
        ))
        XCTAssertEqual(frame.asTranscriptEvent(), .failure("nope"))
    }

    func testHotkeyControlOption() {
        let hotkey = Hotkey.controlOption
        XCTAssertTrue(hotkey.isHeld(flags: [.maskControl, .maskAlternate]) { _ in false })
        XCTAssertFalse(hotkey.isHeld(flags: [.maskControl]) { _ in false })
        XCTAssertFalse(hotkey.isHeld(flags: [.maskControl, .maskAlternate, .maskShift]) { _ in false })
        XCTAssertEqual(hotkey.display, "⌃⌥")
    }

    func testHotkeyWithKeyRequiresKeyDown() {
        let hotkey = Hotkey(keyCode: 2, modifiers: CGEventFlags.maskCommand.rawValue, modifiersOnly: false)
        XCTAssertTrue(hotkey.isHeld(flags: .maskCommand) { $0 == 2 })
        XCTAssertFalse(hotkey.isHeld(flags: .maskCommand) { $0 == 0 })
        XCTAssertFalse(hotkey.isHeld(flags: []) { $0 == 2 })
    }

    func testScreenshotHotkeyDefaultsToShiftCommandTwo() {
        let hotkey = Hotkey.screenshotDefault
        XCTAssertEqual(hotkey.keyCode, 19)
        XCTAssertEqual(hotkey.display, "⇧⌘2")
        XCTAssertFalse(hotkey.modifiersOnly)
        XCTAssertTrue(hotkey.isActive(
            type: .keyDown,
            keyCode: 19,
            flags: [.maskShift, .maskCommand],
            wasDown: false
        ))
    }

    func testKeyedScreenshotChordCanReserveModifierOnlyDictationPrefix() {
        let dictation = Hotkey.controlOption
        let screenshot = Hotkey(
            keyCode: 1,
            modifiers: CGEventFlags.maskControl.rawValue | CGEventFlags.maskAlternate.rawValue,
            modifiersOnly: false
        )

        XCTAssertTrue(screenshot.isKeyedChord(using: dictation.flags))
        XCTAssertTrue(screenshot.matchesKeyDown(
            type: .keyDown,
            keyCode: 1,
            flags: [.maskControl, .maskAlternate]
        ))
        XCTAssertFalse(screenshot.matchesKeyDown(
            type: .keyUp,
            keyCode: 1,
            flags: [.maskControl, .maskAlternate]
        ))
    }

    func testShortcutConflictAndKnownMacOSShortcutDetection() {
        let controlSpace = Hotkey(
            keyCode: 49,
            modifiers: CGEventFlags.maskControl.rawValue,
            modifiersOnly: false
        )
        let controlOptionS = Hotkey(
            keyCode: 1,
            modifiers: CGEventFlags.maskControl.rawValue | CGEventFlags.maskAlternate.rawValue,
            modifiersOnly: false
        )

        XCTAssertEqual(controlSpace.knownSystemShortcutName, "macOS input-source switching")
        XCTAssertTrue(Hotkey.controlOption.conflicts(with: controlOptionS))
        XCTAssertFalse(Hotkey.controlOption.conflicts(with: Hotkey.screenshotDefault))
    }

    func testCarbonHotkeyHandlersOnlyOwnTheirEvents() {
        let dictation = EventHotKeyID(
            signature: HotkeyMonitor.carbonSignature,
            id: HotkeyMonitor.carbonID
        )
        let screenshot = EventHotKeyID(
            signature: ScreenshotHotkeyMonitor.carbonSignature,
            id: ScreenshotHotkeyMonitor.carbonID
        )

        XCTAssertTrue(HotkeyMonitor.owns(dictation))
        XCTAssertFalse(HotkeyMonitor.owns(screenshot))
        XCTAssertTrue(ScreenshotHotkeyMonitor.owns(screenshot))
        XCTAssertFalse(ScreenshotHotkeyMonitor.owns(dictation))
    }

    @MainActor
    func testScreenshotLibraryPersistsEditableAnnotations() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "DevTests-Screenshots-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }

        let library = ScreenshotLibrary(directory: directory)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = try XCTUnwrap(CGContext(
            data: nil,
            width: 120,
            height: 80,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 120, height: 40))
        context.setFillColor(CGColor(red: 0, green: 0, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 40, width: 120, height: 40))
        let image = try XCTUnwrap(context.makeImage())

        let item = try library.save(image)
        let before = try Data(contentsOf: item.url)
        let beforeRep = try XCTUnwrap(NSBitmapImageRep(data: before))
        let annotations = [
            ScreenshotAnnotation(
                kind: .rectangle,
                rect: CGRect(x: 0.1, y: 0.2, width: 0.5, height: 0.4)
            ),
            ScreenshotAnnotation(
                kind: .arrow,
                points: [CGPoint(x: 0.1, y: 0.1), CGPoint(x: 0.8, y: 0.7)],
                color: AnnotationColor(red: 0, green: 1, blue: 0, alpha: 1),
                lineWidth: 6
            ),
            ScreenshotAnnotation(
                kind: .text,
                points: [CGPoint(x: 0.2, y: 0.3)],
                text: "Review this"
            ),
            ScreenshotAnnotation(
                kind: .redact,
                rect: CGRect(x: 0.75, y: 0.75, width: 0.15, height: 0.1)
            )
        ]
        try library.saveAnnotations(annotations, for: item)

        XCTAssertEqual(library.annotations(for: item), annotations)
        let after = try Data(contentsOf: item.url)
        XCTAssertNotEqual(after, before)
        let afterRep = try XCTUnwrap(NSBitmapImageRep(data: after))
        let beforeBottomRed = try XCTUnwrap(
            beforeRep.colorAt(x: 10, y: 10)?.usingColorSpace(.sRGB)?.redComponent
        )
        let afterBottomRed = try XCTUnwrap(
            afterRep.colorAt(x: 10, y: 10)?.usingColorSpace(.sRGB)?.redComponent
        )
        let beforeTopBlue = try XCTUnwrap(
            beforeRep.colorAt(x: 10, y: 70)?.usingColorSpace(.sRGB)?.blueComponent
        )
        let afterTopBlue = try XCTUnwrap(
            afterRep.colorAt(x: 10, y: 70)?.usingColorSpace(.sRGB)?.blueComponent
        )
        XCTAssertEqual(beforeBottomRed, afterBottomRed, accuracy: 0.02)
        XCTAssertEqual(beforeTopBlue, afterTopBlue, accuracy: 0.02)
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: item.url.deletingPathExtension().appendingPathExtension("dev-original").path
        ))
    }

    func testControlSpaceActivatesOnKeyDownNotKeyState() {
        let hotkey = Hotkey(
            keyCode: 49,
            modifiers: CGEventFlags.maskControl.rawValue,
            modifiersOnly: false
        )
        XCTAssertTrue(hotkey.isActive(type: .keyDown, keyCode: 49, flags: .maskControl, wasDown: false))
        XCTAssertFalse(hotkey.isActive(type: .flagsChanged, keyCode: 59, flags: .maskControl, wasDown: false))
        XCTAssertFalse(hotkey.isActive(type: .keyUp, keyCode: 49, flags: .maskControl, wasDown: true))
        XCTAssertTrue(hotkey.isActive(type: .keyDown, keyCode: 0, flags: .maskControl, wasDown: true))
    }

    @MainActor
    func testUsageAggregatesAndPersistsWithoutTranscriptText() throws {
        let suiteName = "DevTests.Usage.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let date = Date(timeIntervalSince1970: 1_757_635_200)
        let store = UsageStore(defaults: defaults, calendar: calendar)

        store.record(
            providerID: "muse",
            audioSeconds: 12.5,
            outcome: .completed,
            transcript: "hello private world",
            at: date
        )
        store.record(providerID: "muse", audioSeconds: 7.5, outcome: .failed, at: date)

        let summary = store.currentMonthSummary(at: date)
        XCTAssertEqual(summary.audioSeconds, 20, accuracy: 0.001)
        XCTAssertEqual(summary.sessions, 2)
        XCTAssertEqual(summary.completed, 1)
        XCTAssertEqual(summary.failed, 1)
        XCTAssertEqual(summary.words, 3)
        XCTAssertEqual(summary.characters, 19)

        let persisted = UsageStore(defaults: defaults, calendar: calendar)
        XCTAssertEqual(persisted.currentMonthSummary(at: date), summary)

        let storedData = try XCTUnwrap(defaults.data(forKey: "usage.daily.v1"))
        let storedJSON = try XCTUnwrap(String(data: storedData, encoding: .utf8))
        XCTAssertFalse(storedJSON.contains("hello private world"))
    }

    func testUsageSessionMeterConvertsPCMBytesToDuration() {
        let meter = UsageSessionMeter(providerID: "muse", sampleRate: 24_000)
        meter.addAudioBytes(48_000)

        XCTAssertEqual(meter.audioSeconds, 1, accuracy: 0.001)
    }

    func testMuseCostUsesAudioDuration() {
        XCTAssertEqual(
            ProviderRegistry.estimatedCostUSD(providerID: "muse", audioSeconds: 3_600),
            0.18,
            accuracy: 0.000_001
        )
        XCTAssertEqual(
            ProviderRegistry.estimatedCostUSD(providerID: "muse", audioSeconds: 600),
            0.03,
            accuracy: 0.000_001
        )
    }

    func testSpeechLevelProcessorLeavesSilenceSilent() {
        let processor = SpeechLevelProcessor(sampleRate: 24_000)
        let output = processor.process([Int16](repeating: 0, count: 4_800))

        XCTAssertTrue(output.allSatisfy { $0 == 0 })
    }

    func testSpeechLevelProcessorRaisesSoftVoicedSpeech() {
        let processor = SpeechLevelProcessor(sampleRate: 24_000)
        let input = tone(amplitude: 180, frequency: 220, seconds: 1.5)
        let output = processor.process(input)

        XCTAssertGreaterThan(rms(output), rms(input) * 1.35)
        XCTAssertLessThanOrEqual(output.map { abs(Int($0)) }.max() ?? 0, 30_146)
    }

    func testSpeechLevelProcessorPreservesNormalSpeechLevel() {
        let processor = SpeechLevelProcessor(sampleRate: 24_000)
        let input = tone(amplitude: 8_000, frequency: 220, seconds: 1)
        let output = processor.process(input)
        let ratio = rms(output) / rms(input)

        XCTAssertGreaterThan(ratio, 0.9)
        XCTAssertLessThan(ratio, 1.1)
    }

    func testSpeechLevelProcessorProtectsPeaksAfterQuietSpeech() {
        let processor = SpeechLevelProcessor(sampleRate: 24_000)
        _ = processor.process(tone(amplitude: 180, frequency: 220, seconds: 2))
        let loud = tone(amplitude: 30_000, frequency: 220, seconds: 0.1)
        let output = processor.process(loud)

        XCTAssertLessThanOrEqual(output.map { abs(Int($0)) }.max() ?? 0, 30_146)
    }

    private func tone(amplitude: Int16, frequency: Double, seconds: Double) -> [Int16] {
        let count = Int(24_000 * seconds)
        return (0..<count).map { index in
            let phase = 2 * Double.pi * frequency * Double(index) / 24_000
            return Int16((Double(amplitude) * sin(phase)).rounded())
        }
    }

    private func rms(_ samples: [Int16]) -> Double {
        guard !samples.isEmpty else { return 0 }
        let sum = samples.reduce(0.0) { partial, sample in
            let normalized = Double(sample) / 32_768
            return partial + normalized * normalized
        }
        return sqrt(sum / Double(samples.count))
    }
}
