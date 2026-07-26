import Foundation
import UIKit

@objc public enum IRVideoType:
    Int,
    Hashable,
    Equatable,
    Sendable,
    RawRepresentable
{
    case normal
    @objc(IRVideoTypeVR)
    case vr
    case fisheye
    case pano
    case custom
}

@objc public enum IRPlayerState:
    Int,
    Hashable,
    Equatable,
    Sendable,
    RawRepresentable
{
    case none
    case buffering
    case readyToPlay
    case playing
    case suspend
    case finished
    case failed
}

public enum IRDisplayMode:
    Int,
    Hashable,
    Equatable,
    Sendable,
    RawRepresentable
{
    case normal
    case box
}

@objc public enum IRGravityMode:
    Int,
    Hashable,
    Equatable,
    Sendable,
    RawRepresentable
{
    case resize
    case resizeAspect
    case resizeAspectFill
}

enum IRPlayerBackgroundMode:
    Int,
    Hashable,
    Equatable,
    Sendable,
    RawRepresentable
{
    case nothing
    case autoPlayAndPause
    case continuing
}

enum IRPlayerVolume {
    static func normalizedFloat(from volume: CGFloat?) -> Float {
        guard let volume, volume.isFinite else { return 0 }
        return Float(IRPlayerConfiguration.normalizedVolume(volume))
    }
}

struct IRPlayerRuntimeDependencies {
    typealias BackendFactory = (
        IRPlaybackBackendKind,
        any IRPlaybackBackendHost
    ) -> (any IRPlaybackBackend)?

    let presentation: IRPlayerPresentationDependencies
    let environment: IRPlayerEnvironmentDependencies
    let backendFactory: BackendFactory

    static var system: IRPlayerRuntimeDependencies {
        IRPlayerRuntimeDependencies(
            presentation: .system,
            environment: .system,
            backendFactory: { kind, host in
                switch kind {
                case .avFoundation:
                    return IRAVPlayer(abstractPlayer: host)
                case .ffmpeg:
                    return IRFFPlayer(abstractPlayer: host)
                }
            }
        )
    }
}

@objcMembers
public class IRPlayerImp: NSObject {
    let settingsStore: IRPlayerSettingsStore
    let mediaSession: IRPlayerMediaSession
    let eventEmitter: IRPlayerEventEmitter
    let backendEventRouter: IRPlaybackBackendEventRouter

    var presentationSession: IRPlayerPresentationSession!
    var environmentSession: IRPlayerEnvironmentSession!
    var backendCoordinator: IRPlaybackBackendCoordinator!

    public var decoder: IRPlayerDecoder {
        get { settingsStore.decoder }
        set { settingsStore.decoder = newValue }
    }

    public var contentURL: NSURL? {
        mediaSession.snapshot.contentURL
    }

    public var contentHeaders: [String: String]? {
        mediaSession.snapshot.contentHeaders
    }

    @nonobjc public var mediaSource: IRMediaSource? {
        mediaSession.snapshot.source
    }

    var videoInput: IRFFVideoInput? {
        mediaSession.snapshot.videoInput
    }

    public var videoType: IRVideoType {
        settingsStore.videoType
    }

    public var error: IRError? {
        get { settingsStore.error }
        set { settingsStore.error = newValue }
    }

    public var displayMode: IRDisplayMode {
        get { settingsStore.displayMode }
        set {
            guard settingsStore.setDisplayMode(newValue) else { return }
            presentationSession.apply(
                videoType: videoType,
                displayMode: newValue
            )
        }
    }

    public var view: IRPLFView? {
        presentationSession.displayView
    }

    public var viewAnimationHidden: Bool {
        get { settingsStore.viewAnimationHidden }
        set { settingsStore.viewAnimationHidden = newValue }
    }

    public var isLiveStream: Bool {
        get { settingsStore.isLiveStream }
        set { settingsStore.isLiveStream = newValue }
    }

    public var viewGravityMode: IRGravityMode {
        get { presentationSession.viewGravityMode }
        set { presentationSession.setGravityMode(newValue) }
    }

    public var renderModes: [IRGLRenderMode]? {
        get { presentationSession.renderModes }
        set { presentationSession.setRenderModes(newValue ?? []) }
    }

