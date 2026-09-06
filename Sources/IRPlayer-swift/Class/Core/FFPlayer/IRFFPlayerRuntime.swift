import CoreGraphics
import Foundation

final class IRFFPlayerRuntime: @unchecked Sendable {
    struct Diagnostics {
        let isClosed: Bool
        let state: IRPlayerState
        let playRequested: Bool
        let hasPreparedOnce: Bool
        let progress: TimeInterval
        let playableTime: TimeInterval
        let lifecycleGeneration: UInt64
        let playbackCommandGeneration: UInt64
        let stateTransitionCount: Int
        let commandCount: Int
        let resetCount: Int
        let closeCount: Int
        let rejectedCommandCount: Int
        let executor: IRFFPlayerExecutor.Diagnostics
        let decoderSession: IRFFPlayerDecoderSession.Diagnostics
    }

    struct ProgressPostDecision: Equatable, Sendable {
        let shouldPost: Bool
        let current: TimeInterval
        let total: TimeInterval
        let nextLastPostTime: TimeInterval
    }

    struct NormalizedPlaybackTime: Equatable, Sendable {
        let current: TimeInterval
        let total: TimeInterval
        let boundedDuration: TimeInterval?
    }

    let executor: IRFFPlayerExecutor
    let decoderSession: IRFFPlayerDecoderSession
    let audioRenderer: IRFFAudioRenderer

    private weak var host: (any IRPlaybackBackendHost)?
    private var storedAudioManager: IRAudioManager?
    private var stateMachine = IRFFPlayerStateMachine()
    private var storedProgress: TimeInterval = 0
    private var storedPlayableTime: TimeInterval = 0
    private var lastPostProgressTime: TimeInterval = 0
    private var closed = false
    private var stateTransitionCount = 0
    private var commandCount = 0
    private var resetCount = 0
    private var closeCount = 0
    private var rejectedCommandCount = 0
    private var lifecycleGeneration: UInt64 = 0
    private var playbackCommandGeneration: UInt64 = 0
    private var audioSeekGeneration: UInt64 = 0
    private var activeAudioSeekGeneration: UInt64?

    init(
        host: any IRPlaybackBackendHost,
        audioManager: IRAudioManager?,
        executor: IRFFPlayerExecutor = IRFFPlayerExecutor(),
        decoderFactory: @escaping IRFFPlayerDecoderSession.DecoderFactory = {
            IRFFDecoder(
                contentURL: $0,
                videoFormat: $1,
                contentHeaders: $2,
                videoOutput: $3,
                audioOutput: $4
            )
        },
        audioRenderer: IRFFAudioRenderer = IRFFAudioRenderer()
    ) {
        self.host = host
        self.storedAudioManager = audioManager
        self.executor = executor
        self.decoderSession = IRFFPlayerDecoderSession(
            executor: executor,
            decoderFactory: decoderFactory
        )
        self.audioRenderer = audioRenderer
        _ = audioManager?.registerAudioSession()
    }

    static func progressPostDecision(
        progress: TimeInterval,
        oldProgress: TimeInterval,
        duration: TimeInterval,
        lastPostTime: TimeInterval,
        now: TimeInterval,
        seekEnabled: Bool
    ) -> ProgressPostDecision {
        let safeDuration =
            duration.isFinite && duration >= 0
            ? duration
            : 0
        guard progress != oldProgress else {
            return ProgressPostDecision(
                shouldPost: false,
                current: progress,
                total: safeDuration,
                nextLastPostTime: lastPostTime
            )
        }
        guard progress.isFinite else {
            return ProgressPostDecision(
                shouldPost: false,
                current: 0,
                total: safeDuration,
                nextLastPostTime: lastPostTime
            )
        }

        if progress <= 0.000001 || progress == safeDuration {
            return ProgressPostDecision(
                shouldPost: true,
                current: progress,
                total: safeDuration,
                nextLastPostTime: lastPostTime
            )
        }

        let elapsed = now - lastPostTime
        guard now.isFinite,
              lastPostTime.isFinite,
              elapsed.isFinite,
              elapsed >= 1 else {
            return ProgressPostDecision(
                shouldPost: false,
                current: progress,
                total: safeDuration,
                nextLastPostTime: lastPostTime
            )
        }

        return ProgressPostDecision(
            shouldPost: true,
            current: progress,
            total: seekEnabled ? safeDuration : progress,
            nextLastPostTime: now
        )
    }

