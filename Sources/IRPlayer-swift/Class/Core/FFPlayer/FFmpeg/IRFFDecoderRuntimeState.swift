import Foundation

final class IRFFDecoderRuntimeState: @unchecked Sendable {
    struct Change<Value: Equatable>: Equatable {
        let previous: Value
        let current: Value
    }

    struct Snapshot: Equatable {
        let progress: TimeInterval
        let bufferedDuration: TimeInterval
        let buffering: Bool
        let playbackFinished: Bool
        let closed: Bool
        let endOfFile: Bool
        let paused: Bool
        let seeking: Bool
        let prepareToDecode: Bool
        let reading: Bool
        let audioTimeClock: TimeInterval
        let bufferingStartTime: TimeInterval
        let hardwareDecoderEnable: Bool
        let minBufferedDuration: TimeInterval
        let isLiveStream: Bool
        let hasError: Bool
    }

    struct BeginSeekResult {
        let progressChange: Change<TimeInterval>?
        let displacedCompletion: ((Bool) -> Void)?
    }

    struct PendingSeek {
        fileprivate let id: UInt64
        let target: TimeInterval
    }

    private struct StoredSeek {
        let id: UInt64
        let target: TimeInterval
        let completion: ((Bool) -> Void)?
    }

    private struct Storage {
        var progress: TimeInterval = 0
        var bufferedDuration: TimeInterval = 0
        var buffering = false
        var playbackFinished = false
        var closed = false
        var endOfFile = false
        var paused = false
        var seeking = false
        var prepareToDecode = false
        var reading = false
        var audioTimeClock: TimeInterval = 0
        var bufferingStartTime: TimeInterval = 0
        var hardwareDecoderEnable = true
        var minBufferedDuration: TimeInterval = 0
        var isLiveStream = false
        var error: Error?
        var nextSeekID: UInt64 = 0
        var pendingSeek: StoredSeek?
        var activeSeek: StoredSeek?
        var currentVideoFrame: IRFFVideoFrame?
        var currentAudioFrame: IRFFAudioFrame?
    }

    private let lock = NSLock()
    private var storage = Storage()

    var snapshot: Snapshot {
        withLock {
            Snapshot(
                progress: storage.progress,
                bufferedDuration: storage.bufferedDuration,
                buffering: storage.buffering,
                playbackFinished: storage.playbackFinished,
                closed: storage.closed,
                endOfFile: storage.endOfFile,
                paused: storage.paused,
                seeking: storage.seeking,
                prepareToDecode: storage.prepareToDecode,
                reading: storage.reading,
                audioTimeClock: storage.audioTimeClock,
                bufferingStartTime: storage.bufferingStartTime,
                hardwareDecoderEnable: storage.hardwareDecoderEnable,
                minBufferedDuration: storage.minBufferedDuration,
                isLiveStream: storage.isLiveStream,
                hasError: storage.error != nil
            )
        }
    }

    var error: Error? {
        get { withLock { storage.error } }
        set { withLock { storage.error = newValue } }
    }

    var currentVideoFrame: IRFFVideoFrame? {
        get { withLock { storage.currentVideoFrame } }
        set { withLock { storage.currentVideoFrame = newValue } }
    }

    var currentAudioFrame: IRFFAudioFrame? {
        get { withLock { storage.currentAudioFrame } }
        set { withLock { storage.currentAudioFrame = newValue } }
    }

    @discardableResult
    func setProgress(_ value: TimeInterval) -> Change<TimeInterval>? {
        set(\.progress, to: value)
    }

    @discardableResult
    func setBufferedDuration(_ value: TimeInterval) -> Change<TimeInterval>? {
        set(\.bufferedDuration, to: value)
    }

    @discardableResult
    func applyBufferedDuration(
        requestedValue: TimeInterval,
        normalizedValue: TimeInterval
    ) -> Change<TimeInterval>? {
        withLock {
            let previous = storage.bufferedDuration
            guard requestedValue != previous else { return nil }
            storage.bufferedDuration = normalizedValue
            return Change(previous: previous, current: normalizedValue)
        }
    }

    @discardableResult
    func setBuffering(_ value: Bool) -> Change<Bool>? {
        set(\.buffering, to: value)
    }

    @discardableResult
    func applyBuffering(
        _ value: Bool,
        startTime: TimeInterval
    ) -> Change<Bool>? {
        withLock {
            let bufferingChange = change(from: storage.buffering, to: value)
            storage.buffering = value
            storage.bufferingStartTime = startTime
            return bufferingChange
        }
    }

