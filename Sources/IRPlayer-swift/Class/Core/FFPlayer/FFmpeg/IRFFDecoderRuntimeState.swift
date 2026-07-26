import Foundation

final class IRFFDecoderRuntimeState: @unchecked Sendable {
    struct TestingHooks {
        let willAttemptBeginSeek: (() -> Void)?
        let didAcquireBeginSeekTransition: (() -> Void)?

        init(
            willAttemptBeginSeek: (() -> Void)? = nil,
            didAcquireBeginSeekTransition:
                (() -> Void)? = nil
        ) {
            self.willAttemptBeginSeek =
                willAttemptBeginSeek
            self.didAcquireBeginSeekTransition =
                didAcquireBeginSeekTransition
        }
    }

    struct Change<Value: Equatable>: Equatable {
        let previous: Value
        let current: Value
    }

    struct GenerationStampedChange<Value: Equatable> {
        let change: Change<Value>
        let decodeGeneration: UInt64
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
        let decodeGeneration: UInt64
    }

    struct BeginSeekResult {
        let progressChange: Change<TimeInterval>?
        let displacedCompletion: ((Bool) -> Void)?
        let decodeGeneration: UInt64
        let needsWorkerRestart: Bool
    }

    struct SeekCommitResult {
        let bufferingChange: Change<Bool>?
        let completion: ((Bool) -> Void)?
    }

    struct BufferedDurationCommit {
        let bufferedDurationChange:
            Change<TimeInterval>
        let progressChange:
            Change<TimeInterval>?
        let didFinishPlayback: Bool
        let bufferingChange: Change<Bool>?
    }

    struct AudioRenderSnapshot: Equatable {
        let closed: Bool
        let hasError: Bool
        let seeking: Bool
        let buffering: Bool
        let paused: Bool
        let playbackFinished: Bool
    }

    struct PendingSeek {
        fileprivate let id: UInt64
        let target: TimeInterval
        let decodeGeneration: UInt64
    }

    private struct StoredSeek {
        let id: UInt64
        let target: TimeInterval
        let decodeGeneration: UInt64
        let completion: ((Bool) -> Void)?
    }

    private struct PendingAudioProgress {
        let value: TimeInterval
        let decodeGeneration: UInt64
    }

    private struct AudioRetirementBuffer {
        private var frames: [IRFFAudioFrame?]
        private var readIndex = 0
        private var storedCount = 0

        init(capacity: Int) {
            frames = Array(
                repeating: nil,
                count: max(1, capacity)
            )
        }

        mutating func append(_ frame: IRFFAudioFrame) -> Bool {
            guard storedCount < frames.count else {
                return false
            }
            let writeIndex =
                (readIndex + storedCount) % frames.count
            frames[writeIndex] = frame
            storedCount += 1
            return true
        }

        mutating func popFirst() -> IRFFAudioFrame? {
            guard storedCount > 0 else { return nil }
            let frame = frames[readIndex]
            frames[readIndex] = nil
            readIndex = (readIndex + 1) % frames.count
            storedCount -= 1
            return frame
        }
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
        var decodeGeneration: UInt64 = 0
        var nextSeekID: UInt64 = 0
        var pendingSeek: StoredSeek?
        var activeSeek: StoredSeek?
        var currentVideoFrame: IRFFVideoFrame?
        var currentAudioFrame: IRFFAudioFrame?
        var pendingAudioProgress:
            PendingAudioProgress?
        var activeAudioFrameID: ObjectIdentifier?
        var activeAudioFrameDuration: TimeInterval = 0
        var finishedAudioFrames =
            AudioRetirementBuffer(
                capacity:
                    IRFFFramePool
                        .audioMaximumCapacity
            )
    }

    private let lock = NSLock()
    private let transitionLock = NSRecursiveLock()
    private let testingHooks: TestingHooks
    private var storage = Storage()

