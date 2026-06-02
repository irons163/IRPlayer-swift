//
//  IRPlayerImp.swift
//  IRPlayer-swift
//
//  Created by Phil Chang on 2022/4/11.
//  Copyright © 2022 Phil. All rights reserved.
//

import UIKit
import OSLog

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
        return Float(volume)
    }
}

// MARK: - IRPlayerImp
@objcMembers
public class IRPlayerImp: NSObject {

    public var decoder: IRPlayerDecoder
    public private(set) var contentURL: NSURL?
    public private(set) var contentHeaders: [String: String]?
    private(set) var videoInput: IRFFVideoInput?
    public private(set) var videoType: IRVideoType {
        didSet {
            self.setVideoType(videoType: self.videoType)
        }
    }
    public var error: IRError?

    // preview
    public var displayMode: IRDisplayMode
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
    var backgroundMode: IRPlayerBackgroundMode
    var state: IRPlayerState {
        switch self.decoderType {
        case .avPlayer:
            return self.avPlayer.state
        case .ffmpeg:
            return self.ffPlayer.state
        case .error:
            return .none
        case .none:
            return .none
        }
    }
    var presentationSize: CGSize {
        switch self.decoderType {
        case .avPlayer:
            return self.avPlayer.presentationSize
        case .ffmpeg:
            return self.ffPlayer.presentationSize
        case .error:
            return .zero
        case .none:
            return .zero
        }
    }
    var bitrate: TimeInterval {
        switch self.decoderType {
        case .avPlayer:
            return self.avPlayer.bitrate
        case .ffmpeg:
            return self.ffPlayer.bitrate
        case .error:
            return 0
        case .none:
            return 0
        }
    }
    var progress: TimeInterval {
        switch self.decoderType {
        case .avPlayer:
            return self.avPlayer.progress
        case .ffmpeg:
            return self.ffPlayer.progress
        case .error:
            return 0
        case .none:
            return 0
        }
    }
    public var duration: TimeInterval {
        switch self.decoderType {
        case .avPlayer:
            return self.avPlayer.duration
        case .ffmpeg:
            return self.ffPlayer.duration
        case .error:
            return 0
        case .none:
            return 0
        }
    }
    var playableTime: TimeInterval {
        switch self.decoderType {
        case .avPlayer:
            return self.avPlayer.playableTime
        case .ffmpeg:
            return self.ffPlayer.playableTime
        case .error:
            return 0
        case .none:
            return 0
        }
    }
    public var playableBufferInterval: TimeInterval = 2.0 {
        didSet {
            if self._ffPlayer != nil {
                self.ffPlayer.reloadPlayableBufferInterval()
            }
        }
    }
    var seeking: Bool {
        switch self.decoderType {
        case .avPlayer:
            return self.avPlayer.seeking
        case .ffmpeg:
            return self.ffPlayer.seeking
        case .error:
            return false
        case .none:
            return false
        }
    }
    public var volume: CGFloat = 1 {
        didSet {
            if self._avPlayer != nil {
                self.avPlayer.reloadVolume()
            }
            if self._ffPlayer != nil {
                self.ffPlayer.reloadVolume()
            }
        }
    }

    var displayView: IRGLView?
    private var decoderType: IRDecoderType?
    private var _avPlayer: IRAVPlayer?
    private var avPlayer: IRAVPlayer {
        let player = Self.makeAVPlayerIfNeeded(self._avPlayer, abstractPlayer: self)
        self._avPlayer = player
        return player
    }
    private var _ffPlayer: IRFFPlayer?
    private var ffPlayer: IRFFPlayer {
        let player = Self.makeFFPlayerIfNeeded(self._ffPlayer, abstractPlayer: self)
        self._ffPlayer = player
        return player
    }
    private var gestureControl: IRGLGestureController?
    private var sensor: IRSensor?
    private var scrollController: IRSmoothScrollController?

    private var needAutoPlay: Bool?
    private var lastForegroundTimeInterval: TimeInterval?
    var manager: IRAudioManager?

    override init() {
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
#if IRPLATFORM_TARGET_OS_IPHONE_OR_TV
        self.setupNotification()
#endif
        self.setupViews()
    }

    public class func player() -> IRPlayerImp {
        return IRPlayerImp()
    }

    static func makeAVPlayerIfNeeded(_ player: IRAVPlayer?, abstractPlayer: IRPlayerImp) -> IRAVPlayer {
        return player ?? IRAVPlayer(abstractPlayer: abstractPlayer)
    }

    static func makeFFPlayerIfNeeded(_ player: IRFFPlayer?, abstractPlayer: IRPlayerImp) -> IRFFPlayer {
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
        return IRGLView()
    }

    func snapshot() -> IRPLFImage? {
        //    return self.displayView.snapshot;
        return nil
    }