    static func normalizedPlaybackTime(
        _ value: TimeInterval,
        duration: TimeInterval,
        seekEnabled: Bool,
        isLiveStream: Bool
    ) -> NormalizedPlaybackTime {
        let nonnegative =
            IRPlaybackTimeValue.normalized(value) ?? 0
        guard !isLiveStream,
              seekEnabled,
              let boundedDuration =
                IRPlaybackTimeValue.normalized(duration),
              boundedDuration > 0 else {
            return NormalizedPlaybackTime(
                current: nonnegative,
                total: nonnegative,
                boundedDuration: nil
            )
        }
        return NormalizedPlaybackTime(
            current: min(nonnegative, boundedDuration),
            total: boundedDuration,
            boundedDuration: boundedDuration
        )
    }

    var diagnostics: Diagnostics {
        executor.sync {
            Diagnostics(
                isClosed: closed,
                state: stateMachine.state,
                playRequested: stateMachine.playRequested,
                hasPreparedOnce: stateMachine.hasPreparedOnce,
                progress: storedProgress,
                playableTime: storedPlayableTime,
                lifecycleGeneration: lifecycleGeneration,
                playbackCommandGeneration: playbackCommandGeneration,
                stateTransitionCount: stateTransitionCount,
                commandCount: commandCount,
                resetCount: resetCount,
                closeCount: closeCount,
                rejectedCommandCount: rejectedCommandCount,
                executor: executor.diagnostics,
                decoderSession: decoderSession.diagnostics
            )
        }
    }

    var audioManager: IRAudioManager? {
        executor.sync { storedAudioManager }
    }

    var currentDecoder: IRFFDecoder? {
        decoderSession.currentDecoder
    }

    var state: IRPlayerState {
        get { executor.sync { stateMachine.state } }
        set {
            executor.sync {
                guard acceptCommandLocked() else { return }
                applyStateTransitionLocked(
                    stateMachine.transition(to: newValue)
                )
            }
        }
    }

    var playRequested: Bool {
        get { executor.sync { stateMachine.playRequested } }
        set {
            executor.sync {
                guard acceptCommandLocked() else { return }
                stateMachine.setPlayRequested(newValue)
                audioRenderer.setEnabled(
                    newValue
                        && activeAudioSeekGeneration == nil
                )
            }
        }
    }

    var progress: TimeInterval {
        get { executor.sync { storedProgress } }
        set {
            executor.sync {
                guard acceptCommandLocked() else { return }
                setProgressLocked(newValue)
            }
        }
    }

    var playableTime: TimeInterval {
        get { executor.sync { storedPlayableTime } }
        set {
            executor.sync {
                guard acceptCommandLocked() else { return }
                setPlayableTimeLocked(newValue)
            }
        }
    }

    var currentAudioFrame: IRFFAudioFrame? {
        get { audioRenderer.currentFrame }
        set {
            executor.sync {
                guard acceptCommandLocked() else { return }
                audioRenderer.replaceCurrentFrame(newValue)
            }
        }
    }

    var samplingRate: Float64 {
        executor.sync { storedAudioManager?.samplingRate ?? 0 }
    }

    var numberOfChannels: UInt32 {
        executor.sync { storedAudioManager?.numberOfChannels ?? 0 }
    }

    var snapshot: IRPlaybackBackendSnapshot {
        executor.sync {
            let decoder = decoderSession.currentDecoder
            let prepared = decoder?.prepareToDecode == true
            return IRPlaybackBackendSnapshot(
                state: stateMachine.state,
                presentationSize: prepared
                    ? decoder?.presentationSize ?? .zero
                    : .zero,
                bitrate: prepared ? decoder?.bitrate ?? 0 : 0,
                progress: storedProgress,
                duration: decoder?.duration ?? 0,
                playableTime: storedPlayableTime,
                isSeeking: decoder?.seeking ?? false
            )
        }
    }

