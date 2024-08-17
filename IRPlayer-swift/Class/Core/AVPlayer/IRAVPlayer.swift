//
//  IRAVPlayer.swift
//  IRPlayer-swift
//
//  Created by irons on 2024/3/30.
//

import AVFoundation
import UIKit

class IRAVPlayer: NSObject {

    static let pixelBufferRequestInterval: CGFloat = 0.03
    static let avMediaSelectionOptionTrackIDKey = "MediaSelectionOptionsPersistentID"
    static let AVAssetLoadKeys: [String] = ["tracks", "playable"]

    weak var abstractPlayer: IRPlayerImp!

    var seeking = false

    var playBackTimeObserver: Any?
    var avPlayer: AVPlayer!
    var avPlayerItem: AVPlayerItem!
    var avAsset: AVURLAsset?
    var avOutput: AVPlayerItemVideoOutput?
    var readyToPlayTime: TimeInterval = 0

    var needPlay = false // seek and buffering use
    var autoNeedPlay = false // background use
    var hasPixelBuffer = false

    var displayLink: CADisplayLink?

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
                IRPlayerNotification.postPlayer(abstractPlayer, playablePercent: playableTime/duration as NSNumber, current: playableTime as NSNumber, total: duration as NSNumber)
            }
        }
    }

    init(abstractPlayer: IRPlayerImp) {
        self.abstractPlayer = abstractPlayer
        super.init()
//        self.abstractPlayer.displayView?.avplayer = self
        self.abstractPlayer.displayView?.irPixelFormat = .NV12_IRPixelFormat

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

    func play() {
        if state == .failed || state == .finished {
            replaceEmpty()
        }

        tryReplaceVideo()

        switch state {
        case .none:
            state = .buffering
        case .suspend, .readyToPlay:
            state = .playing
        default:
            break
        }

        avPlayer.play()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let self = self else { return }
            switch self.state {
            case .buffering, .playing, .readyToPlay:
                self.avPlayer.play()
            default:
                break
            }
        }
    }

    func setAutoPlayIfNeed() {
        if state == .playing || state == .buffering {
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
        if state == .playing || state == .buffering {
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
            state = .playing
            avPlayer.play()
            needPlay = false
        }
    }

    func pause() {
        guard state != .failed else { return }
        state = .suspend
        cancelPlayIfNeeded()
        avPlayer.pause()
    }

    func seek(to time: TimeInterval, completionHandler: ((Bool) -> Void)? = nil) {
        guard avPlayerItem.status == .readyToPlay else { return }

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.setPlayIfNeeded()
            self.seeking = true
            self.avPlayerItem.seek(to: CMTimeMakeWithSeconds(time, preferredTimescale: Int32(NSEC_PER_SEC))) { finished in
                DispatchQueue.main.async {
                    self.seeking = false
                    self.playIfNeeded()
                    completionHandler?(finished)
                    print("IRAVPlayer seek success")
                }
            }
        }
    }

    func stop() {
        replaceEmpty()
    }

    var progress: TimeInterval {
        return CMTimeGetSeconds(avPlayerItem.currentTime())
    }

    var duration: TimeInterval {
        return CMTimeGetSeconds(avPlayerItem.duration)
    }

    var bitrate: TimeInterval {
        return 0
    }

}

extension IRAVPlayer {

    func reloadVolume() {
        avPlayer.volume = Float(abstractPlayer.volume)
    }

    func reloadPlayableTime() {
        guard let avPlayerItem = avPlayerItem, avPlayerItem.status == .readyToPlay,
              let range = avPlayerItem.loadedTimeRanges.first?.timeRangeValue else {
            playableTime = 0
            return
        }

        let start = CMTimeGetSeconds(range.start)
        let duration = CMTimeGetSeconds(range.duration)
        playableTime = start + duration
    }

    var presentationSize: CGSize {
        return avPlayerItem?.presentationSize ?? CGSize.zero
    }

    func snapshotAtCurrentTime() -> IRPLFImage? {
        guard let avAsset = avAsset,
              abstractPlayer.videoType == .normal else { return nil }

        let imageGenerator = AVAssetImageGenerator(asset: avAsset)
        imageGenerator.appliesPreferredTrackTransform = true
        imageGenerator.requestedTimeToleranceBefore = .zero
        imageGenerator.requestedTimeToleranceAfter = .zero

        do {
            let cgImage = try imageGenerator.copyCGImage(at: avPlayerItem.currentTime(), actualTime: nil)
            return IRPLFImage(cgImage: cgImage)
        } catch {
            print("Error generating image: \(error)")
            return nil
        }
    }

