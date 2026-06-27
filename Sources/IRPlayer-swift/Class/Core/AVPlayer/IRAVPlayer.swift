//
//  IRAVPlayer.swift
//  IRPlayer-swift
//
//  Created by irons on 2024/3/30.
//

import AVFoundation
import UIKit

private final class IRAVPlayerDisplayLinkProxy {
    weak var player: IRAVPlayer?

    init(player: IRAVPlayer) {
        self.player = player
    }

    @objc func displayLinkCallback(_ sender: CADisplayLink) {
        guard let player else {
            sender.invalidate()
            return
        }
        player.displayLinkCallback(sender)
    }
}

class IRAVPlayer: NSObject {

    static let pixelBufferRequestInterval: CGFloat = 0.03
    static let avMediaSelectionOptionTrackIDKey = "MediaSelectionOptionsPersistentID"
    static let AVAssetLoadKeys: [String] = ["tracks", "playable"]

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

    weak var abstractPlayer: IRPlayerImp?

    var seeking = false

    var playBackTimeObserver: Any?
    var avPlayer: AVPlayer?
    var avPlayerItem: AVPlayerItem?
    private var avPlayerItemObserversAdded = false
    var avAsset: AVURLAsset?
    var avOutput: AVPlayerItemVideoOutput?
    var readyToPlayTime: TimeInterval = 0

    var needPlay = false // seek and buffering use
    var autoNeedPlay = false // background use
    var hasPixelBuffer = false

    var displayLink: CADisplayLink?
    private var displayLinkProxy: IRAVPlayerDisplayLinkProxy?

    var videoEnable = false
    var audioEnable = false

    var videoTrack: IRPlayerTrack?
    var audioTrack: IRPlayerTrack?

    var videoTracks: [IRPlayerTrack] = []
    var audioTracks: [IRPlayerTrack] = []

    var state: IRPlayerState = .none {
        didSet {
            if state != oldValue,
               let abstractPlayer = abstractPlayer {
                if state != .failed {
                    abstractPlayer.error = nil
                }
                IRPlayerNotification.postPlayer(abstractPlayer, statePrevious: oldValue, current: state)
            }
        }
    }

    var playableTime: TimeInterval = 0 {
        didSet {
            if playableTime != oldValue,
               let abstractPlayer = abstractPlayer {
                let duration = self.duration
                IRPlayerNotification.postPlayer(abstractPlayer, playablePercent: IRPlayerNotificationPayload.timePercent(current: playableTime, total: duration), current: playableTime as NSNumber, total: duration as NSNumber)
            }
        }
    }

    init(abstractPlayer: IRPlayerImp) {
        self.abstractPlayer = abstractPlayer
        super.init()
//        self.abstractPlayer.displayView?.avplayer = self
        abstractPlayer.displayView?.irPixelFormat = .NV12_IRPixelFormat

        setupDisplayLink()
    }

    deinit {
        displayLink?.invalidate()
//        IRPlayerLog("IRAVPlayer release")
        NotificationCenter.default.removeObserver(self)
        replaceEmpty()
        cleanAVPlayer()
    }
}

extension IRAVPlayer {
    static func itemStatusDecision(status: AVPlayerItem.Status, currentState: IRPlayerState) -> ItemStatusDecision {
        return IRAVPlayerPlaybackPolicy.itemStatusDecision(status: status, currentState: currentState)
    }

    static func nextStateAfterPlay(from state: IRPlayerState) -> IRPlayerState? {
        return IRAVPlayerPlaybackPolicy.nextStateAfterPlay(from: state)
    }

    static func nextStateAfterPause(from state: IRPlayerState) -> IRPlayerState? {
        return IRAVPlayerPlaybackPolicy.nextStateAfterPause(from: state)
    }

    static func shouldRetryPlayAfterDelay(for state: IRPlayerState) -> Bool {
        return IRAVPlayerPlaybackPolicy.shouldRetryPlayAfterDelay(for: state)
    }

