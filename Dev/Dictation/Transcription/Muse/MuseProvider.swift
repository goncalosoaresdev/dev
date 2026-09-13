import Foundation

struct MuseProvider: TranscriptionProvider {
    let id = "muse"
    let displayName = "Muse"
    let sampleRate = MuseAPI.sampleRate
    let pricePerAudioHourUSD = 0.18

    func connect(apiKey: String, options: TranscriptionOptions) async throws -> any TranscriptionStream {
        try await MuseStream.connect(apiKey: apiKey, options: options)
    }
}

final class MuseStream: TranscriptionStream, @unchecked Sendable {
    let events: AsyncStream<TranscriptEvent>

    private let continuation: AsyncStream<TranscriptEvent>.Continuation
    private let queue = DispatchQueue(label: "dev.muse", qos: .userInitiated)
    private let delegate = WebSocketDelegate()
    private var session: URLSession!
    private var task: URLSessionWebSocketTask?
    private var pending: [Data] = []
    private var ready = false
    private var wantsEnd = false
    private var ended = false
    private var handshakeWait: CheckedContinuation<Void, Error>?
    private var sawFinal = false
    private var continuationFinished = false
    private var lastText = ""

    static func connect(apiKey: String, options: TranscriptionOptions) async throws -> MuseStream {
        let stream = MuseStream()
        try await stream.open(apiKey: apiKey, options: options)
        return stream
    }

    private init() {
        let stream = AsyncStream.makeStream(of: TranscriptEvent.self, bufferingPolicy: .bufferingNewest(16))
        events = stream.stream
        continuation = stream.continuation
    }

    private func open(apiKey: String, options: TranscriptionOptions) async throws {
        let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw TranscriptionError.missingAPIKey }

