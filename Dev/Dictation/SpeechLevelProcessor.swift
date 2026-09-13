import Foundation

/// Conservative, capture-independent speech leveling for transcription input.
/// It never touches Core Audio devices and intentionally performs no denoising.
final class SpeechLevelProcessor: @unchecked Sendable {
    private let sampleRate: Float
    private let samplesPerAnalysisFrame: Int
    private let highPassCoefficient: Float
    private let lock = NSLock()

    private var previousInput: Float = 0
    private var previousHighPassed: Float = 0
    private var noiseRMS: Float = 0.0005
    private var gainDB: Float = 0
    private var adjacentSpeechFrames = 0
    private var speechHangoverFrames = 0

    private let targetSpeechRMS: Float = 0.05       // Approximately -26 dBFS.
    private let minimumSpeechRMS: Float = 0.0015   // Approximately -56.5 dBFS.
    private let maximumGainDB: Float = 12
    private let maximumOutputNoiseRMS: Float = 0.00316 // -50 dBFS.
    private let peakCeiling: Float = 0.92

    init(sampleRate: Int) {
        self.sampleRate = Float(sampleRate)
        samplesPerAnalysisFrame = max(1, sampleRate / 100)
        highPassCoefficient = exp(-2 * .pi * 70 / Float(sampleRate))
    }

    func process(_ data: Data) -> Data {
        guard data.count >= MemoryLayout<Int16>.size else { return data }
        var input = [Int16](repeating: 0, count: data.count / MemoryLayout<Int16>.size)
        input.withUnsafeMutableBytes { destination in
            data.copyBytes(to: destination)
        }
        let output = process(input)
        return output.withUnsafeBytes { Data($0) }
    }

    func process(_ input: [Int16]) -> [Int16] {
        lock.withLock {
            processLocked(input)
        }
    }

    func reset() {
        lock.withLock {
            previousInput = 0
            previousHighPassed = 0
            noiseRMS = 0.0005
            gainDB = 0
            adjacentSpeechFrames = 0
            speechHangoverFrames = 0
        }
    }

    private func processLocked(_ input: [Int16]) -> [Int16] {
        guard !input.isEmpty else { return [] }
        var output = [Int16]()
        output.reserveCapacity(input.count)

        var offset = 0
        while offset < input.count {
            let end = min(offset + samplesPerAnalysisFrame, input.count)
            var frame = [Float]()
            frame.reserveCapacity(end - offset)

            for index in offset..<end {
                let sample = Float(input[index]) / 32_768
                let highPassed = highPassCoefficient * (previousHighPassed + sample - previousInput)
                previousInput = sample
                previousHighPassed = highPassed
                frame.append(highPassed)
            }

            let analysis = analyze(frame)
            let threshold = max(minimumSpeechRMS, noiseRMS * 2.8)
            let plausibleSpeechShape = analysis.zeroCrossingRate >= 0.008
                && analysis.zeroCrossingRate <= 0.44
            let isSpeech = analysis.rms >= threshold
                && (plausibleSpeechShape || speechHangoverFrames > 0)

            if isSpeech {
                adjacentSpeechFrames += 1
                speechHangoverFrames = 18
            } else {
                adjacentSpeechFrames = 0
                speechHangoverFrames = max(0, speechHangoverFrames - 1)
                updateNoiseEstimate(with: analysis.rms)
            }

            let desiredGainDB = desiredGain(for: analysis, isSpeech: isSpeech)
            let oldGainDB = gainDB
            gainDB = nextGain(from: gainDB, toward: desiredGainDB, peak: analysis.peak)
            appendLeveled(frame, fromGainDB: oldGainDB, toGainDB: gainDB, into: &output)
            offset = end
        }

        return output
    }

    private func analyze(_ frame: [Float]) -> (rms: Float, peak: Float, zeroCrossingRate: Float) {
        guard !frame.isEmpty else { return (0, 0, 0) }
        var squaredSum: Float = 0
        var peak: Float = 0
        var crossings = 0

        for index in frame.indices {
            let sample = frame[index]
            squaredSum += sample * sample
            peak = max(peak, abs(sample))
            if index > frame.startIndex,
               (sample >= 0) != (frame[index - 1] >= 0) {
                crossings += 1
            }
        }

        return (
            sqrt(squaredSum / Float(frame.count)),
            peak,
            Float(crossings) / Float(frame.count)
        )
    }

    private func updateNoiseEstimate(with rms: Float) {
        let rate: Float = rms < noiseRMS ? 0.12 : 0.015
        noiseRMS += (max(0.000_001, rms) - noiseRMS) * rate
    }

    private func desiredGain(
        for analysis: (rms: Float, peak: Float, zeroCrossingRate: Float),
        isSpeech: Bool
    ) -> Float {
        guard isSpeech, analysis.rms > 0 else { return 0 }

        var desired = decibels(targetSpeechRMS / analysis.rms)
        desired = min(maximumGainDB, max(0, desired))

        if adjacentSpeechFrames < 3 {
            desired = min(desired, 3)
        }
        if analysis.peak > 0 {
            desired = min(desired, max(0, decibels(peakCeiling / analysis.peak)))
        }
        if noiseRMS > 0 {
            desired = min(desired, max(0, decibels(maximumOutputNoiseRMS / noiseRMS)))
        }
        return desired
    }

    private func nextGain(from current: Float, toward desired: Float, peak: Float) -> Float {
        let frameSeconds = Float(samplesPerAnalysisFrame) / sampleRate
        let riseStep = 12 * frameSeconds
        let fallStep = 90 * frameSeconds
        var next: Float

        if desired > current {
            next = min(desired, current + riseStep)
        } else {
            next = max(desired, current - fallStep)
        }

        if peak > 0 {
            next = min(next, max(0, decibels(peakCeiling / peak)))
        }
        return min(maximumGainDB, max(0, next))
    }

    private func appendLeveled(
        _ frame: [Float],
        fromGainDB: Float,
        toGainDB: Float,
        into output: inout [Int16]
    ) {
        let denominator = Float(max(1, frame.count - 1))
        for index in frame.indices {
            let progress = Float(index) / denominator
            let interpolatedDB = fromGainDB + (toGainDB - fromGainDB) * progress
            let gain = pow(10, interpolatedDB / 20)
            let sample = min(peakCeiling, max(-peakCeiling, frame[index] * gain))
            output.append(Int16((sample * 32_767).rounded()))
        }
    }

    private func decibels(_ linear: Float) -> Float {
        20 * log10(max(linear, 0.000_001))
    }
}
