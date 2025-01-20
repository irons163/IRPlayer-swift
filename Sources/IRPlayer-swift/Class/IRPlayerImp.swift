//
//  IRPlayerImp.swift
//  IRPlayer-swift
//
//  Created by Phil Chang on 2022/4/11.
//  Copyright © 2022 Phil. All rights reserved.
//

import UIKit

// video type
@objc public enum IRVideoType: Int {
    case normal // normal
    @objc(IRVideoTypeVR)
    case vr // virtual reality
    case fisheye
    case pano
    case custom
}

// player state
@objc public enum IRPlayerState: Int {
    case none // normal
    case buffering // virtual reality
    case readyToPlay
    case playing
    case suspend
    case finished
    case failed
}

// display mode
public enum IRDisplayMode {
    case normal // normal
    case box // virtual reality
}

// video content mode
@objc public enum IRGravityMode: Int {
    case resize
    case resizeAspect
    case resizeAspectFill
}

// background mode
enum IRPlayerBackgroundMode {
    case nothing
    case autoPlayAndPause
    case continuing
}

// Mark: - IRPlayerImp
@objcMembers
public class IRPlayerImp: NSObject {

    public var decoder: IRPlayerDecoder
    public private(set) var contentURL: NSURL?
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
    var viewAnimationHidden: Bool // default is YES
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
                self.ffPlayer.reloadVolume()
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
        if self._avPlayer == nil {
            self._avPlayer = IRAVPlayer(abstractPlayer: self)
        }
        return self._avPlayer!
    }
    private var _ffPlayer: IRFFPlayer?
    private var ffPlayer: IRFFPlayer {
        if self._ffPlayer == nil {
            self._ffPlayer = IRFFPlayer.init(abstractPlayer: self)
        }
        return self._ffPlayer!
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
        self.volume = 1;
        super.init()
#if IRPLATFORM_TARGET_OS_IPHONE_OR_TV
        self.setupNotification()
#endif
        self.setupViews()
    }

    public class func player() -> IRPlayerImp {
        return IRPlayerImp()
    }

    deinit {
        print("IRPlayer release")
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
        switch self.decoderType {
        case .avPlayer:
            self.avPlayer.play()
        case .ffmpeg:
            self.ffPlayer.play()
        default:
            break
        }
    }

    public func pause() {
#if IRPLATFORM_TARGET_OS_IPHONE_OR_TV
        UIApplication.shared.isIdleTimerDisabled = false
#endif
        switch self.decoderType {
        case .avPlayer:
            self.avPlayer.pause()
        case .ffmpeg:
            self.ffPlayer.pause()
        default:
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
            if (self.displayMode == .normal) {
                let mode = IRGLRenderModeFactory.createVRMode(with: nil)
                mode.program?.setDefaultScale(1.5)
                mode.aspect = 16.0 / 9.0
                self.displayView?.setRenderModes([mode])
            } else if self.displayMode == .normal {
                let mode = IRGLRenderModeFactory.createDistortionMode(with: nil)
                mode.defaultScale = 1.5
                mode.aspect = 16.0 / 9.0
                self.displayView?.setRenderModes([mode])
                self.gestureControl?.removeGesture(to: displayView)
                self.sensor = IRSensor()
                self.sensor?.targetView = displayView
                self.sensor?.smoothScroll = self.gestureControl?.smoothScroll
                self.sensor?.resetUnit()
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
}

public extension IRPlayerImp {

    func replaceEmpty() {
        self.replaceVideoWithURL(contentURL: nil)
    }

    func replaceVideoWithURL(contentURL: NSURL?,
                             videoType: IRVideoType = .normal,
                             videoInput: IRFFVideoInput? = nil) {
        self.error = nil;
        self.contentURL = contentURL
        self.videoInput = videoInput
        if let videoInput = self.videoInput {
            videoInput.videoOutput = self.displayView
        }
        self.decoderType = self.decoder.decoderTypeForContentURL(contentURL: self.contentURL)
        self.videoType = videoType

        switch self.decoderType {
        case .avPlayer:
            if self._ffPlayer != nil {
                self.ffPlayer.stop()
            }
            self.avPlayer.replaceVideo()
        case .ffmpeg:
            if self._avPlayer != nil {
                self.avPlayer.stop()
            }
            self.ffPlayer.replaceVideo()
            if self.videoInput?.outputType == .decoder {
                self.videoInput?.videoOutput = self.ffPlayer.decoder
            }
        case .error, .none:
            if self._avPlayer != nil {
                self.avPlayer.stop()
            }
            if self._ffPlayer != nil {
                self.ffPlayer.stop()
            }
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
            self.gestureControl = nil;
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
            guard type == .begin else { return }
            switch self?.state {
            case .playing, .buffering:
                // fix : maybe receive interruption notification when enter foreground.
                let timeInterval = NSDate().timeIntervalSince1970
                guard timeInterval - (self?.lastForegroundTimeInterval ?? 0) > 1.5 else { break }
                self?.pause()
            default:
                break
            }
        }, routeChange: { [weak self] (handlerTarget, audioManager, reason) in
            guard reason == .oldDeviceUnavailable else { return }
            switch self?.state {
            case .playing, .buffering:
                self?.pause()
            default:
                break
            }
        })
    }

    func applicationDidEnterBackground(_ notification: NSNotification) {
        switch self.backgroundMode {
        case .nothing, .continuing:
            break
        case .autoPlayAndPause:
            switch self.state {
            case .playing, .buffering:
                self.needAutoPlay = true
                self.pause()
            default:
                break
            }
        }
    }

    func applicationWillEnterForeground(_ notification: NSNotification) {
        switch self.backgroundMode {
        case .nothing, .continuing:
            break
        case .autoPlayAndPause:
            switch self.state {
            case .suspend:
                guard self.needAutoPlay == true else { break }
                self.needAutoPlay = false
                self.play()
                self.lastForegroundTimeInterval = NSDate().timeIntervalSince1970
            default:
                break
            }
        }
    }
}
#endif

// Mark: - IRPlayer Action Category
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

// Mark: - UIScrollViewDelegate
extension IRPlayerImp: IRGLViewDelegate {

    public func glViewWillBeginZooming(_ glView: IRGLView?) {
        self.sensor?.stopMotionDetection()
    }

    public func glViewDidEndZooming(_ glView: IRGLView?, atScale scale: CGFloat) {
        self.sensor?.resetUnit()
    }

    public func glViewWillBeginDragging(_ glView: IRGLView?) {
        self.sensor?.stopMotionDetection()
    }

    public func glViewDidEndDragging(_ glView: IRGLView?, willDecelerate decelerate: Bool) {
        if !decelerate {
            self.sensor?.resetUnit()
        }
    }

    public func glViewDidEndDecelerating(_ glView: IRGLView?) {

    }

    public func glViewDidScroll(toBounds glView: IRGLView?) {
        print("scroll to bounds")
    }
}
