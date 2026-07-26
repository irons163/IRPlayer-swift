//
//  IRAVPlayer.swift
//  IRPlayer-swift
//
//  Created by irons on 2024/3/30.
//

import AVFoundation
import UIKit

private final class IRAVPlayerSeekRequest: @unchecked Sendable {
    let token: IRAVPlayerSession.Token
    let item: AVPlayerItem
    let backendActivation: IRPlaybackBackendActivation?

    private let lock = NSLock()
    private var completion: ((Bool) -> Void)?

    init(
        token: IRAVPlayerSession.Token,
        item: AVPlayerItem,
        backendActivation: IRPlaybackBackendActivation?,
        completion: ((Bool) -> Void)?
    ) {
        self.token = token
        self.item = item
        self.backendActivation = backendActivation
        self.completion = completion
    }

    func finish(_ finished: Bool) {
        lock.lock()
        let completion = completion
        self.completion = nil
        lock.unlock()
        completion?(finished)
    }
}

class IRAVPlayer: NSObject {
    typealias ItemSeekExecutor = (
        AVPlayerItem,
        CMTime,
        @escaping (Bool) -> Void
    ) -> Void

    static let pixelBufferRequestInterval: CGFloat = 0.03
    static let avMediaSelectionOptionTrackIDKey =
        "MediaSelectionOptionsPersistentID"
    static let AVAssetLoadKeys = ["tracks", "playable"]

    enum ItemStatusDecision: Equatable {
        case buffer
        case markReady
        case playIfNeeded
        case fail
        case failUnknown
        case ignore
    }

    enum AVAssetLoadDecision: Equatable {
        case fail
        case setupOutput
        case ignore
    }

    enum LoadedTimeRangeDecision: Equatable {
        case playIfNeeded
        case buffer
        case ignore
    }

    weak var abstractPlayer: (any IRPlaybackBackendHost)?

    private let stateStore = IRPlayerStateStore()
    let session: IRAVPlayerSession
    let presentationLoop:
        IRAVPlayerPresentationLoop
    private let itemSeekExecutor: ItemSeekExecutor
    private let seekLock = NSLock()
    private var pendingSeekRequest: IRAVPlayerSeekRequest?
    private let playableTimeLock = NSLock()
    private var storedPlayableTime: TimeInterval = 0

    var readyToPlayTime: TimeInterval = 0
    var needPlay = false
    var autoNeedPlay = false

    var videoEnable = false
    var audioEnable = false
    var videoTrack: IRPlayerTrack?
    var audioTrack: IRPlayerTrack?
    var videoTracks: [IRPlayerTrack] = []
    var audioTracks: [IRPlayerTrack] = []

    var avAsset: AVURLAsset? {
        session.withResources(default: nil) { $0.asset }
    }

    var avPlayerItem: AVPlayerItem? {
        session.withResources(default: nil) { $0.item }
    }

    var avPlayer: AVPlayer? {
        session.withResources(default: nil) { $0.player }
    }

    var avOutput: AVPlayerItemVideoOutput? {
        session.withResources(default: nil) { $0.output }
    }

    var seeking: Bool {
        seekLock.lock()
        defer { seekLock.unlock() }
        return pendingSeekRequest != nil
    }

    var state: IRPlayerState {
        get { stateStore.value }
        set {
            guard let transition = stateStore.transition(to: newValue),
                  let abstractPlayer else {
                return
            }
            let activation = abstractPlayer.activation
            if transition.current != .failed {
                abstractPlayer.error = nil
            }
            abstractPlayer.playbackBackendDidChangeState(
                previous: transition.previous,
                current: transition.current,
                activation: activation
            )
        }
    }

    var playableTime: TimeInterval {
        get {
            playableTimeLock.lock()
            defer { playableTimeLock.unlock() }
            return storedPlayableTime
        }
        set {
            let normalized =
                IRPlaybackTimeValue.normalizedOrZero(newValue)
            playableTimeLock.lock()
            let changed = storedPlayableTime != normalized
            storedPlayableTime = normalized
            playableTimeLock.unlock()
            guard changed, let abstractPlayer else { return }
            abstractPlayer.playbackBackendDidUpdatePlayableTime(
                current: normalized,
                total: duration,
                activation: abstractPlayer.activation
            )
        }
    }