    @discardableResult
    func activate(
        configuration: IRFFPlayerDecoderSession.Configuration,
        volume: CGFloat?
    ) -> IRFFPlayerDecoderSession.Token? {
        executor.sync {
            guard acceptCommandLocked() else { return nil }
            guard resetForActivationLocked() else { return nil }
            let token = decoderSession.activate(
                configuration: configuration,
                eventHandler: makeDecoderEventHandler(),
                didActivate: { [weak self] decoder in
                    guard let self else { return }
                    self.audioRenderer.attachSource(decoder)
                    self.storedAudioManager?.volume =
                        IRPlayerVolume.normalizedFloat(from: volume)
                }
            )
            if token == nil {
                if let decoder = decoderSession.currentDecoder {
                    audioRenderer.attachSource(decoder)
                } else {
                    audioRenderer.reset()
                }
            }
            return token
        }
    }

    @discardableResult
    func adopt(_ decoder: IRFFDecoder?) -> IRFFPlayerDecoderSession.Token? {
        executor.sync {
            guard acceptCommandLocked() else { return nil }
            guard resetForActivationLocked() else { return nil }
            guard let decoder else { return nil }
            return decoderSession.adopt(
                decoder,
                eventHandler: makeDecoderEventHandler(),
                didActivate: { [weak self] decoder in
                    self?.audioRenderer.attachSource(decoder)
                }
            )
        }
    }

    func play() {
        executor.sync {
            guard acceptCommandLocked() else { return }
            commandCount += 1
            playbackCommandGeneration &+= 1
            let commandGeneration = playbackCommandGeneration
            let expectedLifecycleGeneration = lifecycleGeneration
            stateMachine.setPlayRequested(true)
            audioRenderer.setEnabled(
                activeAudioSeekGeneration == nil
            )
            _ = decoderSession.withCurrentDecoder(default: false) {
                $0.resume()
                return true
            }
            guard acceptsPlaybackContinuationLocked(
                commandGeneration: commandGeneration,
                lifecycleGeneration: expectedLifecycleGeneration
            ) else {
                return
            }

            let decision = stateMachine.beginPlay()
            if decision.shouldSeekToStart {
                let decoderAlreadyRestarted =
                    decoderSession.withCurrentDecoder(default: false) {
                        $0.seeking
                    }
                if !decoderAlreadyRestarted {
                    decoderSession.seek(to: 0, completion: nil)
                }
                guard acceptsPlaybackContinuationLocked(
                    commandGeneration: commandGeneration,
                    lifecycleGeneration: expectedLifecycleGeneration
                ) else {
                    return
                }
            }
            applyStateTransitionLocked(
                stateMachine.transition(to: decision.nextState)
            )
        }
    }

    func pause() {
        executor.sync {
            guard acceptCommandLocked() else { return }
            commandCount += 1
            playbackCommandGeneration &+= 1
            let commandGeneration = playbackCommandGeneration
            let expectedLifecycleGeneration = lifecycleGeneration
            stateMachine.setPlayRequested(false)
            audioRenderer.setEnabled(false)
            _ = decoderSession.withCurrentDecoder(default: false) {
                $0.pause()
                return true
            }
            guard acceptsPlaybackContinuationLocked(
                commandGeneration: commandGeneration,
                lifecycleGeneration: expectedLifecycleGeneration
            ) else {
                return
            }
            applyStateTransitionLocked(stateMachine.beginPause())
        }
    }

    func seek(
        to time: TimeInterval,
        completion: ((Bool) -> Void)?
    ) {
        executor.sync {
            guard acceptCommandLocked() else {
                completion?(false)
                return
            }
            commandCount += 1
            audioSeekGeneration &+= 1
            let seekGeneration = audioSeekGeneration
            let expectedLifecycleGeneration =
                lifecycleGeneration
            activeAudioSeekGeneration = seekGeneration
            storedAudioManager?.pause()
            audioRenderer.suspendAndDrain()
            decoderSession.seek(to: time) {
                [weak self] finished in
                guard let self else {
                    completion?(false)
                    return
                }
                self.executor.sync {
                    guard self.lifecycleGeneration
                            == expectedLifecycleGeneration else {
                        completion?(false)
                        return
                    }
                    guard self.activeAudioSeekGeneration
                            == seekGeneration else {
                        completion?(finished)
                        return
                    }
                    self.activeAudioSeekGeneration = nil
                    self.restoreAudioAfterSeekLocked()
                    completion?(finished)
                }
            }
        }
    }

