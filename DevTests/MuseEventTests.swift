import XCTest
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