    public func play() {
#if IRPLATFORM_TARGET_OS_IPHONE_OR_TV
        UIApplication.shared.isIdleTimerDisabled = true
#endif
        switch IRPlayerLifecyclePolicy.commandTarget(for: self.decoderType) {
        case .avPlayer:
            self.avPlayer.play()
        case .ffmpeg:
            self.ffPlayer.play()
        case .none:
            break
        }
    }

    public func pause() {
#if IRPLATFORM_TARGET_OS_IPHONE_OR_TV
        UIApplication.shared.isIdleTimerDisabled = false
#endif
        switch IRPlayerLifecyclePolicy.commandTarget(for: self.decoderType) {
        case .avPlayer:
            self.avPlayer.pause()
        case .ffmpeg:
            self.ffPlayer.pause()
        case .none:
            break
        }
    }

    public func seekToTime(time: TimeInterval, completeHandler: ((Bool) -> Void)? = nil) {
        switch self.decoderType {
        case .avPlayer:
            self.avPlayer.seek(to: time, completionHandler: completeHandler)
        case .ffmpeg:
            self.ffPlayer.seek(to: time, completeHandler: completeHandler)
        default:
            break
        }
    }

    func seekToTime(time: TimeInterval) {
//        self.seekToTime(time: time)
    }

    public func updateGraphicsViewFrame(frame: CGRect) {
        self.displayView?.update(frame: frame)
    }

    private func setVideoType(videoType: IRVideoType) {
        switch videoType {
        case .normal:
            self.displayView?.setRenderModes(IRGLRenderModeFactory.createNormalModes(with: nil))
            self.gestureControl?.currentMode = self.displayView?.getCurrentRenderMode()
        case .vr:
            guard let displayView = self.displayView else { return }
            if self.displayMode == .normal {
                let mode = IRGLRenderModeFactory.createVRMode(with: nil)
                mode.defaultScale = 1.5
                mode.aspect = 16.0 / 9.0
                self.displayView?.setRenderModes([mode])
            } else if self.displayMode == .box {
                let mode = IRGLRenderModeFactory.createDistortionMode(with: nil)
                mode.defaultScale = 1.5
                mode.aspect = 16.0 / 9.0
                self.displayView?.setRenderModes([mode])
                self.gestureControl?.removeGesture(to: displayView)
                self.sensor = IRSensor()
                self.sensor?.targetView = displayView
                self.sensor?.smoothScroll = self.gestureControl?.smoothScroll
                _ = self.sensor?.resetUnit()
            }
            self.viewGravityMode = .resizeAspect
            self.gestureControl?.currentMode = self.displayView?.getCurrentRenderMode()
        case .fisheye:
            let mode = IRGLRenderModeFactory.createFisheyeMode(with: IRFisheyeParameter(width: 0, height: 0, up: false, rx: 0, ry: 0, cx: 0, cy: 0, latmax: 80))
            mode.defaultScale = 1.5
            mode.aspect = 16.0 / 9.0
            self.displayView?.setRenderModes([mode])
            self.viewGravityMode = .resizeAspect
            self.gestureControl?.currentMode = self.displayView?.getCurrentRenderMode()
        case .pano:
            let mode = IRGLRenderModeFactory.createPanoramaMode(with: nil)
            self.displayView?.setRenderModes([mode])
            self.gestureControl?.currentMode = self.displayView?.getCurrentRenderMode()
        case .custom:
            self.gestureControl?.currentMode = self.displayView?.getCurrentRenderMode()
        }
    }

    public func setRequestHeaderFields(_ fields: [String: String]?) {
        self.contentHeaders = fields
    }
}

public extension IRPlayerImp {

    func replaceEmpty() {
        self.replaceVideoWithURL(contentURL: nil)
    }

    func replaceVideoWithURL(contentURL: NSURL?,
                             videoType: IRVideoType = .normal,
                             videoInput: IRFFVideoInput? = nil) {
        self.error = nil
        self.contentURL = contentURL
        self.videoInput = videoInput
        if let videoInput = self.videoInput {
            videoInput.videoOutput = self.displayView
        }
        self.decoderType = self.decoder.decoderTypeForContentURL(contentURL: self.contentURL)
        self.videoType = videoType

        let replacementPlan = IRPlayerLifecyclePolicy.replacementPlan(
            for: self.decoderType,
            hasAVPlayer: self._avPlayer != nil,
            hasFFPlayer: self._ffPlayer != nil
        )

        if replacementPlan.stopAVPlayer { self.avPlayer.stop() }
        if replacementPlan.stopFFPlayer { self.ffPlayer.stop() }

        switch replacementPlan.replaceTarget {
        case .avPlayer:
            self.avPlayer.replaceVideo()
        case .ffmpeg:
            self.ffPlayer.replaceVideo()
            if self.videoInput?.outputType == .decoder {
                self.videoInput?.videoOutput = self.ffPlayer.decoder
            }
        case .none:
            break
        }
    }
}