    init(testingHooks: TestingHooks = TestingHooks()) {
        self.testingHooks = testingHooks
    }

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
                hasError: storage.error != nil,
                decodeGeneration:
                    storage.decodeGeneration
            )
        }
    }

    func acceptsDecodeGeneration(
        _ generation: UInt64
    ) -> Bool {
        withLock {
            !storage.closed &&
                storage.decodeGeneration == generation
        }
    }

    var error: Error? {
        withLock { storage.error }
    }

    var decodeGeneration: UInt64 {
        withLock { storage.decodeGeneration }
    }

    @discardableResult
    func commitDecodeError(
        _ error: Error,
        generation: UInt64,
        notification: () -> Void
    ) -> Bool {
        // Keep the winning commit and its internal delegate-bridge publication
        // ordered against seek/close. The bridge is part of this boundary: an
        // off-executor bridge must enqueue without waiting for the player
        // executor. It must not perform arbitrary user work here.
        withTransitionLock {
            let committed = withLock {
                guard !storage.closed,
                      storage.error == nil,
                      !storage.endOfFile,
                      storage.decodeGeneration ==
                        generation else {
                    return false
                }
                storage.error = error
                return true
            }
            guard committed else { return false }
            notification()
            return true
        }
    }

    @discardableResult
    func commitEndOfFile(
        generation: UInt64,
        notification: () -> Void
    ) -> Bool {
        withTransitionLock {
            let committed = withLock {
                guard !storage.closed,
                      storage.error == nil,
                      !storage.endOfFile,
                      storage.decodeGeneration ==
                        generation else {
                    return false
                }
                storage.endOfFile = true
                return true
            }
            guard committed else { return false }
            notification()
            return true
        }
    }

    /// Commits every state transition caused by a decoder worker's duration
    /// update before publishing its first notification. The transition gate
    /// keeps generation validation, mutation, and delivery ordered with seek
    /// and close.
    @discardableResult
    func commitBufferedDuration(
        _ requestedValue: TimeInterval,
        playbackDuration: TimeInterval,
        generation: UInt64,
        currentTime: TimeInterval,
        notification:
            (BufferedDurationCommit) -> Void
    ) -> Bool {
        withTransitionLock {
            let result: (
                accepted: Bool,
                commit:
                    BufferedDurationCommit?
            ) = withLock {
                guard !storage.closed,
                      !storage.seeking,
                      storage.error == nil,
                      storage.decodeGeneration ==
                        generation else {
                    return (false, nil)
                }

                let durationTransition =
                    IRFFDecoder
                        .bufferedDurationTransition(
                            bufferedDuration:
                                requestedValue,
                            endOfFile:
                                storage.endOfFile
                        )
                let previousDuration =
                    storage.bufferedDuration
                guard requestedValue !=
                        previousDuration else {
                    return (true, nil)
                }
                storage.bufferedDuration =
                    durationTransition
                        .bufferedDuration

                var progressChange:
                    Change<TimeInterval>?
                var didFinishPlayback = false
                if durationTransition
                        .shouldFinishPlayback,
                   !storage.playbackFinished {
                    storage.playbackFinished = true
                    didFinishPlayback = true
                    if let normalizedProgress =
                            IRFFDecoder
                                .normalizedProgress(
                                    playbackDuration,
                                    duration:
                                        playbackDuration
                                ) {
                        progressChange = change(
                            from: storage.progress,
                            to: normalizedProgress
                        )
                        storage.progress =
                            normalizedProgress
                    }
                }

                let bufferingTransition =
                    IRFFDecoder
                        .bufferingStatusTransition(
                            buffering:
                                storage.buffering,
                            bufferedDuration:
                                storage
                                    .bufferedDuration,
                            endOfFile:
                                storage.endOfFile,
                            isLiveStream:
                                storage.isLiveStream,
                            minBufferedDuration:
                                storage
                                    .minBufferedDuration,
                            bufferingStartTime:
                                storage
                                    .bufferingStartTime,
                            currentTime:
                                currentTime
                        )
                let bufferingChange = change(
                    from: storage.buffering,
                    to: bufferingTransition
                        .buffering
                )
                storage.buffering =
                    bufferingTransition.buffering
                storage.bufferingStartTime =
                    bufferingTransition
                        .bufferingStartTime

                return (
                    true,
                    BufferedDurationCommit(
                        bufferedDurationChange:
                            Change(
                                previous:
                                    previousDuration,
                                current:
                                    durationTransition
                                        .bufferedDuration
                            ),
                        progressChange:
                            progressChange,
                        didFinishPlayback:
                            didFinishPlayback,
                        bufferingChange:
                            bufferingChange
                    )
                )
            }
            guard result.accepted else {
                return false
            }
            if let commit = result.commit {
                notification(commit)
            }
            return true
        }
    }

    /// Recomputes and commits buffering from one generation-consistent
    /// snapshot, then publishes the change while still holding the transition
    /// gate.
    @discardableResult
    func commitVideoBufferingStatus(
        generation: UInt64,
        currentTime: TimeInterval,
        notification:
            (Change<Bool>) -> Void
    ) -> Bool {
        withTransitionLock {
            let result: (
                accepted: Bool,
                change: Change<Bool>?
            ) = withLock {
                guard !storage.closed,
                      !storage.seeking,
                      storage.error == nil,
                      storage.decodeGeneration ==
                        generation else {
                    return (false, nil)
                }
                let transition =
                    IRFFDecoder
                        .bufferingStatusTransition(
                            buffering:
                                storage.buffering,
                            bufferedDuration:
                                storage
                                    .bufferedDuration,
                            endOfFile:
                                storage.endOfFile,
                            isLiveStream:
                                storage.isLiveStream,
                            minBufferedDuration:
                                storage
                                    .minBufferedDuration,
                            bufferingStartTime:
                                storage
                                    .bufferingStartTime,
                            currentTime:
                                currentTime
                        )
                let bufferingChange = change(
                    from: storage.buffering,
                    to: transition.buffering
                )
                storage.buffering =
                    transition.buffering
                storage.bufferingStartTime =
                    transition
                        .bufferingStartTime
                return (true, bufferingChange)
            }
            guard result.accepted else {
                return false
            }
            if let change = result.change {
                notification(change)
            }
            return true
        }
    }

    /// Revalidates between notifications from one multi-event transaction.
    /// A delegate may synchronously seek or close because the transition lock
    /// is recursive; any remaining events from the displaced generation are
    /// suppressed when control returns.
    @discardableResult
    func notifyIfCurrentDecodeGeneration(
        _ generation: UInt64,
        notification: () -> Void
    ) -> Bool {
        withTransitionLock {
            let accepted = withLock {
                !storage.closed &&
                    !storage.seeking &&
                    storage.error == nil &&
                    storage.decodeGeneration ==
                        generation
            }
            guard accepted else { return false }
            notification()
            return true
        }
    }

    var currentVideoFrame: IRFFVideoFrame? {
        get { withLock { storage.currentVideoFrame } }
        set { withLock { storage.currentVideoFrame = newValue } }
    }

    /// Runs external delivery while the transition gate excludes cross-thread
    /// seek/close/error transitions, then revalidates after synchronous
    /// delegate reentry before publishing the frame.
    @discardableResult
    func commitDeliveredVideoFrame(
        _ frame: IRFFVideoFrame,
        generation: UInt64,
        progress: TimeInterval?,
        playbackDuration: TimeInterval,
        delivery: (IRFFVideoFrame) -> Bool,
        notification:
            (Change<TimeInterval>) -> Void
    ) -> Bool {
        withTransitionLock {
            guard withLock({
                acceptsDisplayGenerationLocked(
                    generation
                )
            }) else {
                return false
            }
            guard delivery(frame) else {
                return false
            }

            let result: (
                accepted: Bool,
                progressChange:
                    Change<TimeInterval>?
            ) = withLock {
                guard acceptsDisplayGenerationLocked(
                    generation
                ) else {
                    return (false, nil)
                }
                storage.currentVideoFrame = frame
                guard let progress,
                      let normalizedProgress =
                        IRFFDecoder
                            .normalizedProgress(
                                progress,
                                duration:
                                    playbackDuration
                            ) else {
                    return (true, nil)
                }
                let progressChange = change(
                    from: storage.progress,
                    to: normalizedProgress
                )
                storage.progress =
                    normalizedProgress
                return (true, progressChange)
            }
            guard result.accepted else {
                return false
            }
            if let progressChange =
                    result.progressChange {
                notification(progressChange)
            }
            return true
        }
    }

    /// Replays only a frame owned by the current runnable generation.
    @discardableResult
    func replayCurrentVideoFrame(
        generation: UInt64,
        delivery: (IRFFVideoFrame) -> Bool
    ) -> Bool {
        withTransitionLock {
            guard let frame = withLock({ () -> IRFFVideoFrame? in
                guard acceptsDisplayGenerationLocked(
                    generation
                ) else {
                    return nil
                }
                return storage.currentVideoFrame
            }) else {
                return false
            }
            return delivery(frame)
        }
    }

    /// A nil dequeue from a displaced worker must never clear a newer
    /// generation's retained frame.
    @discardableResult
    func clearCurrentVideoFrame(
        generation: UInt64
    ) -> Bool {
        withTransitionLock {
            withLock {
                guard acceptsDisplayGenerationLocked(
                    generation
                ) else {
                    return false
                }
                storage.currentVideoFrame = nil
                return true
            }
        }
    }

    var currentAudioFrame: IRFFAudioFrame? {
        get { withLock { storage.currentAudioFrame } }
        set { withLock { storage.currentAudioFrame = newValue } }
    }

    /// Atomically admits and records a non-blocking audio dequeue.
    ///
    /// The callback runs while the state lock is held, so it must only attempt
    /// non-waiting operations. Keeping admission and publication in one
    /// transaction prevents a dequeued frame from becoming invisible to EOF
    /// accounting when another worker briefly owns this state.
    func tryFetchAudioFrame(
        _ dequeue: (AudioRenderSnapshot) ->
            IRFFAudioFrameTransfer?
    ) -> IRFFAudioRenderLease? {
        guard lock.try() else { return nil }
        defer { lock.unlock() }
        let snapshot = AudioRenderSnapshot(
            closed: storage.closed,
            hasError: storage.error != nil,
            seeking: storage.seeking,
            buffering: storage.buffering,
            paused: storage.paused,
            playbackFinished: storage.playbackFinished
        )
        guard storage.error == nil else {
            return nil
        }
        guard storage.activeAudioFrameID == nil else {
            return nil
        }
        guard let transfer = dequeue(snapshot) else {
            return nil
        }
        let position = transfer.position.isFinite
            ? transfer.position
            : storage.audioTimeClock
        let duration =
            transfer.duration.isFinite
                && transfer.duration > 0
            ? transfer.duration
            : 0
        storage.currentAudioFrame = transfer.frame
        storage.audioTimeClock = position
        storage.pendingAudioProgress =
            PendingAudioProgress(
                value: position,
                decodeGeneration:
                    storage.decodeGeneration
            )
        storage.activeAudioFrameID =
            ObjectIdentifier(transfer.frame)
        storage.activeAudioFrameDuration = duration
        return IRFFAudioRenderLease(
            frame: transfer.frame,
            byteCount: transfer.size
        )
    }

    @discardableResult
    func tryFinishAudioFrame(
        _ identifier: ObjectIdentifier
    ) -> Bool {
        guard lock.try() else { return false }
        defer { lock.unlock() }
        return finishAudioFrameLocked(identifier)
    }

    func finishAudioFrame(
        _ identifier: ObjectIdentifier
    ) -> Bool {
        withLock {
            finishAudioFrameLocked(identifier)
        }
    }

    private func finishAudioFrameLocked(
        _ identifier: ObjectIdentifier
    ) -> Bool {
        guard storage.activeAudioFrameID == identifier else {
            return true
        }
        if let frame = storage.currentAudioFrame {
            guard storage.finishedAudioFrames
                    .append(frame) else {
                return false
            }
        }
        storage.currentAudioFrame = nil
        storage.activeAudioFrameID = nil
        storage.activeAudioFrameDuration = 0
        return true
    }

    func takeFinishedAudioFrame() -> IRFFAudioFrame? {
        withLock {
            storage.finishedAudioFrames.popFirst()
        }
    }

    var activeAudioFrameDuration: TimeInterval {
        withLock { storage.activeAudioFrameDuration }
    }

    @discardableResult
    func commitPendingAudioProgress(
        generation: UInt64,
        playbackDuration: TimeInterval,
        notification:
            (Change<TimeInterval>) -> Void
    ) -> Bool {
        withTransitionLock {
            let result: (
                accepted: Bool,
                change:
                    Change<TimeInterval>?
            ) = withLock {
                guard !storage.closed,
                      !storage.seeking,
                      storage.error == nil,
                      storage.decodeGeneration ==
                        generation,
                      let pendingProgress =
                        storage
                            .pendingAudioProgress,
                      pendingProgress
                        .decodeGeneration ==
                        generation else {
                    return (false, nil)
                }
                storage.pendingAudioProgress =
                    nil
                guard let normalizedProgress =
                        IRFFDecoder
                            .normalizedProgress(
                                pendingProgress.value,
                                duration:
                                    playbackDuration
                            ) else {
                    return (true, nil)
                }
                let progressChange = change(
                    from: storage.progress,
                    to: normalizedProgress
                )
                storage.progress =
                    normalizedProgress
                return (true, progressChange)
            }
            guard result.accepted else {
                return false
            }
            if let change = result.change {
                notification(change)
            }
            return true
        }
    }

    @discardableResult
    func setProgress(_ value: TimeInterval) -> Change<TimeInterval>? {
        setProgressWithGeneration(value)?.change
    }

    func setProgressWithGeneration(
        _ value: TimeInterval
    ) -> GenerationStampedChange<TimeInterval>? {
        setWithGeneration(\.progress, to: value)
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
        applyBufferedDurationWithGeneration(
            requestedValue: requestedValue,
            normalizedValue: normalizedValue
        )?.change
    }

    func applyBufferedDurationWithGeneration(
        requestedValue: TimeInterval,
        normalizedValue: TimeInterval
    ) -> GenerationStampedChange<TimeInterval>? {
        withLock {
            let previous = storage.bufferedDuration
            guard requestedValue != previous else { return nil }
            storage.bufferedDuration = normalizedValue
            return GenerationStampedChange(
                change: Change(
                    previous: previous,
                    current: normalizedValue
                ),
                decodeGeneration: storage.decodeGeneration
            )
        }
    }

    @discardableResult
    func setBuffering(_ value: Bool) -> Change<Bool>? {
        setBufferingWithGeneration(value)?.change
    }

    func setBufferingWithGeneration(
        _ value: Bool
    ) -> GenerationStampedChange<Bool>? {
        setWithGeneration(\.buffering, to: value)
    }

    @discardableResult
    func applyBuffering(
        _ value: Bool,
        startTime: TimeInterval
    ) -> Change<Bool>? {
        applyBufferingWithGeneration(
            value,
            startTime: startTime
        )?.change
    }

    func applyBufferingWithGeneration(
        _ value: Bool,
        startTime: TimeInterval
    ) -> GenerationStampedChange<Bool>? {
        withLock {
            let bufferingChange = change(from: storage.buffering, to: value)
            storage.buffering = value
            storage.bufferingStartTime = startTime
            guard let bufferingChange else { return nil }
            return GenerationStampedChange(
                change: bufferingChange,
                decodeGeneration: storage.decodeGeneration
            )
        }
    }

    @discardableResult
    func setPlaybackFinished(_ value: Bool) -> Change<Bool>? {
        setPlaybackFinishedWithGeneration(value)?.change
    }

    func setPlaybackFinishedWithGeneration(
        _ value: Bool
    ) -> GenerationStampedChange<Bool>? {
        setWithGeneration(\.playbackFinished, to: value)
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
        withTransitionLock {
            withLock {
                guard !storage.closed else { return false }
                storage.closed = true
                return true
            }
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
        testingHooks.willAttemptBeginSeek?()
        return withTransitionLock {
            testingHooks
                .didAcquireBeginSeekTransition?()
            return withLock {
                guard !storage.closed,
                      storage.error == nil else {
                    return nil
                }

                let displacedCompletion = storage.pendingSeek?.completion
                let progressChange = change(from: storage.progress, to: target)
                let needsWorkerRestart =
                    storage.endOfFile ||
                    storage.playbackFinished
                storage.nextSeekID &+= 1
                storage.decodeGeneration &+= 1
                storage.progress = target
                storage.pendingAudioProgress =
                    nil
                storage.endOfFile = false
                storage.playbackFinished = false
                storage.pendingSeek = StoredSeek(
                    id: storage.nextSeekID,
                    target: target,
                    decodeGeneration:
                        storage.decodeGeneration,
                    completion: completion
                )
                storage.seeking = true
                return BeginSeekResult(
                    progressChange: progressChange,
                    displacedCompletion: displacedCompletion,
                    decodeGeneration:
                        storage.decodeGeneration,
                    needsWorkerRestart:
                        needsWorkerRestart
                )
            }
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
            return PendingSeek(
                id: pendingSeek.id,
                target: pendingSeek.target,
                decodeGeneration:
                    pendingSeek.decodeGeneration
            )
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

    func commitSeek(
        _ request: PendingSeek,
        transition: IRFFDecoder.SeekCompletionTransition,
        bufferingStartTime: TimeInterval
    ) -> SeekCommitResult? {
        withLock {
            guard storage.activeSeek?.id ==
                    request.id else {
                return nil
            }
            let completion =
                storage.activeSeek?.completion
            let bufferingChange = change(
                from: storage.buffering,
                to: transition.buffering
            )
            storage.endOfFile =
                transition.endOfFile
            storage.playbackFinished =
                transition.playbackFinished
            storage.buffering =
                transition.buffering
            storage.bufferingStartTime =
                transition.buffering
                ? bufferingStartTime
                : 0
            storage.audioTimeClock =
                transition.audioTimeClock
            if transition.shouldClearFrames {
                clearFramesLocked()
            }
            storage.activeSeek = nil
            storage.seeking =
                storage.pendingSeek != nil
            return SeekCommitResult(
                bufferingChange: bufferingChange,
                completion: completion
            )
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
            clearFramesLocked()
        }
    }

    private func clearFramesLocked() {
        storage.currentVideoFrame = nil
        if storage.activeAudioFrameID == nil {
            storage.currentAudioFrame = nil
        }
        storage.pendingAudioProgress = nil
        storage.activeAudioFrameDuration = 0
    }

    private func acceptsDisplayGenerationLocked(
        _ generation: UInt64
    ) -> Bool {
        !storage.closed &&
            !storage.seeking &&
            storage.error == nil &&
            storage.decodeGeneration ==
                generation
    }

    private func set<Value: Equatable>(
        _ keyPath: WritableKeyPath<Storage, Value>,
        to value: Value
    ) -> Change<Value>? {
        setWithGeneration(keyPath, to: value)?.change
    }

    private func setWithGeneration<Value: Equatable>(
        _ keyPath: WritableKeyPath<Storage, Value>,
        to value: Value
    ) -> GenerationStampedChange<Value>? {
        withLock {
            let previous = storage[keyPath: keyPath]
            guard let change = change(from: previous, to: value) else {
                return nil
            }
            storage[keyPath: keyPath] = value
            return GenerationStampedChange(
                change: change,
                decodeGeneration: storage.decodeGeneration
            )
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

    private func withTransitionLock<Result>(
        _ body: () -> Result
    ) -> Result {
        transitionLock.lock()
        defer { transitionLock.unlock() }
        return body()
    }
}