    @discardableResult
    func setPlaybackFinished(_ value: Bool) -> Change<Bool>? {
        set(\.playbackFinished, to: value)
    }

    @discardableResult
    func setEndOfFile(_ value: Bool) -> Change<Bool>? {
        set(\.endOfFile, to: value)
    }

    @discardableResult
    func setPaused(_ value: Bool) -> Change<Bool>? {
        set(\.paused, to: value)
    }

    @discardableResult
    func setSeeking(_ value: Bool) -> Change<Bool>? {
        set(\.seeking, to: value)
    }

    @discardableResult
    func setPrepareToDecode(_ value: Bool) -> Change<Bool>? {
        set(\.prepareToDecode, to: value)
    }

    @discardableResult
    func setReading(_ value: Bool) -> Change<Bool>? {
        set(\.reading, to: value)
    }

    @discardableResult
    func setAudioTimeClock(_ value: TimeInterval) -> Change<TimeInterval>? {
        set(\.audioTimeClock, to: value)
    }

    @discardableResult
    func setBufferingStartTime(_ value: TimeInterval) -> Change<TimeInterval>? {
        set(\.bufferingStartTime, to: value)
    }

    @discardableResult
    func setHardwareDecoderEnable(_ value: Bool) -> Change<Bool>? {
        set(\.hardwareDecoderEnable, to: value)
    }

    @discardableResult
    func setMinBufferedDuration(_ value: TimeInterval) -> Change<TimeInterval>? {
        set(\.minBufferedDuration, to: value)
    }

    @discardableResult
    func setIsLiveStream(_ value: Bool) -> Change<Bool>? {
        set(\.isLiveStream, to: value)
    }

    func beginClose() -> Bool {
        withLock {
            guard !storage.closed else { return false }
            storage.closed = true
            return true
        }
    }

    func markPreparedIfOpen() -> Bool {
        withLock {
            guard !storage.closed else { return false }
            storage.prepareToDecode = true
            return true
        }
    }

    func beginSeek(
        to target: TimeInterval,
        completion: ((Bool) -> Void)?
    ) -> BeginSeekResult? {
        withLock {
            guard !storage.closed else { return nil }

            let displacedCompletion = storage.pendingSeek?.completion
            let progressChange = change(from: storage.progress, to: target)
            storage.nextSeekID &+= 1
            storage.progress = target
            storage.pendingSeek = StoredSeek(
                id: storage.nextSeekID,
                target: target,
                completion: completion
            )
            storage.seeking = true
            return BeginSeekResult(
                progressChange: progressChange,
                displacedCompletion: displacedCompletion
            )
        }
    }

    func takePendingSeek() -> PendingSeek? {
        withLock {
            guard storage.activeSeek == nil,
                  let pendingSeek = storage.pendingSeek else {
                return nil
            }

            storage.pendingSeek = nil
            storage.activeSeek = pendingSeek
            return PendingSeek(id: pendingSeek.id, target: pendingSeek.target)
        }
    }

    func finishSeek(_ request: PendingSeek) -> ((Bool) -> Void)? {
        withLock {
            guard storage.activeSeek?.id == request.id else { return nil }
            let completion = storage.activeSeek?.completion
            storage.activeSeek = nil
            storage.seeking = storage.pendingSeek != nil
            return completion
        }
    }

    func cancelSeeks() -> [((Bool) -> Void)] {
        withLock {
            let completions = [
                storage.activeSeek?.completion,
                storage.pendingSeek?.completion
            ].compactMap { $0 }
            storage.activeSeek = nil
            storage.pendingSeek = nil
            storage.seeking = false
            return completions
        }
    }

    func clearFrames() {
        withLock {
            storage.currentVideoFrame = nil
            storage.currentAudioFrame = nil
        }
    }

    private func set<Value: Equatable>(
        _ keyPath: WritableKeyPath<Storage, Value>,
        to value: Value
    ) -> Change<Value>? {
        withLock {
            let previous = storage[keyPath: keyPath]
            guard let change = change(from: previous, to: value) else {
                return nil
            }
            storage[keyPath: keyPath] = value
            return change
        }
    }

    private func change<Value: Equatable>(
        from previous: Value,
        to current: Value
    ) -> Change<Value>? {
        guard previous != current else { return nil }
        return Change(previous: previous, current: current)
    }

    private func withLock<Result>(_ body: () -> Result) -> Result {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }
}
