@preconcurrency import AVFoundation
import Foundation

enum AudioCaptureError: LocalizedError {
    case badFormat
    case engine(String)

    var errorDescription: String? {
        switch self {
        case .badFormat:
            return "Could not configure the microphone."
        case .engine(let message):
            return message
        }
    }
}

final class AudioCapture: @unchecked Sendable {
    static let frameMilliseconds = 80

    var onFrame: (@Sendable (Data) -> Void)?
    var onLevel: (@Sendable (Float) -> Void)?

    private let sampleRate: Double
    private let frameSamples: Int
    private let speechLevelProcessor: SpeechLevelProcessor?
    private let engine = AVAudioEngine()
    private let lock = NSLock()
    private var remainder = Data()
    private var converter: AVAudioConverter?
    private var tapping = false

    init(sampleRate: Int) {
        self.sampleRate = Double(sampleRate)
        self.frameSamples = sampleRate * Self.frameMilliseconds / 1000
        let storedPreference = UserDefaults.standard.object(forKey: "audio.quietSpeechEnhancement.enabled")
        let enhancementEnabled = storedPreference as? Bool ?? true
        speechLevelProcessor = enhancementEnabled ? SpeechLevelProcessor(sampleRate: sampleRate) : nil
    }

    func start() throws {
        stop()

        let input = engine.inputNode
        let inputFormat = input.inputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0,
              let outputFormat = AVAudioFormat(
                commonFormat: .pcmFormatInt16,
                sampleRate: sampleRate,
                channels: 1,
                interleaved: true
              ),
              let converter = AVAudioConverter(from: inputFormat, to: outputFormat)
        else {
            engine.stop()
            throw AudioCaptureError.badFormat
        }

        self.converter = converter
        input.installTap(onBus: 0, bufferSize: 2048, format: inputFormat) { [weak self] buffer, _ in
            self?.convert(buffer, converter: converter, outputFormat: outputFormat)
        }
        tapping = true
        do {
            engine.prepare()
            try engine.start()
        } catch {
            stop()
            throw error
        }
    }

    func stop() {
        if tapping {
            engine.inputNode.removeTap(onBus: 0)
            tapping = false
        }
        if engine.isRunning {
            engine.stop()
        }
        converter?.reset()
        converter = nil

        lock.lock()
        let tail = remainder
        remainder = Data()
        lock.unlock()
        if !tail.isEmpty {
            onFrame?(speechLevelProcessor?.process(tail) ?? tail)
        }
        speechLevelProcessor?.reset()
        onLevel?(0)
    }

    private func convert(
        _ buffer: AVAudioPCMBuffer,
        converter: AVAudioConverter,
        outputFormat: AVAudioFormat
    ) {
        let ratio = outputFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up) + 32)
        guard let output = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: capacity) else { return }

        var error: NSError?
        let once = InputOnce()
        let status = converter.convert(to: output, error: &error) { _, outStatus in
            if once.done {
                outStatus.pointee = .noDataNow
                return nil
            }
            once.done = true
            outStatus.pointee = .haveData
            return buffer
        }
        guard status != .error, error == nil, output.frameLength > 0, let samples = output.int16ChannelData else {
            return
        }

        let count = Int(output.frameLength)
        let bytes = count * MemoryLayout<Int16>.size
        let data = Data(bytes: samples[0], count: bytes)
        let rms = Self.rms(samples[0], count: count)

        lock.lock()
        remainder.append(data)
        let frameBytes = frameSamples * MemoryLayout<Int16>.size
        var chunks: [Data] = []
        while remainder.count >= frameBytes {
            chunks.append(Data(remainder.prefix(frameBytes)))
            remainder.removeSubrange(..<frameBytes)
        }
        lock.unlock()

        for chunk in chunks {
            onFrame?(speechLevelProcessor?.process(chunk) ?? chunk)
        }
        onLevel?(min(1, rms * 10))
    }

    private final class InputOnce: @unchecked Sendable {
        var done = false
    }

    private static func rms(_ samples: UnsafePointer<Int16>, count: Int) -> Float {
        var sum: Float = 0
        for i in 0..<count {
            let sample = Float(samples[i]) / 32768
            sum += sample * sample
        }
        return count == 0 ? 0 : sqrt(sum / Float(count))
    }
}