    static func isActivePlaybackState(_ state: IRPlayerState) -> Bool {
        return IRAVPlayerPlaybackPolicy.isActivePlaybackState(state)
    }
}

extension IRAVPlayer {

    func play() {
        if state == .failed || state == .finished {
            replaceEmpty()
        }

        tryReplaceVideo()
        guard let avPlayer = avPlayer else { return }

        if let nextState = Self.nextStateAfterPlay(from: state) {
            state = nextState
        }

        avPlayer.play()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let self = self else { return }
            if Self.shouldRetryPlayAfterDelay(for: self.state) {
                self.avPlayer?.play()
            }
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
        if autoNeedPlay {
            play()
            autoNeedPlay = false
        }
    }

    func setPlayIfNeeded() {
        if Self.isActivePlaybackState(state) {
            guard let avPlayer = avPlayer else { return }
            state = .buffering
            needPlay = true
            avPlayer.pause()
        }
    }

    func cancelPlayIfNeeded() {
        needPlay = false
    }

    func playIfNeeded() {
        if needPlay {
            guard let avPlayer = avPlayer else { return }
            state = .playing
            avPlayer.play()
            needPlay = false
        }
    }

    func pause() {
        guard let nextState = Self.nextStateAfterPause(from: state) else { return }
        guard let avPlayer = avPlayer else { return }
        state = nextState
        cancelPlayIfNeeded()
        avPlayer.pause()
    }

    func seek(to time: TimeInterval, completionHandler: ((Bool) -> Void)? = nil) {
        guard let seekTime = Self.seekTime(for: time),
              let avPlayerItem = avPlayerItem,
              avPlayerItem.status == .readyToPlay else { return }

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.setPlayIfNeeded()
            self.seeking = true
            avPlayerItem.seek(to: seekTime) { finished in
                DispatchQueue.main.async {
                    self.completeSeek(finished: finished, completionHandler: completionHandler)
                }
            }
        }
    }

    func completeSeek(finished: Bool, completionHandler: ((Bool) -> Void)? = nil) {
        seeking = false
        playIfNeeded()
        completionHandler?(finished)
    }

    static func seekTime(for time: TimeInterval) -> CMTime? {
        return IRAVPlayerTimePolicy.seekTime(for: time)
    }

    static func finiteSeconds(from time: CMTime) -> TimeInterval {
        return IRAVPlayerTimePolicy.finiteSeconds(from: time)
    }

    static func playableEndTime(start: TimeInterval, duration: TimeInterval, totalDuration: TimeInterval) -> TimeInterval {
        return IRAVPlayerTimePolicy.playableEndTime(
            start: start,
            duration: duration,
            totalDuration: totalDuration
        )
    }

    func stop() {
        replaceEmpty()
    }

    var progress: TimeInterval {
        guard let avPlayerItem = avPlayerItem else { return 0 }
        return Self.finiteSeconds(from: avPlayerItem.currentTime())
    }

    var duration: TimeInterval {
        guard let avPlayerItem = avPlayerItem else { return 0 }
        return Self.finiteSeconds(from: avPlayerItem.duration)
    }

    var bitrate: TimeInterval {
        return 0
    }

}

extension IRAVPlayer {

    func reloadVolume() {
        guard let avPlayer = avPlayer,
              let abstractPlayer = abstractPlayer else { return }
        avPlayer.volume = IRPlayerVolume.normalizedFloat(from: abstractPlayer.volume)
    }

    func reloadPlayableTime() {
        guard let avPlayerItem = avPlayerItem, avPlayerItem.status == .readyToPlay,
              let range = avPlayerItem.loadedTimeRanges.first?.timeRangeValue else {
            playableTime = 0
            return
        }

        let start = Self.finiteSeconds(from: range.start)
        let duration = Self.finiteSeconds(from: range.duration)
        playableTime = Self.playableEndTime(start: start, duration: duration, totalDuration: self.duration)
    }

    var presentationSize: CGSize {
        return avPlayerItem?.presentationSize ?? CGSize.zero
    }