extension IRPlayerImp {

    func cleanPlayer() {
        if _avPlayer != nil {
            self.avPlayer.stop()
            self._avPlayer = nil
        }
        if _ffPlayer != nil {
            self.ffPlayer.stop()
            self._ffPlayer = nil
        }
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

        self.needAutoPlay = false
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
            let timeSinceForeground = NSDate().timeIntervalSince1970 - (self.lastForegroundTimeInterval ?? 0)
            switch IRPlayerLifecyclePolicy.audioInterruptionAction(type: type, state: self.state, timeSinceForeground: timeSinceForeground) {
            case .pause:
                self.pause()
            case .none:
                break
            }
        }, routeChange: { [weak self] (handlerTarget, audioManager, reason) in
            guard let self = self else { return }
            switch IRPlayerLifecyclePolicy.audioRouteChangeAction(reason: reason, state: self.state) {
            case .pause:
                self.pause()
            case .none:
                break
            }
        })
    }

    func applicationDidEnterBackground(_ notification: NSNotification) {
        switch IRPlayerLifecyclePolicy.backgroundAction(mode: self.backgroundMode, state: self.state) {
        case .pauseAndRememberAutoPlay:
            self.needAutoPlay = true
            self.pause()
        case .none:
            break
        }
    }

    func applicationWillEnterForeground(_ notification: NSNotification) {
        switch IRPlayerLifecyclePolicy.foregroundAction(mode: self.backgroundMode, state: self.state, needAutoPlay: self.needAutoPlay) {
        case .playAndClearAutoPlay:
            self.needAutoPlay = false
            self.play()
            self.lastForegroundTimeInterval = Date().timeIntervalSince1970
        case .none:
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

// ******************************* MARK: - Logger Delegate

/// Severity levels that mirror OSLog's level hierarchy.
@objc public enum IRPlayerLogLevel: Int, Equatable, Hashable, Sendable {
    case debug
    case info
    case warning
    case error
}

/// Implement this protocol to intercept IRPlayer log messages and forward them
/// to your own logging system. When a delegate is set it receives **all** log
/// messages instead of (not in addition to) the built-in OSLog output.
public protocol IRPlayerLoggerDelegate: AnyObject {
    func irPlayer(didLog message: String, level: IRPlayerLogLevel, category: String)
}

// ******************************* MARK: - Constants

public extension IRPlayerImp { enum Logger {} }
public extension IRPlayerImp.Logger {
    static var subsystem = Bundle.main.bundleIdentifier ?? "IRPlayerImp"

    /// Set this delegate to receive all IRPlayer log messages in your own
    /// logging system. Setting it to `nil` (the default) restores OSLog output.
    nonisolated(unsafe) static weak var delegate: (any IRPlayerLoggerDelegate)?

    static var libraryLogger = IRPlayerLogger(subsystem: subsystem, category: "library")
}

// ******************************* MARK: - IRPlayerLogger

/// A thin logger wrapper that forwards messages to `IRPlayerImp.Logger.delegate`
/// when one is set, and falls back to OSLog otherwise.
/// It intentionally mirrors the `debug / info / warning / error` API of
/// `OSLog.Logger` so all existing call sites remain unchanged.
public struct IRPlayerLogger {
    private let osLogger: Logger  // OSLog.Logger, available via `import OSLog`
    private let category: String

    public init(subsystem: String, category: String) {
        self.osLogger = Logger(subsystem: subsystem, category: category)
        self.category = category
    }

    public func debug(_ message: @autoclosure () -> String) {
        let msg = message()
        if let delegate = IRPlayerImp.Logger.delegate {
            delegate.irPlayer(didLog: msg, level: .debug, category: category)
        } else {
            osLogger.debug("\(msg)")
        }
    }

    public func info(_ message: @autoclosure () -> String) {
        let msg = message()
        if let delegate = IRPlayerImp.Logger.delegate {
            delegate.irPlayer(didLog: msg, level: .info, category: category)
        } else {
            osLogger.info("\(msg)")
        }
    }

    public func warning(_ message: @autoclosure () -> String) {
        let msg = message()
        if let delegate = IRPlayerImp.Logger.delegate {
            delegate.irPlayer(didLog: msg, level: .warning, category: category)
        } else {
            osLogger.warning("\(msg)")
        }
    }

    public func error(_ message: @autoclosure () -> String) {
        let msg = message()
        if let delegate = IRPlayerImp.Logger.delegate {
            delegate.irPlayer(didLog: msg, level: .error, category: category)
        } else {
            osLogger.error("\(msg)")
        }
    }
}
