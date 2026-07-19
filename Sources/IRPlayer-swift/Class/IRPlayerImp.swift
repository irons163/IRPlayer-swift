//
//  IRPlayerImp.swift
//  IRPlayer-swift
//
//  Created by Phil Chang on 2022/4/11.
//  Copyright © 2022 Phil. All rights reserved.
//

import UIKit

// video type
@objc public enum IRVideoType: Int, Hashable, Equatable, Sendable, RawRepresentable {
    case normal // normal
    @objc(IRVideoTypeVR)
    case vr // virtual reality
    case fisheye
    case pano
    case custom
}

// player state
@objc public enum IRPlayerState: Int, Hashable, Equatable, Sendable, RawRepresentable {
    case none
    case buffering
    case readyToPlay
    case playing
    case suspend
    case finished
    case failed
}

// display mode
public enum IRDisplayMode: Int, Hashable, Equatable, Sendable, RawRepresentable {
    case normal // normal
    case box // virtual reality
}

// video content mode
@objc public enum IRGravityMode: Int, Hashable, Equatable, Sendable, RawRepresentable {
    case resize
    case resizeAspect
    case resizeAspectFill
}

// background mode
enum IRPlayerBackgroundMode: Int, Hashable, Equatable, Sendable, RawRepresentable {
    case nothing
    case autoPlayAndPause
    case continuing
}

enum IRPlayerVolume {
    static func normalizedFloat(from volume: CGFloat?) -> Float {
        guard let volume = volume, volume.isFinite else { return 0 }
        return Float(IRPlayerConfiguration.normalizedVolume(volume))
    }
}

// MARK: - IRPlayerImp
@objcMembers
public class IRPlayerImp: NSObject {

    public var decoder: IRPlayerDecoder
    public private(set) var contentURL: NSURL?
    public private(set) var contentHeaders: [String: String]?
    @nonobjc public private(set) var mediaSource: IRMediaSource?
    private(set) var videoInput: IRFFVideoInput?
    public private(set) var videoType: IRVideoType {
        didSet {
            self.setVideoType(videoType: self.videoType)
        }
    }
    public var error: IRError?

    // preview
    public var displayMode: IRDisplayMode {
        didSet {
            guard displayMode != oldValue else { return }
            setVideoType(videoType: videoType)
        }
    }
    public var view: IRPLFView? {
        return self.displayView
    } // graphics view
    public var viewAnimationHidden: Bool // default is YES
    public var isLiveStream: Bool // default is NO
    public var viewGravityMode: IRGravityMode {
        didSet {
            self.displayView?.reloadGravityMode()
        }
    } // default is IRGravityModeResizeAspect
    public var renderModes: [IRGLRenderMode]? {
        get {
            return self.displayView?.getRenderModes() as? [IRGLRenderMode]
        }
        set {
            self.displayView?.setRenderModes(newValue ?? [])
        }
    }
    public private(set) var renderMode: IRGLRenderMode?
    public var viewTapAction: ((_ player: IRPlayerImp, _ view: IRPLFView) -> Void)?