    func snapshotAtCurrentTime() -> IRPLFImage? {
        guard let avAsset = avAsset,
              let avPlayerItem = avPlayerItem,
              abstractPlayer?.videoType == .normal else { return nil }

        let imageGenerator = AVAssetImageGenerator(asset: avAsset)
        imageGenerator.appliesPreferredTrackTransform = true
        imageGenerator.requestedTimeToleranceBefore = .zero
        imageGenerator.requestedTimeToleranceAfter = .zero

        do {
            let cgImage = try imageGenerator.copyCGImage(at: avPlayerItem.currentTime(), actualTime: nil)
            return IRPLFImage(cgImage: cgImage)
        } catch {
            return nil
        }
    }

    func pixelBufferAtCurrentTime() -> CVPixelBuffer? {
        guard !seeking else { return nil }
        guard let avPlayerItem = avPlayerItem,
              let avOutput = avOutput,
              avOutput.hasNewPixelBuffer(forItemTime: avPlayerItem.currentTime()) else {
            return nil
        }

        guard let pixelBuffer = avOutput.copyPixelBuffer(forItemTime: avPlayerItem.currentTime(), itemTimeForDisplay: nil) else {
            trySetupOutput()
            return nil
        }

        hasPixelBuffer = true
        return pixelBuffer
    }
}


// MARK: CADisplayLink
extension IRAVPlayer {

    func setupDisplayLink() {
        let proxy = IRAVPlayerDisplayLinkProxy(player: self)
        self.displayLinkProxy = proxy
        self.displayLink = CADisplayLink(target: proxy, selector: #selector(IRAVPlayerDisplayLinkProxy.displayLinkCallback(_:)))
        self.displayLink?.add(to: .current, forMode: .default)
        self.displayLink?.isPaused = false
    }

    @objc func displayLinkCallback(_ sender: CADisplayLink) {
        guard let pixelBuffer = pixelBufferAtCurrentTime() else { return }

        let videoFrame = IRFFCVYUVVideoFrame(pixelBuffer: pixelBuffer)

        videoFrame.position = -1
        videoFrame.duration = -1
        abstractPlayer?.displayView?.render(videoFrame)
    }
}

extension IRAVPlayer {

    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey: Any]?, context: UnsafeMutableRawPointer?) {
        guard let item = object as? AVPlayerItem, item == avPlayerItem else { return }

        switch keyPath {
        case "status":
            switch Self.itemStatusDecision(status: item.status, currentState: state) {
            case .buffer:
                state = .buffering

            case .markReady:
                setupTrackInfo()
                readyToPlayTime = Date().timeIntervalSince1970
                state = .readyToPlay

            case .playIfNeeded:
                setupTrackInfo()
                readyToPlayTime = Date().timeIntervalSince1970
                playIfNeeded()

            case .fail:
                failPlayback(with: playbackErrorInfo())

            case .failUnknown:
                let errorInfo = IRError()
                errorInfo.error = NSError(domain: "AVPlayer item status unknown", code: -1, userInfo: [
                    NSLocalizedDescriptionKey: "AVPlayerItem reported an unknown status."
                ])
                failPlayback(with: errorInfo)

            case .ignore:
                break
            }

        case "playbackBufferEmpty":
            if item.isPlaybackBufferEmpty {
                setPlayIfNeeded()
            }

        case "loadedTimeRanges":
            reloadPlayableTime()
            guard let abstractPlayer = abstractPlayer else { return }
            let interval = playableTime - progress
            let residue = duration - progress
            if interval > abstractPlayer.playableBufferInterval {
                playIfNeeded()
            } else if interval < 0.3 && residue > 1.5 {
                setPlayIfNeeded()
            }

        default:
            break
        }
    }

    @objc func avplayerItemDidPlayToEnd(_ notification: Notification) {
        state = .finished
    }

    func avAssetPrepareFailed(error: Error?) {
        readyToPlayTime = 0
        let errorInfo = IRError()
        if let error = error {
            errorInfo.error = error as NSError
        }
        failPlayback(with: errorInfo)
    }

    private func playbackErrorInfo() -> IRError {
        readyToPlayTime = 0
        return Self.playbackErrorInfo(playerItem: avPlayerItem, player: avPlayer)
    }

    static func playbackErrorInfo(playerItem: AVPlayerItem?, player: AVPlayer?) -> IRError {
        return IRAVPlayerErrorPolicy.playbackErrorInfo(playerItem: playerItem, player: player)
    }

    private func failPlayback(with errorInfo: IRError) {
        guard let abstractPlayer = abstractPlayer else {
            state = .failed
            return
        }
        abstractPlayer.error = errorInfo
        state = .failed
        IRPlayerNotification.postPlayer(abstractPlayer, error: errorInfo)
    }
}