    public var renderMode: IRGLRenderMode? {
        presentationSession.currentRenderMode
    }

    public var viewTapAction:
        ((_ player: IRPlayerImp, _ view: IRPLFView) -> Void)?
    {
        get { settingsStore.tapAction }
        set { settingsStore.tapAction = newValue }
    }

    var backgroundMode: IRPlayerBackgroundMode {
        get { environmentSession.mode }
        set { environmentSession.mode = newValue }
    }

    public var state: IRPlayerState {
        backendCoordinator.snapshot.state
    }

    public var presentationSize: CGSize {
        backendCoordinator.snapshot.presentationSize
    }

    public var bitrate: TimeInterval {
        backendCoordinator.snapshot.bitrate
    }

    public var progress: TimeInterval {
        backendCoordinator.snapshot.progress
    }

    public var duration: TimeInterval {
        backendCoordinator.snapshot.duration
    }

    public var playableTime: TimeInterval {
        backendCoordinator.snapshot.playableTime
    }

    public var playableBufferInterval: TimeInterval {
        get { settingsStore.playableBufferInterval }
        set {
            settingsStore.playableBufferInterval = newValue
            backendCoordinator?.reloadPlayableBufferInterval()
        }
    }

    var seeking: Bool {
        backendCoordinator.snapshot.isSeeking
    }

    public var isSeeking: Bool { seeking }

    public var activeBackend: IRDecoderType? {
        backendCoordinator.activeKind?.decoderType
    }

    public var volume: CGFloat {
        get { settingsStore.volume }
        set {
            settingsStore.volume = newValue
            backendCoordinator?.reloadVolume()
        }
    }

    var displayView: IRGLView? {
        presentationSession.displayView
    }

    var manager: IRAudioManager? {
        get { environmentSession.audioManager }
        set { environmentSession.replaceAudioManager(newValue) }
    }

    var autoplayOnLoad: Bool {
        get { settingsStore.autoplay }
        set { settingsStore.autoplay = newValue }
    }

    public override convenience init() {
        self.init(runtimeDependencies: .system)
    }

    init(runtimeDependencies: IRPlayerRuntimeDependencies) {
        settingsStore = IRPlayerSettingsStore()
        mediaSession = IRPlayerMediaSession()
        eventEmitter = IRPlayerEventEmitter()
        backendEventRouter = IRPlaybackBackendEventRouter()
        super.init()

        presentationSession = IRPlayerPresentationSession(
            gravityMode: .resizeAspect,
            videoType: .normal,
            displayMode: .normal,
            dependencies: runtimeDependencies.presentation
        )
        presentationSession.setTapHandler { [weak self] view in
            guard let self else { return }
            self.settingsStore.tapAction?(self, view)
        }

        backendEventRouter.setSink(self)

        backendCoordinator = IRPlaybackBackendCoordinator(
            factory: { [weak self] activation in
                guard let self else { return nil }
                let host = IRPlaybackBackendHostAdapter(
                    activation: activation,
                    context: self,
                    eventRouter: self.backendEventRouter
                )
                guard let backend = runtimeDependencies.backendFactory(
                    activation.kind,
                    host
                ) else {
                    return nil
                }
                return IRPlaybackBackendProduct(
                    backend: backend,
                    retaining: host
                )
            },
            didChangeActiveActivation: {
                [weak self, weak backendEventRouter] activation in
                backendEventRouter?.activate(activation)
                self?.environmentSession?.activatePlayback(
                    activation
                )
            }
        )

        environmentSession = IRPlayerEnvironmentSession(
            mode: .autoPlayAndPause,
            dependencies: runtimeDependencies.environment,
            stateProvider: { [weak self] in self?.state ?? .none },
            commandHandler: { [weak self] command in
                switch command {
                case .play:
                    self?.play()
                case .pause:
                    self?.pause()
                case .none:
                    break
                }
            }
        )
    }

    deinit {
        environmentSession.close()
        backendEventRouter.activate(nil)
        backendEventRouter.setSink(nil)
        backendCoordinator.reset()
        mediaSession.clear()
        presentationSession.close()
    }

