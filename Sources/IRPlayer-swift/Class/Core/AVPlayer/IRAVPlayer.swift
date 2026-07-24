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

    private let lock = NSLock()
    private var completion: ((Bool) -> Void)?

    init(
        token: IRAVPlayerSession.Token,
        item: AVPlayerItem,
        completion: ((Bool) -> Void)?
    ) {
        self.token = token
        self.item = item
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

    weak var abstractPlayer: (any IRPlaybackBackendHost)?

    private let stateStore = IRPlayerStateStore()
    let session: IRAVPlayerSession
    let presentationLoop:
        IRAVPlayerPresentationLoop
    private let seekLock = NSLock()
    private var pendingSeekRequest: IRAVPlayerSeekRequest?

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
            if transition.current != .failed {
                abstractPlayer.error = nil
            }
            abstractPlayer.playbackBackendDidChangeState(
                previous: transition.previous,
                current: transition.current
            )
        }
    }

    var playableTime: TimeInterval = 0 {
        didSet {
            guard playableTime != oldValue,
                  let abstractPlayer else {
                return
            }
            abstractPlayer.playbackBackendDidUpdatePlayableTime(
                current: playableTime,
                total: duration
            )
        }
    }

    init(
        abstractPlayer: any IRPlaybackBackendHost,
        session: IRAVPlayerSession = IRAVPlayerSession(),
        presentationLoop:
            IRAVPlayerPresentationLoop = .system()
    ) {
        self.abstractPlayer = abstractPlayer
        self.session = session
        self.presentationLoop = presentationLoop
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
        abstractPlayer?.displayView?.setAVPlayer(nil)
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

    static func seekTime(for time: TimeInterval) -> CMTime? {
        guard time.isFinite, time >= 0 else { return nil }
        let timescale = Int32(NSEC_PER_SEC)
        guard time <=
            Double(Int64.max) / Double(timescale) else {
            return nil
        }
        let seekTime = CMTimeMakeWithSeconds(
            time,
            preferredTimescale: timescale
        )
        guard seekTime.isValid else { return nil }
        return seekTime
    }

    static func finiteSeconds(from time: CMTime) -> TimeInterval {
        let seconds = CMTimeGetSeconds(time)
        return seconds.isFinite ? seconds : 0
    }

    static func playableEndTime(
        start: TimeInterval,
        duration: TimeInterval,
        totalDuration: TimeInterval
    ) -> TimeInterval {
        let end = start + duration
        guard start.isFinite,
              duration.isFinite,
              end.isFinite else {
            return 0
        }
        return IRPlaybackTimeRange(duration: totalDuration)?
            .clamped(end) ?? 0
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

    static func resourceLoaderRedirectRequest(
        for request: URLRequest,
        headers: [String: String]?
    ) -> URLRequest? {
        IRAVPlayerSession.resourceLoaderRedirectRequest(
            for: request,
            headers: headers
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
        guard let seekTime = Self.seekTime(for: time),
              let target = session.withResources(
                default:
                    Optional<(IRAVPlayerSession.Token, AVPlayerItem)>.none,
                { resources in
                    guard resources.item.status == .readyToPlay else {
                        return nil
                    }
                    return (resources.token, resources.item)
                }
              ) else {
            completionHandler?(false)
            return
        }

        DispatchQueue.main.async { [weak self] in
            guard let self,
                  self.session.isCurrent(
                    target.0,
                    item: target.1
                  ) else {
                completionHandler?(false)
                return
            }

            self.setPlayIfNeeded()
            guard self.session.isCurrent(
                target.0,
                item: target.1
            ) else {
                completionHandler?(false)
                return
            }

            let request = IRAVPlayerSeekRequest(
                token: target.0,
                item: target.1,
                completion: completionHandler
            )
            self.installPendingSeek(request)
            target.1.seek(to: seekTime) { [weak self, weak request] finished in
                DispatchQueue.main.async {
                    guard let request else { return }
                    self?.completeSeek(request, finished: finished)
                }
            }
        }
    }

    func stop() {
        replaceEmpty()
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

    private func installPendingSeek(_ request: IRAVPlayerSeekRequest) {
        seekLock.lock()
        let displacedRequest = pendingSeekRequest
        pendingSeekRequest = request
        seekLock.unlock()
        displacedRequest?.finish(false)
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
        ) else {
            request.finish(false)
            return
        }
        playIfNeeded()
        request.finish(finished)
    }

    func cancelPendingSeek() {
        seekLock.lock()
        let request = pendingSeekRequest
        pendingSeekRequest = nil
        seekLock.unlock()
        request?.finish(false)
    }
}