extension IRAVPlayer {

    func tryReplaceVideo() {
        if avPlayerItem == nil {
            replaceVideo()
        }
    }

    func replaceVideo() {
        replaceEmpty()
        guard let abstractPlayer = abstractPlayer,
              let contentURL = abstractPlayer.contentURL else { return }

        avAsset = AVURLAsset(url: contentURL as URL)
        avAsset?.resourceLoader.setDelegate(self, queue: DispatchQueue(label: "IRAVPlayer.AssetResourceLoaderDelegateQueue"))
        switch abstractPlayer.videoType {
        case .normal:
            setupAVPlayerItem(autoLoadedAsset: true)
            setupAVPlayer()
            abstractPlayer.displayView?.rendererType = .AVPlayerLayer
        case .vr:
            setupAVPlayerItem(autoLoadedAsset: false)
            setupAVPlayer()
            abstractPlayer.displayView?.rendererType = .AVPlayerPixelBufferVR
            avAsset?.loadValuesAsynchronously(forKeys: Self.AVAssetLoadKeys) { [weak self] in
                DispatchQueue.main.async {
                    guard let self = self else { return }
                    var keyStatuses: [AVKeyValueStatus] = []
                    var failureError: NSError?
                    for loadKey in Self.AVAssetLoadKeys {
                        var error: NSError? = nil
                        let keyStatus = self.avAsset?.statusOfValue(forKey: loadKey, error: &error)
                        if let keyStatus {
                            keyStatuses.append(keyStatus)
                        }
                        if keyStatus == .failed, failureError == nil {
                            failureError = error
                        }
                    }
                    let trackStatus = self.avAsset?.statusOfValue(forKey: "tracks", error: nil)
                    switch Self.avAssetLoadDecision(keyStatuses: keyStatuses, trackStatus: trackStatus) {
                    case .fail:
                        self.avAssetPrepareFailed(error: failureError)
                    case .setupOutput:
                        self.setupOutput()
                    case .ignore:
                        break
                    }
                }
            }
        case .fisheye, .pano:
            // Handle fisheye or pano video type if needed
            break
        case .custom:
            break
        }
    }

}

extension IRAVPlayer: AVAssetResourceLoaderDelegate {

    func resourceLoader(_ resourceLoader: AVAssetResourceLoader, shouldWaitForLoadingOfRequestedResource loadingRequest: AVAssetResourceLoadingRequest) -> Bool {
        guard let redirectRequest = Self.resourceLoaderRedirectRequest(
            for: loadingRequest.request,
            headers: abstractPlayer?.contentHeaders
        ) else {
            return false
        }

        loadingRequest.redirect = redirectRequest
        loadingRequest.finishLoading() // This signals AVFoundation to use the redirect request

        return true
    }

}

extension IRAVPlayer {

    static func avAssetLoadDecision(keyStatuses: [AVKeyValueStatus], trackStatus: AVKeyValueStatus?) -> AVAssetLoadDecision {
        return IRAVPlayerAssetLoadPolicy.decision(keyStatuses: keyStatuses, trackStatus: trackStatus)
    }