    init(
        abstractPlayer: any IRPlaybackBackendHost,
        session: IRAVPlayerSession = IRAVPlayerSession(),
        presentationLoop:
            IRAVPlayerPresentationLoop = .system(),
        itemSeekExecutor:
            @escaping ItemSeekExecutor = {
                item,
                time,
                completion in
                item.seek(
                    to: time,
                    completionHandler: completion
                )
            }
    ) {
        self.abstractPlayer = abstractPlayer
        self.session = session
        self.presentationLoop = presentationLoop
        self.itemSeekExecutor = itemSeekExecutor
        super.init()
        abstractPlayer.displayView?.irPixelFormat = .NV12_IRPixelFormat
        presentationLoop.install {
            [weak self] tick in
            self?.handlePresentationTick(tick)
        }
    }

    deinit {
        presentationLoop.close()
        cancelPendingSeek()
        if abstractPlayer?.isCurrentActivation != false {
            abstractPlayer?.displayView?.setAVPlayer(nil)
        }
        session.close()
    }
}

// MARK: - Pure playback decisions

extension IRAVPlayer {
    static func itemStatusDecision(
        status: AVPlayerItem.Status,
        currentState: IRPlayerState
    ) -> ItemStatusDecision {
        switch status {
        case .unknown:
            return .buffer

        case .readyToPlay:
            switch currentState {
            case .buffering, .playing:
                return .playIfNeeded
            case .suspend, .finished, .failed:
                return .ignore
            case .none, .readyToPlay:
                return .markReady
            @unknown default:
                return .failUnknown
            }

        case .failed:
            return .fail

        @unknown default:
            return .failUnknown
        }
    }

    static func nextStateAfterPlay(
        from state: IRPlayerState
    ) -> IRPlayerState? {
        switch state {
        case .none:
            return .buffering
        case .suspend, .readyToPlay:
            return .playing
        case .buffering, .playing, .finished, .failed:
            return nil
        @unknown default:
            return nil
        }
    }

    static func nextStateAfterPause(
        from state: IRPlayerState
    ) -> IRPlayerState? {
        guard state != .failed else { return nil }
        return .suspend
    }

    static func shouldRetryPlayAfterDelay(
        for state: IRPlayerState
    ) -> Bool {
        switch state {
        case .buffering, .playing, .readyToPlay:
            return true
        case .none, .suspend, .finished, .failed:
            return false
        @unknown default:
            return false
        }
    }

    static func isActivePlaybackState(_ state: IRPlayerState) -> Bool {
        switch state {
        case .buffering, .playing:
            return true
        case .none, .readyToPlay, .suspend, .finished, .failed:
            return false
        @unknown default:
            return false
        }
    }

    static func seekTime(
        for time: TimeInterval,
        duration: TimeInterval = 0
    ) -> CMTime? {
        guard let requestedTime =
                IRPlaybackTimeValue.normalized(time) else {
            return nil
        }
        let boundedDuration =
            IRPlaybackTimeValue.normalized(duration) ?? 0
        let targetTime =
            boundedDuration > 0
            ? min(requestedTime, boundedDuration)
            : requestedTime
        let timescale = Int32(NSEC_PER_SEC)
        let seekTime = CMTimeMakeWithSeconds(
            targetTime,
            preferredTimescale: timescale
        )
        guard seekTime.isValid else { return nil }
        return seekTime
    }

    static func finiteSeconds(from time: CMTime) -> TimeInterval {
        IRPlaybackTimeValue.normalizedOrZero(
            CMTimeGetSeconds(time)
        )
    }

    static func playableEndTime(
        start: TimeInterval,
        duration: TimeInterval,
        totalDuration: TimeInterval
    ) -> TimeInterval {
        guard let start = IRPlaybackTimeValue.normalized(start),
              let duration = IRPlaybackTimeValue.normalized(duration),
              let totalDuration =
                IRPlaybackTimeValue.normalized(totalDuration),
              let end =
                IRPlaybackTimeValue.normalized(start + duration) else {
            return 0
        }
        guard totalDuration > 0 else { return end }
        return min(end, totalDuration)
    }