    // control
    var backgroundMode: IRPlayerBackgroundMode {
        didSet { lifecycleController.mode = backgroundMode }
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
    public var playableBufferInterval: TimeInterval = 2.0 {
        didSet {
            playableBufferInterval = IRPlayerConfiguration.normalizedBufferInterval(
                playableBufferInterval
            )
            backendCoordinator?.reloadPlayableBufferInterval()
        }
    }
    var seeking: Bool {
        backendCoordinator.snapshot.isSeeking
    }
    public var isSeeking: Bool { seeking }
    public var activeBackend: IRDecoderType? { backendCoordinator.activeKind?.decoderType }
    public var volume: CGFloat = 1 {
        didSet {
            volume = IRPlayerConfiguration.normalizedVolume(volume)
            backendCoordinator?.reloadVolume()
        }
    }

    var displayView: IRGLView?
    private var backendCoordinator: IRPlaybackBackendCoordinator!
    private var gestureControl: IRGLGestureController?
    private var sensor: IRSensor?
    private var scrollController: IRSmoothScrollController?

    private var autoplayOnLoad = false
    private let eventEmitter = IRPlayerEventEmitter()
    private let lifecycleController = IRPlayerLifecycleController()
    var manager: IRAudioManager?

    public override init() {
        self.decoder = IRPlayerDecoder.defaultDecoder()
        self.contentURL = nil
        self.videoType = .normal
        self.backgroundMode = .autoPlayAndPause
        self.displayMode = .normal
        self.viewGravityMode = .resizeAspect
        self.playableBufferInterval = 2
        self.viewAnimationHidden = true
        self.isLiveStream = false
        self.volume = 1
        super.init()
        self.backendCoordinator = IRPlaybackBackendCoordinator { [weak self] kind in
            guard let self else { return nil }
            switch kind {
            case .avFoundation:
                return Self.makeAVPlayerIfNeeded(nil, abstractPlayer: self)
            case .ffmpeg:
                return Self.makeFFPlayerIfNeeded(nil, abstractPlayer: self)
            }
        }
#if IRPLATFORM_TARGET_OS_IPHONE_OR_TV
        self.setupNotification()
#endif
        self.setupViews()
    }

    public class func player() -> IRPlayerImp {
        return IRPlayerImp()
    }

    static func makeAVPlayerIfNeeded(
        _ player: IRAVPlayer?,
        abstractPlayer: any IRPlaybackBackendHost
    ) -> IRAVPlayer {
        return player ?? IRAVPlayer(abstractPlayer: abstractPlayer)
    }

    static func makeFFPlayerIfNeeded(
        _ player: IRFFPlayer?,
        abstractPlayer: any IRPlaybackBackendHost
    ) -> IRFFPlayer {
        return player ?? IRFFPlayer(abstractPlayer: abstractPlayer)
    }

    deinit {
        self.cleanPlayer()
#if IRPLATFORM_TARGET_OS_IPHONE_OR_TV
        NotificationCenter.default.removeObserver(self)
        self.manager?.removeHandlerTarget(self)
#endif
    }

    func setupViews() {
        let displayView = createGLView()

        scrollController = IRSmoothScrollController.init(targetView: displayView)
        scrollController?.currentMode = displayView.getCurrentRenderMode()
        scrollController?.delegate = self

        gestureControl = IRGLGestureController()
        gestureControl?.addGesture(to: displayView)
        gestureControl?.currentMode = displayView.getCurrentRenderMode()
        gestureControl?.smoothScroll = scrollController
        gestureControl?.delegate = self
        self.displayView = displayView
        setVideoType(videoType: videoType)
    }

    public func setupPlayerView(_ playerView: IRPLFView) {
        guard let view = self.view else { return }
        self.cleanPlayerView()
        view.addSubview(playerView)
        playerView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            playerView.topAnchor.constraint(equalTo: view.topAnchor),
            playerView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            playerView.leftAnchor.constraint(equalTo: view.leftAnchor),
            playerView.rightAnchor.constraint(equalTo: view.rightAnchor)
        ])
    }

    public func selectRenderMode(renderMode: IRGLRenderMode) {
        _ = self.displayView?.choose(renderMode: renderMode, withImmediatelyRenderOnce: true)
        self.gestureControl?.currentMode = self.displayView?.getCurrentRenderMode()
    }

    func createGLView() -> IRGLView {
        return IRGLView(frame: .zero, player: self)
    }

    func snapshot() -> IRPLFImage? {
        //    return self.displayView.snapshot;
        return nil
    }

    public func play() {
#if IRPLATFORM_TARGET_OS_IPHONE_OR_TV
        UIApplication.shared.isIdleTimerDisabled = true
#endif
        backendCoordinator.play()
    }

    public func pause() {
#if IRPLATFORM_TARGET_OS_IPHONE_OR_TV
        UIApplication.shared.isIdleTimerDisabled = false
#endif
        backendCoordinator.pause()
    }

    public func seekToTime(time: TimeInterval, completeHandler: ((Bool) -> Void)? = nil) {
        backendCoordinator.seek(to: time, completionHandler: completeHandler)
    }

    func seekToTime(time: TimeInterval) {
//        self.seekToTime(time: time)
    }

    func existingPlaybackBackend(
        for kind: IRPlaybackBackendKind
    ) -> (any IRPlaybackBackend)? {
        backendCoordinator.existingBackend(for: kind)
    }

    public func updateGraphicsViewFrame(frame: CGRect) {
        self.displayView?.update(frame: frame)
    }

    private func setVideoType(videoType: IRVideoType) {
        guard let displayView else { return }
        let configuration = IRPlayerRenderConfiguration.make(
            videoType: videoType,
            displayMode: displayMode
        )

        if let modes = configuration.modes {
            displayView.setRenderModes(modes)
        }
        if let gravityMode = configuration.gravityMode {
            viewGravityMode = gravityMode
        }

        switch configuration.interaction {
        case .gestures:
            sensor?.stopMotionDetection()
            sensor = nil
            gestureControl?.removeGesture(to: displayView)
            gestureControl?.addGesture(to: displayView)
        case .motion:
            gestureControl?.removeGesture(to: displayView)
            sensor?.stopMotionDetection()
            let sensor = IRSensor()
            sensor.targetView = displayView
            sensor.smoothScroll = gestureControl?.smoothScroll
            self.sensor = sensor
            _ = sensor.resetUnit()
        }

        gestureControl?.currentMode = displayView.getCurrentRenderMode()
    }

    public func setRequestHeaderFields(_ fields: [String: String]?) {
        self.contentHeaders = fields
    }
}