    static func resourceLoaderRedirectRequest(for request: URLRequest, headers: [String: String]?) -> URLRequest? {
        return IRAVPlayerResourceLoaderPolicy.redirectRequest(for: request, headers: headers)
    }

    func setupAVPlayer() {
        avPlayer = AVPlayer(playerItem: avPlayerItem)
        // iOS 10+ specific feature, uncomment if needed and ensure you handle different iOS versions if necessary
        // if #available(iOS 10.0, *) {
        //     avPlayer?.automaticallyWaitsToMinimizeStalling = false
        // }

        playBackTimeObserver = avPlayer?.addPeriodicTimeObserver(forInterval: CMTimeMake(value: 1, timescale: 1), queue: .main) { [weak self] time in
            guard let strongSelf = self else { return }
            if strongSelf.state == .playing {
                guard let abstractPlayer = strongSelf.abstractPlayer else { return }
                let current = Self.finiteSeconds(from: time)
                let duration = strongSelf.duration
                IRPlayerNotification.postPlayer(abstractPlayer, progressPercent: IRPlayerNotificationPayload.timePercent(current: current, total: duration), current: current as NSNumber, total: duration as NSNumber)
            }
        }
        reloadVolume()
    }

    func cleanAVPlayer() {
        avPlayer?.pause()
        avPlayer?.cancelPendingPrerolls()
        avPlayer?.replaceCurrentItem(with: nil)

        if let observer = playBackTimeObserver {
            avPlayer?.removeTimeObserver(observer)
            playBackTimeObserver = nil
        }
        avPlayer = nil
    }

    func setupAVPlayerItem(autoLoadedAsset: Bool) {
        guard let avAsset = avAsset else {
            avPlayerItem = nil
            return
        }

        if autoLoadedAsset {
            avPlayerItem = AVPlayerItem(asset: avAsset, automaticallyLoadedAssetKeys: Self.AVAssetLoadKeys)
        } else {
            avPlayerItem = AVPlayerItem(asset: avAsset)
        }

        avPlayerItem?.addObserver(self, forKeyPath: "status", options: [], context: nil)
        avPlayerItem?.addObserver(self, forKeyPath: "playbackBufferEmpty", options: [.new], context: nil)
        avPlayerItem?.addObserver(self, forKeyPath: "loadedTimeRanges", options: [.new], context: nil)
        avPlayerItemObserversAdded = true
        NotificationCenter.default.addObserver(self, selector: #selector(avplayerItemDidPlayToEnd(_:)), name: .AVPlayerItemDidPlayToEndTime, object: avPlayerItem)

        setupOutput()
    }

    func cleanAVPlayerItem() {
        avPlayerItem?.cancelPendingSeeks()
        if avPlayerItemObserversAdded {
            avPlayerItem?.removeObserver(self, forKeyPath: "status")
            avPlayerItem?.removeObserver(self, forKeyPath: "playbackBufferEmpty")
            avPlayerItem?.removeObserver(self, forKeyPath: "loadedTimeRanges")
            avPlayerItemObserversAdded = false
        }
        avPlayerItem?.outputs.forEach { avPlayerItem?.remove($0) }
        NotificationCenter.default.removeObserver(self, name: .AVPlayerItemDidPlayToEndTime, object: avPlayerItem)
        avPlayerItem = nil
    }

    func trySetupOutput() {
        let isReadyToPlay = avPlayerItem?.status == .readyToPlay && readyToPlayTime > 10 && (Date().timeIntervalSince1970 - readyToPlayTime) > 0.3
        if isReadyToPlay {
            setupOutput()
        }
    }

    func setupOutput() {
        cleanOutput()
        guard let avPlayerItem else { return }

        let pixelBufferAttributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
            kCVPixelBufferMetalCompatibilityKey as String: true,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:]
        ]
        avOutput = AVPlayerItemVideoOutput(pixelBufferAttributes: pixelBufferAttributes)
        avOutput?.requestNotificationOfMediaDataChange(withAdvanceInterval: IRAVPlayer.pixelBufferRequestInterval)
        guard let avOutput = avOutput else { return }
        avPlayerItem.add(avOutput)
    }


    func cleanOutput() {
        if let outputs = avPlayerItem?.outputs as? [AVPlayerItemOutput], let avOutput = avOutput {
            if outputs.contains(avOutput) {
                avPlayerItem?.remove(avOutput)
            }
        }
        avOutput = nil
        hasPixelBuffer = false
    }

}

