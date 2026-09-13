import Foundation

struct MuseServerFrame: Equatable, Sendable {
    var type: String?
    var sessionId: String?
    var transcript: String?
    var isFinal: Bool
    var message: String?
    var turnId: Int?
    var audioProcessedMs: Int?

    var isHandshake: Bool {
        type == nil && sessionId != nil
    }

    static func parse(_ text: String) -> MuseServerFrame? {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return nil
        }
        return MuseServerFrame(
            type: json["type"] as? String,
            sessionId: json["sessionId"] as? String,
            transcript: json["transcript"] as? String,
            isFinal: boolValue(json["final"]),
            message: json["message"] as? String,
            turnId: intValue(json["turnId"]),
            audioProcessedMs: intValue(json["audioProcessedMs"])
        )
    }

    func asTranscriptEvent() -> TranscriptEvent? {
        if type == "error" {
            return .failure(message ?? "Muse returned an error.")
        }
        if type == "transcript", let transcript {
            return isFinal ? .final(transcript) : .partial(transcript)
        }
        if type == "speechComplete", let transcript {
            return .final(transcript)
        }
        return nil
    }

    private static func intValue(_ value: Any?) -> Int? {
        switch value {
        case let number as Int:
            return number
        case let number as NSNumber:
            return number.intValue
        default:
            return nil
        }
    }

    private static func boolValue(_ value: Any?) -> Bool {
        switch value {
        case let flag as Bool:
            return flag
        case let number as NSNumber:
            return number.boolValue
        default:
            return false
        }
    }
}

enum MuseAPI {
    static let model = "muse-voice-transcribe-1.0"
    static let sampleRate = 24_000
    static let websocketURL = URL(string: "wss://api.meta.ai/v1/asr/realtime")!
}