    static func loadedTimeRangeDecision(
        playableTime: TimeInterval,
        progress: TimeInterval,
        totalDuration: TimeInterval,
        playableBufferInterval: TimeInterval
    ) -> LoadedTimeRangeDecision {
        guard let playableTime =
                IRPlaybackTimeValue.normalized(playableTime),
              let progress =
                IRPlaybackTimeValue.normalized(progress),
              let totalDuration =
                IRPlaybackTimeValue.normalized(totalDuration),
              let playableBufferInterval =
                IRPlaybackTimeValue.normalized(
                    playableBufferInterval
                ) else {
            return .ignore
        }

        let playableInterval = playableTime - progress
        if playableInterval > playableBufferInterval {
            return .playIfNeeded
        }

        let remainingDuration = totalDuration - progress
        if playableInterval < 0.3 && remainingDuration > 1.5 {
            return .buffer
        }
        return .ignore
    }

    static func avAssetLoadDecision(
        keyStatuses: [AVKeyValueStatus],
        trackStatus: AVKeyValueStatus?
    ) -> AVAssetLoadDecision {
        IRAVPlayerSession.assetLoadDecision(
            keyStatuses: keyStatuses,
            trackStatus: trackStatus
        )
    }

}

// MARK: - Playback commands

extension IRAVPlayer {
    func play() {
        if state == .failed || state == .finished {
            replaceEmpty()
        }

        tryReplaceVideo()
        guard let token = session.currentToken else { return }

        if state == .none {
            needPlay = true
        }
        if let nextState = Self.nextStateAfterPlay(from: state) {
            state = nextState
        }
        session.withCurrentPlayer(token) { $0.play() }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            [weak self] in
            guard let self,
                  Self.shouldRetryPlayAfterDelay(for: self.state) else {
                return
            }
            self.session.withCurrentPlayer(token) { $0.play() }
        }
    }

    func setAutoPlayIfNeed() {
        if Self.isActivePlaybackState(state) {
            state = .suspend
            autoNeedPlay = true
            pause()
        }
    }

    func cancelAutoPlayIfNeed() {
        autoNeedPlay = false
    }

    func autoPlayIfNeed() {
        guard autoNeedPlay else { return }
        autoNeedPlay = false
        play()
    }

    func setPlayIfNeeded() {
        guard Self.isActivePlaybackState(state),
              let token = session.currentToken else {
            return
        }
        needPlay = true
        state = .buffering
        session.withCurrentPlayer(token) { $0.pause() }
    }

    func cancelPlayIfNeeded() {
        needPlay = false
    }

    func playIfNeeded() {
        guard needPlay, let token = session.currentToken else { return }
        needPlay = false
        state = .playing
        session.withCurrentPlayer(token) { $0.play() }
    }

    func pause() {
        guard let nextState = Self.nextStateAfterPause(from: state),
              let token = session.currentToken else {
            return
        }
        cancelPlayIfNeeded()
        state = nextState
        session.withCurrentPlayer(token) { $0.pause() }
    }

    func seek(
        to time: TimeInterval,
        completionHandler: ((Bool) -> Void)? = nil
    ) {
        guard let target = session.withResources(
                default:
                    Optional<(
                        token: IRAVPlayerSession.Token,
                        item: AVPlayerItem,
                        seekTime: CMTime
                    )>.none,
                { resources in
                    guard resources.item.status == .readyToPlay,
                          let seekTime = Self.seekTime(
                              for: time,
                              duration: Self.finiteSeconds(
                                  from: resources.item.duration
                              )
                          ) else {
                        return nil
                    }
                    return (
                        token: resources.token,
                        item: resources.item,
                        seekTime: seekTime
                    )
                }
              ) else {
            completionHandler?(false)
            return
        }

        DispatchQueue.main.async { [weak self] in
            guard let self,
                  self.session.isCurrent(
                    target.token,
                    item: target.item
                  ) else {
                completionHandler?(false)
                return
            }

            self.setPlayIfNeeded()
            guard self.session.isCurrent(
                target.token,
                item: target.item
            ) else {
                completionHandler?(false)
                return
            }

            let request = IRAVPlayerSeekRequest(
                token: target.token,
                item: target.item,
                backendActivation:
                    self.abstractPlayer?.activation,
                completion: completionHandler
            )
            guard self.installPendingSeek(request),
                  self.isSeekRequestCurrent(request) else {
                request.finish(false)
                return
            }
            self.itemSeekExecutor(
                target.item,
                target.seekTime
            ) { [weak self, weak request] finished in
                DispatchQueue.main.async {
                    guard let request else { return }
                    self?.completeSeek(request, finished: finished)
                }
            }
        }
    }

    func stop() {
        replaceEmpty(allowInactiveCleanup: true)
    }

    var progress: TimeInterval {
        session.withResources(default: 0) {
            Self.finiteSeconds(from: $0.item.currentTime())
        }
    }

    var duration: TimeInterval {
        session.withResources(default: 0) {
            Self.finiteSeconds(from: $0.item.duration)
        }
    }

    var bitrate: TimeInterval { 0 }

    var snapshot: IRPlaybackBackendSnapshot {
        for _ in 0..<3 {
            let token = session.currentToken
            let resourceSnapshot = session.withResources(
                default:
                    Optional<(
                        presentationSize: CGSize,
                        progress: TimeInterval,
                        duration: TimeInterval
                    )>.none
            ) { resources in
                guard resources.token == token else { return nil }
                return (
                    presentationSize: resources.item.presentationSize,
                    progress: Self.finiteSeconds(
                        from: resources.item.currentTime()
                    ),
                    duration: Self.finiteSeconds(
                        from: resources.item.duration
                    )
                )
            }
            let snapshot = IRPlaybackBackendSnapshot(
                state: stateStore.value,
                presentationSize:
                    resourceSnapshot?.presentationSize ?? .zero,
                bitrate: 0,
                progress: resourceSnapshot?.progress ?? 0,
                duration: resourceSnapshot?.duration ?? 0,
                playableTime: playableTime,
                isSeeking: seeking
            )
            guard session.currentToken == token else { continue }
            return snapshot
        }
        return .empty
    }

    private func installPendingSeek(
        _ request: IRAVPlayerSeekRequest
    ) -> Bool {
        seekLock.lock()
        let displacedRequest = pendingSeekRequest
        pendingSeekRequest = request
        seekLock.unlock()
        displacedRequest?.finish(false)
        guard isSeekRequestCurrent(request) else {
            seekLock.lock()
            if pendingSeekRequest === request {
                pendingSeekRequest = nil
            }
            seekLock.unlock()
            request.finish(false)
            return false
        }
        return true
    }

    private func completeSeek(
        _ request: IRAVPlayerSeekRequest,
        finished: Bool
    ) {
        seekLock.lock()
        guard pendingSeekRequest === request else {
            seekLock.unlock()
            request.finish(false)
            return
        }
        pendingSeekRequest = nil
        seekLock.unlock()

        guard session.isCurrent(
            request.token,
            item: request.item
        ), isBackendActivationCurrent(
            request.backendActivation
        ) else {
            request.finish(false)
            return
        }
        playIfNeeded()
        guard session.isCurrent(
            request.token,
            item: request.item
        ), isBackendActivationCurrent(
            request.backendActivation
        ) else {
            request.finish(false)
            return
        }
        request.finish(finished)
    }

    func cancelPendingSeek() {
        seekLock.lock()
        let request = pendingSeekRequest
        pendingSeekRequest = nil
        seekLock.unlock()
        request?.finish(false)
    }

    private func isSeekRequestCurrent(
        _ request: IRAVPlayerSeekRequest
    ) -> Bool {
        seekLock.lock()
        let isPending = pendingSeekRequest === request
        seekLock.unlock()
        return isPending
            && session.isCurrent(
                request.token,
                item: request.item
            )
            && isBackendActivationCurrent(
                request.backendActivation
            )
    }

    private func isBackendActivationCurrent(
        _ activation: IRPlaybackBackendActivation?
    ) -> Bool {
        guard let abstractPlayer,
              abstractPlayer.activation == activation else {
            return false
        }
        return abstractPlayer.isCurrentActivation
    }
}