    func reloadVolume(_ volume: CGFloat?) {
        executor.sync {
            guard acceptCommandLocked() else { return }
            storedAudioManager?.volume =
                IRPlayerVolume.normalizedFloat(from: volume)
        }
    }

    func reloadPlayableBufferInterval(
        requestedInterval: TimeInterval,
        isLiveStream: Bool
    ) {
        executor.sync {
            guard acceptCommandLocked() else { return }
            _ = decoderSession.withCurrentDecoder(default: false) { decoder in
                decoder.isLiveStream = isLiveStream
                decoder.minBufferedDuration = Self.minimumBufferedDuration(
                    requestedInterval: requestedInterval,
                    isLiveStream: isLiveStream
                )
                return true
            }
        }
    }

    @discardableResult
    func reset() -> Bool {
        executor.sync {
            guard acceptCommandLocked() else { return false }
            commandCount += 1
            return resetLocked(notify: true)
        }
    }

    func fail(_ error: NSError) {
        executor.sync {
            guard acceptCommandLocked() else { return }
            failLocked(error)
        }
    }

    @discardableResult
    func close() -> Bool {
        executor.sync {
            guard !closed else { return false }
            closed = true
            lifecycleGeneration &+= 1
            activeAudioSeekGeneration = nil
            storedAudioManager?.pause()
            audioRenderer.reset()
            decoderSession.close()
            stateMachine.clearSilently()
            storedProgress = 0
            storedPlayableTime = 0
            lastPostProgressTime = 0
            storedAudioManager?.unregisterAudioSession()
            storedAudioManager = nil
            host = nil
            closeCount += 1
            return true
        }
    }

    static func minimumBufferedDuration(
        requestedInterval: TimeInterval,
        isLiveStream: Bool
    ) -> TimeInterval {
        guard isLiveStream else { return requestedInterval }
        let bounded = min(requestedInterval, 0.2)
        return bounded == 0 ? 0.2 : bounded
    }

    private func makeDecoderEventHandler()
        -> IRFFPlayerDecoderSession.EventHandler
    {
        { [weak self] event in
            self?.handleDecoderEventLocked(event)
        }
    }

    private func handleDecoderEventLocked(
        _ event: IRFFPlayerDecoderSession.Event
    ) {
        guard !closed else { return }
        switch event {
        case .willOpenInput:
            applyStateTransitionLocked(
                stateMachine.transition(to: .buffering)
            )
        case .prepared:
            applyStateTransitionLocked(
                stateMachine.applyPrepared()
            )
        case .endOfFile:
            setPlayableTimeLocked(currentDurationLocked())
        case .playbackFinished:
            applyStateTransitionLocked(
                stateMachine.transition(to: .finished)
            )
        case .failed(let error):
            failLocked(error)
        case .bufferingChanged(let buffering):
            applyStateTransitionLocked(
                stateMachine.applyBuffering(buffering)
            )
        case .bufferedDurationChanged(let bufferedDuration):
            setPlayableTimeLocked(storedProgress + bufferedDuration)
        case .progressChanged(let progress):
            setProgressLocked(progress)
        }
    }

    @discardableResult
    private func resetLocked(notify: Bool) -> Bool {
        lifecycleGeneration &+= 1
        activeAudioSeekGeneration = nil
        let audioDiagnostics = audioRenderer.diagnostics
        let hadRuntimeState =
            stateMachine.state != .none ||
            stateMachine.playRequested ||
            stateMachine.hasPreparedOnce ||
            storedProgress != 0 ||
            storedPlayableTime != 0 ||
            decoderSession.currentDecoder != nil ||
            audioDiagnostics.hasSource ||
            audioDiagnostics.hasCurrentFrame

        storedAudioManager?.pause()
        audioRenderer.reset()
        _ = decoderSession.reset()

        if notify {
            applyStateTransitionLocked(stateMachine.reset())
            setProgressLocked(0)
            setPlayableTimeLocked(0)
        } else {
            stateMachine.clearSilently()
            storedProgress = 0
            storedPlayableTime = 0
        }
        lastPostProgressTime = 0
        if hadRuntimeState {
            resetCount += 1
        }
        return hadRuntimeState
    }