extension IRAVPlayer {

    func replaceEmpty() {
        if let abstractPlayer = abstractPlayer {
            IRPlayerNotification.postPlayer(abstractPlayer, playablePercent: 0, current: 0, total: 0)
            IRPlayerNotification.postPlayer(abstractPlayer, progressPercent: 0, current: 0, total: 0)
        }
        avAsset?.cancelLoading()
        avAsset = nil
        cleanOutput()
        cleanAVPlayerItem()
        cleanAVPlayer()
        cleanTrackInfo()
        state = .none
        needPlay = false
        seeking = false
        playableTime = 0
        readyToPlayTime = 0
        abstractPlayer?.displayView?.cleanEmptyBuffer()
    }

    func setupTrackInfo() {
        guard !videoEnable, !audioEnable, let tracks = avAsset?.tracks else { return }

        var videoTracks: [IRPlayerTrack] = []
        var audioTracks: [IRPlayerTrack] = []

        tracks.forEach { track in
            if track.mediaType == .video {
                videoEnable = true
                videoTracks.append(playerTrack(from: track))
            } else if track.mediaType == .audio {
                audioEnable = true
                audioTracks.append(playerTrack(from: track))
            }
        }

        self.videoTracks = videoTracks
        self.audioTracks = audioTracks

        setupDefaultTrack(for: .visual, from: videoTracks)
        setupDefaultTrack(for: .audible, from: audioTracks)
    }

    private func setupDefaultTrack(for characteristic: AVMediaCharacteristic, from tracks: [IRPlayerTrack]) {
        guard let group = avAsset?.mediaSelectionGroup(forMediaCharacteristic: characteristic) else { return }
        let defaultTrack = Self.defaultTrack(from: tracks, propertyList: group.defaultOption?.propertyList)
        if characteristic == .visual {
            videoTrack = defaultTrack
        } else if characteristic == .audible {
            audioTrack = defaultTrack
        }
    }

    func cleanTrackInfo() {
        videoEnable = false
        videoTrack = nil
        videoTracks = []

        audioEnable = false
        audioTrack = nil
        audioTracks = []
    }

}

extension IRAVPlayer {

    func selectAudioTrack(index audioTrackIndex: Int) {
        guard audioTrack?.index != audioTrackIndex,
              let group = avAsset?.mediaSelectionGroup(forMediaCharacteristic: .audible) else { return }

        if let option = group.options.first(where: { option in
            return Self.mediaSelectionTrackID(from: option.propertyList) == audioTrackIndex
        }) {
            avPlayerItem?.select(option, in: group)
            if let track = audioTracks.first(where: { $0.index == audioTrackIndex }) {
                self.audioTrack = track
            }
        }
    }

    func playerTrack(from track: AVAssetTrack) -> IRPlayerTrack {
        let obj = IRPlayerTrack()
        obj.index = Int(track.trackID)
        obj.name = Self.trackName(languageCode: track.languageCode, trackID: track.trackID)
        return obj
    }

    static func trackName(languageCode: String?, trackID: CMPersistentTrackID) -> String {
        return IRAVPlayerTrackPolicy.trackName(languageCode: languageCode, trackID: trackID)
    }

    static func mediaSelectionTrackID(from propertyList: Any?) -> Int? {
        return IRAVPlayerTrackPolicy.mediaSelectionTrackID(from: propertyList)
    }

    static func defaultTrack(from tracks: [IRPlayerTrack], propertyList: Any?) -> IRPlayerTrack? {
        return IRAVPlayerTrackPolicy.defaultTrack(from: tracks, propertyList: propertyList)
    }

}
