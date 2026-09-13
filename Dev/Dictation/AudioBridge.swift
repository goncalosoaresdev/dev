import Foundation

/// Thread-safe queue so mic frames are kept while Muse is still connecting.
final class AudioBridge: @unchecked Sendable {
    private let lock = NSLock()
    private var pending: [Data] = []
    private var stream: (any TranscriptionStream)?
    private let maxPendingFrames = 50

    func send(_ data: Data) {
        lock.lock()
        if let stream {
            lock.unlock()
            stream.sendAudio(data)
            return
        }
        pending.append(data)
        if pending.count > maxPendingFrames {
            pending.removeFirst(pending.count - maxPendingFrames)
        }
        lock.unlock()
    }

    func attach(_ stream: any TranscriptionStream) {
        lock.lock()
        self.stream = stream
        let queued = pending
        pending.removeAll()
        lock.unlock()
        for chunk in queued {
            stream.sendAudio(chunk)
        }
    }
}