    private func resetForActivationLocked() -> Bool {
        let expectedGeneration = lifecycleGeneration &+ 1
        _ = resetLocked(notify: true)
        guard !closed, lifecycleGeneration == expectedGeneration else {
            rejectedCommandCount += 1
            return false
        }
        return true
    }

    private func setProgressLocked(_ progress: TimeInterval) {
        let decoder = decoderSession.currentDecoder
        let normalized = Self.normalizedPlaybackTime(
            progress,
            duration: decoder?.duration ?? 0,
            seekEnabled: decoder?.seekEnable ?? false,
            isLiveStream:
                decoder?.isLiveStream
                ?? host?.isLiveStream
                ?? false
        )
        let oldProgress = storedProgress
        guard normalized.current != oldProgress else { return }
        storedProgress = normalized.current

        let decision = Self.progressPostDecision(
            progress: normalized.current,
            oldProgress: oldProgress,
            duration: normalized.boundedDuration ?? 0,
            lastPostTime: lastPostProgressTime,
            now: Date().timeIntervalSince1970,
            seekEnabled: normalized.boundedDuration != nil
        )
        guard decision.shouldPost else { return }
        lastPostProgressTime = decision.nextLastPostTime
        host?.playbackBackendDidUpdateProgress(
            current: decision.current,
            total: decision.total
        )
    }

    private func setPlayableTimeLocked(_ playableTime: TimeInterval) {
        let decoder = decoderSession.currentDecoder
        let normalized = Self.normalizedPlaybackTime(
            playableTime,
            duration: decoder?.duration ?? 0,
            seekEnabled: decoder?.seekEnable ?? false,
            isLiveStream:
                decoder?.isLiveStream
                ?? host?.isLiveStream
                ?? false
        )
        guard normalized.current != storedPlayableTime else {
            return
        }
        storedPlayableTime = normalized.current
        host?.playbackBackendDidUpdatePlayableTime(
            current: normalized.current,
            total: normalized.total
        )
    }

    private func applyStateTransitionLocked(
        _ transition: IRFFPlayerStateMachine.Transition?
    ) {
        guard let transition else { return }
        if transition.current != .failed {
            host?.error = nil
        }
        if transition.current == .playing,
           activeAudioSeekGeneration == nil {
            audioRenderer.setEnabled(true)
            if storedAudioManager?.play(withDelegate: audioRenderer) == false {
                audioRenderer.setEnabled(false)
            }
        } else {
            storedAudioManager?.pause()
            audioRenderer.setEnabled(false)
        }
        stateTransitionCount += 1
        host?.playbackBackendDidChangeState(
            previous: transition.previous,
            current: transition.current
        )
    }

    private func restoreAudioAfterSeekLocked() {
        guard !closed,
              stateMachine.playRequested,
              stateMachine.state == .playing else {
            audioRenderer.setEnabled(false)
            return
        }
        audioRenderer.setEnabled(true)
        if storedAudioManager?.play(withDelegate: audioRenderer) == false {
            audioRenderer.setEnabled(false)
        }
    }

    private func failLocked(_ error: NSError) {
        let expectedLifecycleGeneration = lifecycleGeneration
        let expectedDecoderToken = decoderSession.currentToken
        let playerError = IRError()
        playerError.error = error
        host?.error = playerError
        applyStateTransitionLocked(
            stateMachine.transition(to: .failed)
        )
        guard lifecycleGeneration == expectedLifecycleGeneration,
              decoderSession.currentToken == expectedDecoderToken else {
            return
        }
        host?.playbackBackendDidFail(playerError)
    }

    private func currentDurationLocked() -> TimeInterval {
        decoderSession.withCurrentDecoder(default: 0) { $0.duration }
    }

    private func acceptCommandLocked() -> Bool {
        guard !closed else {
            rejectedCommandCount += 1
            return false
        }
        return true
    }

    private func acceptsPlaybackContinuationLocked(
        commandGeneration: UInt64,
        lifecycleGeneration: UInt64
    ) -> Bool {
        !closed &&
            playbackCommandGeneration == commandGeneration &&
            self.lifecycleGeneration == lifecycleGeneration
    }

    deinit {
        close()
    }
}