    func pixelBufferAtCurrentTime() -> CVPixelBuffer? {
        guard !seeking else { return nil }
        guard let avOutput = avOutput,
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
        self.displayLink = CADisplayLink(target: self, selector: #selector(displayLinkCallback))
        self.displayLink?.add(to: .current, forMode: .default)
        self.displayLink?.isPaused = false
    }

    @objc func displayLinkCallback(_ sender: CADisplayLink) {
        guard let pixelBuffer = pixelBufferAtCurrentTime() else { return }

        let videoFrame = IRFFCVYUVVideoFrame(pixelBuffer: pixelBuffer)

        videoFrame.position = -1
        videoFrame.duration = -1
        abstractPlayer.displayView?.render(videoFrame)
    }
}

extension IRAVPlayer {

    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey: Any]?, context: UnsafeMutableRawPointer?) {
        guard let item = object as? AVPlayerItem, item == avPlayerItem else { return }

        switch keyPath {
        case "status":
            switch item.status {
            case .unknown:
                state = .buffering
                print("IRAVPlayer item status unknown")

            case .readyToPlay:
                setupTrackInfo()
                print("IRAVPlayer item status ready to play")
                readyToPlayTime = Date().timeIntervalSince1970
                switch state {
                case .buffering, .playing:
                    playIfNeeded()
                case .suspend, .finished, .failed:
                    break
                default:
                    state = .readyToPlay
                }

            case .failed:
                print("IRAVPlayer item status failed")
                readyToPlayTime = 0
                let errorInfo = IRError()

                if let playerItemError = avPlayerItem.error {
                    errorInfo.error = playerItemError as NSError

                    if let extendedLogData = avPlayerItem.errorLog()?.extendedLogData(), extendedLogData.count > 0 {
                        errorInfo.extendedLogData = extendedLogData
                        errorInfo.extendedLogDataStringEncoding = String.Encoding(rawValue: avPlayerItem.errorLog()?.extendedLogDataStringEncoding ?? 0).rawValue
                    }

                    if let errorEvents = avPlayerItem.errorLog()?.events {
                        errorInfo.errorEvents = errorEvents.map { event in
                            let errorEvent = IRErrorEvent()
                            errorEvent.date = event.date
                            errorEvent.URI = event.uri
                            errorEvent.serverAddress = event.serverAddress
                            errorEvent.playbackSessionID = event.playbackSessionID
                            errorEvent.errorStatusCode = event.errorStatusCode
                            errorEvent.errorDomain = event.errorDomain
                            errorEvent.errorComment = event.errorComment
                            return errorEvent
                        }
                    }
                } else if let playerError = avPlayer.error {
                    errorInfo.error = playerError as NSError
                } else {
                    errorInfo.error = NSError(domain: "AVPlayer playback error", code: -1, userInfo: nil)
                }

                abstractPlayer.error = errorInfo
                state = .failed
                // Assuming IRPlayerNotification is adapted to Swift
                IRPlayerNotification.postPlayer(abstractPlayer, error: errorInfo)

            @unknown default:
                fatalError()
            }

        case "playbackBufferEmpty":
            if item.isPlaybackBufferEmpty {
                setPlayIfNeeded()
            }

        case "loadedTimeRanges":
            reloadPlayableTime()
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
        print("\(#function) - AVAsset load failed: \(error?.localizedDescription ?? "Unknown error")")
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
        guard let contentURL = abstractPlayer.contentURL else { return }

        avAsset = AVURLAsset(url: contentURL as URL)
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
                    for loadKey in Self.AVAssetLoadKeys {
                        var error: NSError? = nil
                        let keyStatus = self.avAsset?.statusOfValue(forKey: loadKey, error: &error)
                        if keyStatus == .failed {
                            self.avAssetPrepareFailed(error: error)
                            print("AVAsset load failed: \(error?.localizedDescription ?? "")")
                            return
                        }
                    }
                    let trackStatus = self.avAsset?.statusOfValue(forKey: "tracks", error: nil)
                    if trackStatus == .loaded {
                        self.setupOutput()
                    } else {
                        print("AVAsset load failed")
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

extension IRAVPlayer {

    func setupAVPlayer() {
        avPlayer = AVPlayer(playerItem: avPlayerItem)
        // iOS 10+ specific feature, uncomment if needed and ensure you handle different iOS versions if necessary
        // if #available(iOS 10.0, *) {
        //     avPlayer?.automaticallyWaitsToMinimizeStalling = false
        // }

        playBackTimeObserver = avPlayer?.addPeriodicTimeObserver(forInterval: CMTimeMake(value: 1, timescale: 1), queue: .main) { [weak self] time in
            guard let strongSelf = self else { return }
            if strongSelf.state == .playing {
                let current = CMTimeGetSeconds(time)
                let duration = strongSelf.duration
                IRPlayerNotification.postPlayer(strongSelf.abstractPlayer, progressPercent: current / duration as NSNumber, current: current as NSNumber, total: duration as NSNumber)
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
        if autoLoadedAsset {
            avPlayerItem = AVPlayerItem(asset: avAsset!, automaticallyLoadedAssetKeys: Self.AVAssetLoadKeys)
        } else {
            avPlayerItem = AVPlayerItem(asset: avAsset!)
        }

        avPlayerItem?.addObserver(self, forKeyPath: "status", options: [], context: nil)
        avPlayerItem?.addObserver(self, forKeyPath: "playbackBufferEmpty", options: [.new], context: nil)
        avPlayerItem?.addObserver(self, forKeyPath: "loadedTimeRanges", options: [.new], context: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(avplayerItemDidPlayToEnd(_:)), name: .AVPlayerItemDidPlayToEndTime, object: avPlayerItem)

        setupOutput()
    }

    func cleanAVPlayerItem() {
        avPlayerItem?.cancelPendingSeeks()
        avPlayerItem?.removeObserver(self, forKeyPath: "status")
        avPlayerItem?.removeObserver(self, forKeyPath: "playbackBufferEmpty")
        avPlayerItem?.removeObserver(self, forKeyPath: "loadedTimeRanges")
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

        let pixelBufferAttributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
        ]
        avOutput = AVPlayerItemVideoOutput(pixelBufferAttributes: pixelBufferAttributes)
        avOutput?.requestNotificationOfMediaDataChange(withAdvanceInterval: IRAVPlayer.pixelBufferRequestInterval)
        avPlayerItem?.add(avOutput!)

        print("IRAVPlayer add output success") // Assuming IRPlayerLog is a custom logging function. Replace with your logging mechanism.
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
        IRPlayerNotification.postPlayer(abstractPlayer, playablePercent: 0, current: 0, total: 0)
        IRPlayerNotification.postPlayer(abstractPlayer, progressPercent: 0, current: 0, total: 0)
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
                videoTracks.append(playerTrack(from: track)!)
            } else if track.mediaType == .audio {
                audioEnable = true
                audioTracks.append(playerTrack(from: track)!)
            }
        }

        self.videoTracks = videoTracks
        self.audioTracks = audioTracks

        setupDefaultTrack(for: .visual, from: videoTracks)
        setupDefaultTrack(for: .audible, from: audioTracks)
    }

    private func setupDefaultTrack(for characteristic: AVMediaCharacteristic, from tracks: [IRPlayerTrack]) {
        guard let group = avAsset?.mediaSelectionGroup(forMediaCharacteristic: characteristic) else { return }
        let trackID = (group.defaultOption?.propertyList as? [String: Any])?[IRAVPlayer.avMediaSelectionOptionTrackIDKey] as? Int ?? -1
        let defaultTrack = tracks.first { $0.index == trackID } ?? tracks.first
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
            if let trackID = (group.defaultOption?.propertyList as? [String: Any])?[IRAVPlayer.avMediaSelectionOptionTrackIDKey] as? Int {
                return trackID == audioTrackIndex
            }
            return false
        }) {
            avPlayerItem?.select(option, in: group)
            if let track = audioTracks.first(where: { $0.index == audioTrackIndex }) {
                self.audioTrack = track
            }
        }
    }

    func playerTrack(from track: AVAssetTrack) -> IRPlayerTrack? {
        let obj = IRPlayerTrack()
        obj.index = Int(track.trackID)
        obj.name = track.languageCode!
        return obj
    }

}