    public class func player() -> IRPlayerImp {
        IRPlayerImp()
    }

    static func makeAVPlayerIfNeeded(
        _ player: IRAVPlayer?,
        abstractPlayer: any IRPlaybackBackendHost
    ) -> IRAVPlayer {
        player ?? IRAVPlayer(abstractPlayer: abstractPlayer)
    }

    static func makeFFPlayerIfNeeded(
        _ player: IRFFPlayer?,
        abstractPlayer: any IRPlaybackBackendHost
    ) -> IRFFPlayer {
        player ?? IRFFPlayer(abstractPlayer: abstractPlayer)
    }

    @objc(play)
    public func play() {
        IRMainThreadExecutor.sync {
            guard backendCoordinator.activeKind != nil else { return }
            if let activation = backendCoordinator.play() {
                environmentSession.playbackDidStart(
                    activation: activation
                )
            }
        }
    }

    @objc(pause)
    public func pause() {
        IRMainThreadExecutor.sync {
            if let activation = backendCoordinator.pause() {
                environmentSession.playbackDidPauseOrStop(
                    activation: activation
                )
            }
        }
    }

    @objc(seekToTime:completeHandler:)
    public func seekToTime(
        time: TimeInterval,
        completeHandler: ((Bool) -> Void)? = nil
    ) {
        IRMainThreadExecutor.sync {
            backendCoordinator.seek(
                to: time,
                completionHandler: completeHandler
            )
        }
    }

    func existingPlaybackBackend(
        for kind: IRPlaybackBackendKind
    ) -> (any IRPlaybackBackend)? {
        backendCoordinator.existingBackend(for: kind)
    }

    @objc(setRequestHeaderFields:)
    public func setRequestHeaderFields(_ fields: [String: String]?) {
        IRMainThreadExecutor.sync {
            mediaSession.setLegacyHeaders(fields)
            backendCoordinator.updateActiveContentHeaders(
                mediaSession.snapshot.contentHeaders
            )
        }
    }
}

public extension IRPlayerImp {
    @nonobjc convenience init(configuration: IRPlayerConfiguration) {
        self.init()
        apply(configuration)
    }

    @nonobjc var configuration: IRPlayerConfiguration {
        get {
            let settings = settingsStore.snapshot
            return IRPlayerConfiguration(
                decoder: settings.decoder,
                autoplay: settings.autoplay,
                isLiveStream: settings.isLiveStream,
                playableBufferInterval: settings.playableBufferInterval,
                volume: settings.volume,
                gravityMode: viewGravityMode,
                displayMode: settings.displayMode,
                backgroundPolicy: backgroundMode.publicPolicy
            )
        }
        set {
            apply(newValue)
        }
    }

    @nonobjc func apply(_ configuration: IRPlayerConfiguration) {
        decoder = configuration.decoder
        autoplayOnLoad = configuration.autoplay
        isLiveStream = configuration.isLiveStream
        playableBufferInterval = configuration.playableBufferInterval
        volume = configuration.volume
        displayMode = configuration.displayMode
        viewGravityMode = configuration.gravityMode
        backgroundMode = configuration.backgroundPolicy.lifecycleMode
    }

    @nonobjc func observeEvents(
        _ handler: @escaping (IRPlayerEvent) -> Void
    ) -> IRPlayerObservation {
        eventEmitter.observe(handler)
    }

    internal func emit(_ event: IRPlayerEvent) {
        eventEmitter.emit(event)
    }

    @nonobjc func load(_ source: IRMediaSource, autoplay: Bool? = nil) {
        IRMainThreadExecutor.sync {
            loadOnRuntimeThread(source, autoplay: autoplay)
        }
    }

    @objc(stop)
    func stop() {
        IRMainThreadExecutor.sync {
            _ = resetPlayback(
                clearError: true,
                publishFinalState: true
            )
        }
    }

    @objc(replaceEmpty)
    func replaceEmpty() {
        stop()
    }

    @objc(replaceVideoWithURL:videoType:)
    func replaceVideoWithURL(
        contentURL: NSURL?,
        videoType: IRVideoType
    ) {
        replaceVideoWithURL(
            contentURL: contentURL,
            videoType: videoType,
            videoInput: nil
        )
    }

