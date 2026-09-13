import Foundation

struct TranscriptionOptions: Sendable, Equatable {
    var languageBias: [String]
    var keywords: [String]
}

enum TranscriptEvent: Sendable, Equatable {
    case partial(String)
    case final(String)
    case failure(String)
}

protocol TranscriptionStream: Sendable {
    var events: AsyncStream<TranscriptEvent> { get }
    func sendAudio(_ pcm: Data)
    func finish()
    func cancel()
}

protocol TranscriptionProvider: Sendable {
    var id: String { get }
    var displayName: String { get }
    var sampleRate: Int { get }
    var pricePerAudioHourUSD: Double { get }
    func connect(apiKey: String, options: TranscriptionOptions) async throws -> any TranscriptionStream
}

enum ProviderRegistry {
    static let all: [any TranscriptionProvider] = [MuseProvider()]

    static func provider(id: String) -> any TranscriptionProvider {
        all.first { $0.id == id } ?? MuseProvider()
    }

    static func estimatedCostUSD(providerID: String, audioSeconds: Double) -> Double {
        let provider = provider(id: providerID)
        return max(0, audioSeconds) / 3_600 * provider.pricePerAudioHourUSD
    }
}

enum TranscriptionError: LocalizedError {
    case missingAPIKey
    case handshake(String)
    case closed(String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "Add a Muse API key in Settings."
        case .handshake(let message), .closed(let message):
            return message
        }
    }
}