        let sessionId = UUID().uuidString
        var components = URLComponents(url: MuseAPI.websocketURL, resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "sessionId", value: sessionId)]
        guard let url = components.url else {
            throw TranscriptionError.handshake("Could not build the Muse URL.")
        }

        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 300
        configuration.timeoutIntervalForResource = 600
        configuration.waitsForConnectivity = true
        let delegateQueue = OperationQueue()
        delegateQueue.name = "dev.muse.session"
        delegateQueue.maxConcurrentOperationCount = 1
        session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: delegateQueue)
        delegate.onClose = { [weak self] code, reason in
            self?.complete(lastTextAsFinal: false, closeCode: code, reason: reason)
        }
        delegate.onComplete = { [weak self] error in
            self?.complete(lastTextAsFinal: false, closeCode: nil, reason: error?.localizedDescription)
        }

        let task = session.webSocketTask(with: url)
        self.task = task
        task.resume()
        receiveLoop()

        let handshake = try Self.handshakeJSON(apiKey: trimmed, options: options)
        try await send(string: handshake)
        try await waitForHandshake()
    }

    func sendAudio(_ pcm: Data) {
        queue.async { [weak self] in
            guard let self, !self.ended else { return }
            if self.ready {
                self.sendBinary(pcm)
            } else {
                self.pending.append(pcm)
                let cap = MuseAPI.sampleRate * 2 * 4
                var buffered = self.pending.reduce(0) { $0 + $1.count }
                while buffered > cap, !self.pending.isEmpty {
                    buffered -= self.pending.removeFirst().count
                }
            }
        }
    }

    func finish() {
        queue.async { [weak self] in
            guard let self, !self.ended else { return }
            self.wantsEnd = true
            if self.ready {
                self.sendEndOfInput()
            }
            self.queue.asyncAfter(deadline: .now() + 6) { [weak self] in
                self?.complete(lastTextAsFinal: true, closeCode: nil, reason: "timed out")
            }
        }
    }

    func cancel() {
        queue.async { [weak self] in
            guard let self else { return }
            self.ended = true
            self.pending.removeAll()
            self.failHandshake(TranscriptionError.closed("Cancelled."))
            self.task?.cancel(with: .goingAway, reason: nil)
            self.finishContinuation()
        }
    }

    private func waitForHandshake() async throws {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                if self.ready {
                    continuation.resume()
                    return
                }
                self.handshakeWait = continuation
                self.queue.asyncAfter(deadline: .now() + 8) { [weak self] in
                    self?.failHandshake(TranscriptionError.handshake("Muse handshake timed out."))
                }
            }
        }
    }

    private func receiveLoop() {
        task?.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(.string(let text)):
                self.handle(text)
                self.receiveLoop()
            case .success(.data(let data)):
                if let text = String(data: data, encoding: .utf8) {
                    self.handle(text)
                }
                self.receiveLoop()
            case .success:
                self.receiveLoop()
            case .failure(let error):
                self.complete(
                    lastTextAsFinal: false,
                    closeCode: nil,
                    reason: error.localizedDescription
                )
            }
        }
    }

    private func handle(_ text: String) {
        queue.async { [weak self] in
            guard let self, let frame = MuseServerFrame.parse(text) else { return }

            if frame.isHandshake {
                self.ready = true
                self.flushPending()
                if let wait = self.handshakeWait {
                    self.handshakeWait = nil
                    wait.resume()
                }
                if self.wantsEnd {
                    self.sendEndOfInput()
                }
                return
            }

            if frame.type == "error" {
                let message = frame.message ?? "Muse returned an error."
                self.failHandshake(TranscriptionError.handshake(message))
                self.yield(.failure(message))
                self.finishContinuation()
                return
            }

            if let event = frame.asTranscriptEvent() {
                if case .partial(let text) = event {
                    self.lastText = text
                }
                if case .final(let text) = event {
                    self.lastText = text
                    self.sawFinal = true
                    self.yield(event)
                    self.finishContinuation()
                    return
                }
                self.yield(event)
            }
        }
    }

    private func complete(
        lastTextAsFinal: Bool,
        closeCode: URLSessionWebSocketTask.CloseCode?,
        reason: String?
    ) {
        queue.async { [weak self] in
            guard let self, !self.continuationFinished else { return }
            if !self.ready {
                let message: String
                if let closeCode {
                    message = Self.closeMessage(code: closeCode, reason: reason)
                } else {
                    message = reason ?? "Muse closed before completing the handshake."
                }
                let error = TranscriptionError.handshake(message)
                self.failHandshake(error)
                self.yield(.failure(message))
                self.finishContinuation()
                return
            }
            if self.sawFinal {
                self.finishContinuation()
                return
            }
            if lastTextAsFinal || self.wantsEnd {
                self.sawFinal = true
                self.yield(.final(self.lastText))
                self.finishContinuation()
                return
            }
            let message: String
            if let closeCode {
                message = Self.closeMessage(code: closeCode, reason: reason)
            } else {
                message = reason ?? "Muse closed the session."
            }
            self.failHandshake(TranscriptionError.closed(message))
            self.yield(.failure(message))
            self.finishContinuation()
        }
    }

    private func sendEndOfInput() {
        guard !ended else { return }
        ended = true
        flushPending()
        task?.send(.string(#"{"type":"endStream"}"#)) { [weak self] error in
            if let error {
                self?.complete(lastTextAsFinal: true, closeCode: nil, reason: error.localizedDescription)
            }
        }
    }

    private func yield(_ event: TranscriptEvent) {
        guard !continuationFinished else { return }
        continuation.yield(event)
    }

    private func finishContinuation() {
        guard !continuationFinished else { return }
        continuationFinished = true
        continuation.finish()
    }

    private func flushPending() {
        guard ready else { return }
        for chunk in pending {
            sendBinary(chunk)
        }
        pending.removeAll()
    }

    private func sendBinary(_ data: Data) {
        task?.send(.data(data)) { _ in }
    }

    private func send(string: String) async throws {
        guard let task else { throw TranscriptionError.handshake("Socket is not connected.") }
        try await task.send(.string(string))
    }

    private func failHandshake(_ error: Error) {
        if let wait = handshakeWait {
            handshakeWait = nil
            wait.resume(throwing: error)
        }
    }

    private static func handshakeJSON(apiKey: String, options: TranscriptionOptions) throws -> String {
        var body: [String: Any] = [
            "authorization": ["accessToken": "Bearer \(apiKey)"],
            "audioEncoding": "PCM_24KHZ",
            "model": MuseAPI.model,
            "mode": "PUSH_TO_TALK",
            "partialMode": "CUMULATIVE",
            "emitAudioProgress": false
        ]
        if !options.languageBias.isEmpty {
            body["languageBias"] = options.languageBias
        }
        if !options.keywords.isEmpty {
            body["keywords"] = options.keywords
        }
        let data = try JSONSerialization.data(withJSONObject: body, options: [])
        guard let json = String(data: data, encoding: .utf8) else {
            throw TranscriptionError.handshake("Could not encode the Muse handshake.")
        }
        return json
    }

    private static func closeMessage(code: URLSessionWebSocketTask.CloseCode, reason: String?) -> String {
        if let reason, !reason.isEmpty { return reason }
        switch code.rawValue {
        case 1008:
            return "Muse rejected the stream. Check the audio format and pacing."
        case 1011:
            return "Muse hit an internal error. Try again."
        case 1013:
            return "Muse rate-limited the session. Wait a moment and try again."
        default:
            return "Muse closed the session (\(code.rawValue))."
        }
    }
}

private final class WebSocketDelegate: NSObject, URLSessionWebSocketDelegate, URLSessionTaskDelegate, @unchecked Sendable {
    var onClose: (@Sendable (URLSessionWebSocketTask.CloseCode, String?) -> Void)?
    var onComplete: (@Sendable (Error?) -> Void)?

    func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didCloseWith closeCode: URLSessionWebSocketTask.CloseCode,
        reason: Data?
    ) {
        let text = reason.flatMap { String(data: $0, encoding: .utf8) }
        onClose?(closeCode, text)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        onComplete?(error)
    }
}