    @nonobjc
    func replaceVideoWithURL(
        contentURL: NSURL?,
        videoType: IRVideoType = .normal,
        videoInput: IRFFVideoInput? = nil
    ) {
        IRMainThreadExecutor.sync {
            guard let contentURL else {
                let transactionGeneration = resetPlayback(
                    clearError: true,
                    publishFinalState: true
                )
                guard isCurrentResetTransaction(
                    transactionGeneration
                ) else {
                    return
                }
                setVideoType(videoType)
                return
            }
            loadOnRuntimeThread(
                IRMediaSource(
                    url: contentURL as URL,
                    headers: contentHeaders ?? [:],
                    videoType: videoType,
                    videoInput: videoInput
                ),
                autoplay: false
            )
        }
    }
}

extension IRPlayerImp {
    private func loadOnRuntimeThread(
        _ source: IRMediaSource,
        autoplay: Bool?
    ) {
        error = nil
        let previousSnapshot = backendCoordinator.snapshot
        let hadPreviousPlayback =
            backendCoordinator.activeActivation != nil
            || mediaSession.snapshot.source != nil
            || previousSnapshot != .empty
        let backendKind: IRPlaybackBackendKind
        switch source.backendResolution(using: decoder) {
        case let .backend(kind):
            backendKind = kind

        case .missingURL:
            let transactionGeneration = resetPlayback(
                clearError: true,
                publishFinalState: true,
                forceFinalPublication: true
            )
            guard isCurrentResetTransaction(
                transactionGeneration
            ) else {
                return
            }
            setVideoType(source.videoType)
            guard isCurrentResetTransaction(
                transactionGeneration
            ) else {
                return
            }
            publishLoadError(
                code: 1,
                description: "A media source URL is required."
            )
            return

        case .unsupportedSource:
            let transactionGeneration = resetPlayback(
                clearError: true,
                publishFinalState: true,
                forceFinalPublication: true
            )
            guard isCurrentResetTransaction(
                transactionGeneration
            ) else {
                return
            }
            setVideoType(source.videoType)
            guard isCurrentResetTransaction(
                transactionGeneration
            ) else {
                return
            }
            publishLoadError(
                code: 4,
                description:
                    "No playback backend supports this media source."
            )
            return

        case .unsupportedAVFoundation:
            let transactionGeneration = resetPlayback(
                clearError: true,
                publishFinalState: true,
                forceFinalPublication: true
            )
            guard isCurrentResetTransaction(
                transactionGeneration
            ) else {
                return
            }
            setVideoType(source.videoType)
            guard isCurrentResetTransaction(
                transactionGeneration
            ) else {
                return
            }
            publishLoadError(
                code: 3,
                description:
                    "AVFoundation does not support this media source configuration."
            )
            return
        }

        let replacement = backendCoordinator.replace(
            with: backendKind,
            prepare: { [self] in
                mediaSession.replace(with: source)
                setVideoType(source.videoType)
                mediaSession.bindCurrentVideoInput(to: displayView)
            }
        )

        switch replacement {
        case .superseded:
            return

        case let .unavailable(activation):
            guard finalizePlaybackReset(
                previousSnapshot: previousSnapshot,
                hadPlayback: hadPreviousPlayback || source.url != nil,
                transactionGeneration: activation.generation,
                clearError: false,
                publishFinalState: true
            ) else {
                return
            }
            publishLoadError(
                code: 2,
                description: "The requested playback backend is unavailable."
            )
            return

        case let .activated(activation, backend):
            guard backendCoordinator.isCurrent(activation) else {
                return
            }

            if source.videoInput?.outputType == .decoder {
                mediaSession.bindCurrentVideoInput(
                    to: backend.decoderVideoOutput
                )
            } else {
                mediaSession.bindCurrentVideoInput(to: displayView)
            }

            guard backendCoordinator.isCurrent(activation) else {
                return
            }
            if autoplay ?? autoplayOnLoad {
                play()
            }
        }
    }
    func setVideoType(_ videoType: IRVideoType) {
        _ = settingsStore.setVideoType(videoType)
        presentationSession.apply(
            videoType: videoType,
            displayMode: displayMode
        )
    }