public extension IRPlayerImp {

    @nonobjc convenience init(configuration: IRPlayerConfiguration) {
        self.init()
        apply(configuration)
    }

    @nonobjc var configuration: IRPlayerConfiguration {
        get {
            IRPlayerConfiguration(
                decoder: decoder,
                autoplay: autoplayOnLoad,
                isLiveStream: isLiveStream,
                playableBufferInterval: playableBufferInterval,
                volume: volume,
                gravityMode: viewGravityMode,
                displayMode: displayMode,
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
        error = nil
        mediaSource = source
        contentURL = source.url as NSURL?
        contentHeaders = source.headers.isEmpty ? nil : source.headers
        videoInput = source.videoInput
        videoInput?.videoOutput = displayView
        let requestedDecoderType = source.decoderType(using: decoder)
        videoType = source.videoType

        guard let backendKind = requestedDecoderType.playbackBackendKind else {
            backendCoordinator.replace(with: nil)
            videoInput?.videoOutput = nil

            let loadError = IRError()
            loadError.error = NSError(
                domain: "IRPlayer.Load",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "A media source URL is required."]
            )
            IRPlayerNotification.postPlayer(self, error: loadError)
            return
        }

        let backend = backendCoordinator.replace(with: backendKind)
        if videoInput?.outputType == .decoder {
            videoInput?.videoOutput = backend?.decoderVideoOutput
        }

        if autoplay ?? autoplayOnLoad {
            play()
        }
    }

    func stop() {
        backendCoordinator.reset()
        videoInput?.videoOutput = nil
        videoInput = nil
        mediaSource = nil
        contentURL = nil
        contentHeaders = nil
        lifecycleController.reset()
        error = nil
        displayView?.cleanEmptyBuffer()
#if IRPLATFORM_TARGET_OS_IPHONE_OR_TV
        UIApplication.shared.isIdleTimerDisabled = false
#endif
    }

    func replaceEmpty() {
        stop()
    }

    func replaceVideoWithURL(contentURL: NSURL?,
                             videoType: IRVideoType = .normal,
                             videoInput: IRFFVideoInput? = nil) {
        guard let contentURL else {
            self.videoType = videoType
            stop()
            return
        }
        load(
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

extension IRPlayerImp {

    func cleanPlayer() {
        backendCoordinator.reset()
        sensor?.stopMotionDetection()
        sensor = nil
        if self.gestureControl != nil {
            if let view = self.displayView {
                self.gestureControl?.removeGesture(to: view)
            }
            self.gestureControl = nil
        }
        if self.displayView != nil {
            self.displayView?.close()
        }

        self.cleanPlayerView()

    #if IRPLATFORM_TARGET_OS_IPHONE_OR_TV
        UIApplication.shared.isIdleTimerDisabled = false
    #endif

        self.lifecycleController.reset()
        self.error = nil
    }

    func cleanPlayerView() {
        self.view?.subviews.forEach { subview in
            subview.removeFromSuperview()
        }
    }
}

#if IRPLATFORM_TARGET_OS_IPHONE_OR_TV
extension IRPlayerImp {

    func setupNotification() {
        NotificationCenter.default.addObserver(self, selector: #selector(applicationDidEnterBackground(_:)), name: UIApplication.didEnterBackgroundNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(applicationWillEnterForeground(_:)), name: UIApplication.willEnterForegroundNotification, object: nil)

        self.manager = IRAudioManager()
        self.manager?.setHandlerTarget(self, interruption: { [weak self] (handlerTarget, audioManager, type, option) in
            guard let self = self else { return }
            switch self.lifecycleController.audioInterruption(
                type: type,
                state: self.state,
                now: Date().timeIntervalSince1970
            ) {
            case .pause:
                self.pause()
            case .none, .play:
                break
            }
        }, routeChange: { [weak self] (handlerTarget, audioManager, reason) in
            guard let self = self else { return }
            switch self.lifecycleController.audioRouteChanged(reason: reason, state: self.state) {
            case .pause:
                self.pause()
            case .none, .play:
                break
            }
        })
    }

    func applicationDidEnterBackground(_ notification: NSNotification) {
        switch lifecycleController.didEnterBackground(state: state) {
        case .pause:
            self.pause()
        case .none, .play:
            break
        }
    }

    func applicationWillEnterForeground(_ notification: NSNotification) {
        switch lifecycleController.willEnterForeground(
            state: state,
            now: Date().timeIntervalSince1970
        ) {
        case .play:
            self.play()
        case .none, .pause:
            break
        }
    }
}
#endif

// MARK: - IRPlayer Action Category
public extension IRPlayerImp {

    func registerPlayerNotification(target: Any?,
                                    stateAction: Selector? = nil,
                                    progressAction: Selector? = nil,
                                    playableAction: Selector? = nil,
                                    errorAction: Selector? = nil) {
        guard let target = target else { return }
        self.removePlayerNotification(target: target)

        if let stateAction = stateAction {
            NotificationCenter.default.addObserver(target, selector: stateAction, name: NSNotification.Name(rawValue: IRPlayerStateChangeNotificationName), object: self)
        }
        if let progressAction = progressAction {
            NotificationCenter.default.addObserver(target, selector: progressAction, name: NSNotification.Name(rawValue: IRPlayerProgressChangeNotificationName), object: self)
        }
        if let playableAction = playableAction {
            NotificationCenter.default.addObserver(target, selector: playableAction, name: NSNotification.Name(rawValue: IRPlayerPlayableChangeNotificationName), object: self)
        }
        if let errorAction = errorAction {
            NotificationCenter.default.addObserver(target, selector: errorAction, name: NSNotification.Name(rawValue: IRPlayerErrorNotificationName), object: self)
        }
    }

    func removePlayerNotification(target: Any) {
        NotificationCenter.default.removeObserver(target, name: NSNotification.Name(rawValue: IRPlayerStateChangeNotificationName), object: self)
        NotificationCenter.default.removeObserver(target, name: NSNotification.Name(rawValue: IRPlayerProgressChangeNotificationName), object: self)
        NotificationCenter.default.removeObserver(target, name: NSNotification.Name(rawValue: IRPlayerPlayableChangeNotificationName), object: self)
        NotificationCenter.default.removeObserver(target, name: NSNotification.Name(rawValue: IRPlayerErrorNotificationName), object: self)
    }
}

// MARK: - IRGLViewDelegate
extension IRPlayerImp: IRGLViewDelegate {

    public func glViewWillBeginZooming(_ glView: IRGLView?) {
        self.sensor?.stopMotionDetection()
    }

    public func glViewDidEndZooming(_ glView: IRGLView?, atScale scale: CGFloat) {
        _ = self.sensor?.resetUnit()
    }

    public func glViewWillBeginDragging(_ glView: IRGLView?) {
        self.sensor?.stopMotionDetection()
    }

    public func glViewDidEndDragging(_ glView: IRGLView?, willDecelerate decelerate: Bool) {
        if !decelerate {
            _ = self.sensor?.resetUnit()
        }
    }

    public func glViewDidEndDecelerating(_ glView: IRGLView?) {

    }

    public func glViewDidScroll(toBounds glView: IRGLView?) {
    }
}