    @discardableResult
    func resetPlayback(
        clearError: Bool,
        publishFinalState: Bool,
        forceFinalPublication: Bool = false
    ) -> UInt64 {
        let previousSnapshot = backendCoordinator.snapshot
        let hadPlayback =
            forceFinalPublication
            || backendCoordinator.activeActivation != nil
            || mediaSession.snapshot.source != nil
            || previousSnapshot != .empty
        let transactionGeneration =
            backendCoordinator.reset()
        _ = finalizePlaybackReset(
            previousSnapshot: previousSnapshot,
            hadPlayback: hadPlayback,
            transactionGeneration: transactionGeneration,
            clearError: clearError,
            publishFinalState: publishFinalState
        )
        return transactionGeneration
    }

    @discardableResult
    private func finalizePlaybackReset(
        previousSnapshot: IRPlaybackBackendSnapshot,
        hadPlayback: Bool,
        transactionGeneration: UInt64,
        clearError: Bool,
        publishFinalState: Bool
    ) -> Bool {
        guard isCurrentResetTransaction(
            transactionGeneration
        ) else {
            return false
        }
        mediaSession.clear()
        guard isCurrentResetTransaction(
            transactionGeneration
        ) else {
            return false
        }
        if clearError {
            error = nil
        }
        presentationSession.clearEmptyBuffer()
        guard publishFinalState,
              hadPlayback,
              isCurrentResetTransaction(
                  transactionGeneration
              ) else {
            return isCurrentResetTransaction(
                transactionGeneration
            )
        }

        receiveBackendState(
            previous: previousSnapshot.state,
            current: .none
        )
        guard isCurrentResetTransaction(
            transactionGeneration
        ) else {
            return false
        }
        receiveBackendProgress(current: 0, total: 0)
        guard isCurrentResetTransaction(
            transactionGeneration
        ) else {
            return false
        }
        receiveBackendPlayableTime(current: 0, total: 0)
        return isCurrentResetTransaction(
            transactionGeneration
        )
    }

    private func isCurrentResetTransaction(
        _ generation: UInt64
    ) -> Bool {
        backendCoordinator.isCurrentResetTransaction(generation)
    }

    func publishLoadError(code: Int, description: String) {
        let loadError = IRError()
        loadError.error = NSError(
            domain: "IRPlayer.Load",
            code: code,
            userInfo: [NSLocalizedDescriptionKey: description]
        )
        IRPlayerNotification.postPlayer(self, error: loadError)
    }
}

extension IRPlayerImp:
    IRPlaybackBackendContext,
    IRPlaybackBackendEventSink
{
    func receiveBackendState(
        previous: IRPlayerState,
        current: IRPlayerState
    ) {
        let activation = backendCoordinator.activeActivation
        switch current {
        case .playing, .buffering:
            environmentSession.playbackDidStart(
                activation: activation
            )
        case .none, .readyToPlay, .suspend, .finished, .failed:
            environmentSession.playbackDidPauseOrStop(
                activation: activation
            )
        }
        IRPlayerNotification.postPlayer(
            self,
            statePrevious: previous,
            current: current
        )
    }

    func receiveBackendProgress(
        current: TimeInterval,
        total: TimeInterval
    ) {
        IRPlayerNotification.postPlayer(
            self,
            progressPercent: IRPlayerNotificationPayload.timePercent(
                current: current,
                total: total
            ),
            current: current as NSNumber,
            total: total as NSNumber
        )
    }

    func receiveBackendPlayableTime(
        current: TimeInterval,
        total: TimeInterval
    ) {
        IRPlayerNotification.postPlayer(
            self,
            playablePercent: IRPlayerNotificationPayload.timePercent(
                current: current,
                total: total
            ),
            current: current as NSNumber,
            total: total as NSNumber
        )
    }

    func receiveBackendFailure(_ error: IRError) {
        environmentSession.playbackDidPauseOrStop(
            activation: backendCoordinator.activeActivation
        )
        IRPlayerNotification.postPlayer(self, error: error)
    }
}
