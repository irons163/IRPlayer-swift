//
//  IRFFPlayer.swift
//  IRPlayer-swift
//
//  Created by irons on 2024/3/31.
//

import UIKit // For CGSize
import AVFoundation // For NSTimeInterval

class IRFFPlayer: NSObject {
    typealias AudioCopyPlan = IRFFAudioRenderer.CopyPlan

    struct PlayTransition: Equatable {
        let nextState: IRPlayerState
        let shouldSeekToStart: Bool
    }

    struct BufferingTransition: Equatable {
        let nextState: IRPlayerState
        let hasPreparedOnce: Bool
    }

    enum ReplaceVideoReadiness {
        case ready
        case missingRequiredInput
        case missingDisplayView
    }

    private let stateStore = IRPlayerStateStore()
    let audioRenderer = IRFFAudioRenderer()
    weak var abstractPlayer: (any IRPlaybackBackendHost)?
    var decoder: IRFFDecoder? {
        didSet {
            audioRenderer.attachSource(decoder)
        }
    }
    var audioManager: IRAudioManager?
    private(set) var seeking: Bool = false

    var state: IRPlayerState {
        get { stateStore.value }
        set {
            guard let transition = stateStore.transition(to: newValue) else { return }
            if transition.current != .failed {
                abstractPlayer?.error = nil
            }
            if transition.current == .playing {
                audioRenderer.setEnabled(true)
                if audioManager?.play(withDelegate: audioRenderer) == false {
                    audioRenderer.setEnabled(false)
                }
            } else {
                audioManager?.pause()
                audioRenderer.setEnabled(false)
            }
            abstractPlayer?.playbackBackendDidChangeState(
                previous: transition.previous,
                current: transition.current
            )
        }
    }

    var progress: TimeInterval = 0 {
        didSet {
            guard progress != oldValue else { return }

            let decision = IRPlaybackTimePolicy.progressPostDecision(
                progress: progress,
                oldProgress: oldValue,
                duration: duration,
                lastPostTime: lastPostProgressTime,
                now: Date().timeIntervalSince1970,
                seekEnabled: decoder?.seekEnable != false
            )
            guard decision.shouldPost else { return }
            lastPostProgressTime = decision.nextLastPostTime
            abstractPlayer?.playbackBackendDidUpdateProgress(
                current: decision.current,
                total: decision.total
            )
        }
    }

    var playableTime: TimeInterval = 0 {
        didSet {
            let duration = self.duration
            let newPlayableTime = IRPlaybackTimePolicy.clampedPlayableTime(playableTime, duration: duration)
            if playableTime != newPlayableTime {
                playableTime = newPlayableTime
                return
            }
            guard playableTime != oldValue else { return }
            abstractPlayer?.playbackBackendDidUpdatePlayableTime(
                current: playableTime,
                total: duration
            )
        }
    }

    var prepareToken: Bool = false

    var lastPostProgressTime: TimeInterval = 0.0
    var lastPostPlayableTime: TimeInterval = 0.0

    var currentAudioFrame: IRFFAudioFrame? {
        get { audioRenderer.currentFrame }
        set { audioRenderer.replaceCurrentFrame(newValue) }
    }

    var playing = false {
        didSet {
            audioRenderer.setEnabled(playing)
        }
    }

    init(abstractPlayer: any IRPlaybackBackendHost) {
        self.abstractPlayer = abstractPlayer
        self.audioManager = abstractPlayer.manager
        _ = audioManager?.registerAudioSession()
    }

    deinit {
        clean()
        audioManager?.unregisterAudioSession()
    }

    static func player(with abstractPlayer: any IRPlaybackBackendHost) -> IRFFPlayer {
        return IRFFPlayer(abstractPlayer: abstractPlayer)
    }

    static func replaceVideoReadiness(hasAbstractPlayer: Bool, hasContentURL: Bool, hasDisplayView: Bool) -> ReplaceVideoReadiness {
        return IRFFPlayerPlaybackPolicy.replaceVideoReadiness(
            hasAbstractPlayer: hasAbstractPlayer,
            hasContentURL: hasContentURL,
            hasDisplayView: hasDisplayView
        )
    }

    static func playTransition(from state: IRPlayerState) -> PlayTransition {
        return IRFFPlayerPlaybackPolicy.playTransition(from: state)
    }

    static func pauseTransition(from state: IRPlayerState) -> IRPlayerState? {
        return IRFFPlayerPlaybackPolicy.pauseTransition(from: state)
    }

    static func bufferingTransition(isBuffering: Bool, isPlaying: Bool, hasPreparedOnce: Bool) -> BufferingTransition {
        return IRFFPlayerPlaybackPolicy.bufferingTransition(
            isBuffering: isBuffering,
            isPlaying: isPlaying,
            hasPreparedOnce: hasPreparedOnce
        )
    }

    static func audioSilenceByteCount(numberOfFrames: UInt32, numberOfChannels: UInt32) -> Int? {
        return IRFFAudioRenderer.silenceByteCount(
            numberOfFrames: numberOfFrames,
            numberOfChannels: numberOfChannels
        )
    }

    static func audioCopyPlan(frameSize: Int, outputOffset: Int, remainingFrames: UInt32, numberOfChannels: UInt32) -> AudioCopyPlan? {
        return IRFFAudioRenderer.copyPlan(
            frameSize: frameSize,
            outputOffset: outputOffset,
            remainingFrames: remainingFrames,
            numberOfChannels: numberOfChannels
        )
    }

    func play() {
        playing = true
        decoder?.resume()

        let transition = Self.playTransition(from: state)
        if transition.shouldSeekToStart {
            seek(to: 0)
        }
        state = transition.nextState
    }

    func pause() {
        playing = false
        decoder?.pause()

        if let nextState = Self.pauseTransition(from: state) {
            state = nextState
        }
    }

    func stop() {
        clean()
    }

    func seek(to time: TimeInterval) {
        decoder?.seek(to: time)
    }

    func seek(to time: TimeInterval, completionHandler: ((Bool) -> Void)? = nil) {
        decoder?.seek(to: time, completeHandler: completionHandler)
    }
}

// MARK: - Clean
extension IRFFPlayer {

    private func clean() {
        audioManager?.pause()
        audioRenderer.reset()
        cleanDecoder()
        cleanPlayer()
    }

    private func cleanPlayer() {
        playing = false
        state = .none
        progress = 0
        playableTime = 0
        prepareToken = false
        lastPostProgressTime = 0
        lastPostPlayableTime = 0
        abstractPlayer?.displayView?.cleanEmptyBuffer()
    }

    private func cleanDecoder() {
        if let decoder = decoder {
            decoder.closeFile()
            self.decoder = nil
        }
    }
}

extension IRFFPlayer: IRFFDecoderDelegate {

    func decoderWillOpenInputStream(_ decoder: IRFFDecoder) {
        self.state = .buffering
    }

    func decoderDidPrepareToDecodeFrames(_ decoder: IRFFDecoder) {
        self.state = .readyToPlay
    }

    func decoderDidEndOfFile(_ decoder: IRFFDecoder) {
        self.playableTime = self.duration
    }

    func decoderDidPlaybackFinished(_ decoder: IRFFDecoder) {
        self.state = .finished
    }

    func decoder(_ decoder: IRFFDecoder, didError error: Error) {
        errorHandler(error: error as NSError)
    }

    func decoder(_ decoder: IRFFDecoder, didChangeValueOfBuffering buffering: Bool) {
        let transition = Self.bufferingTransition(
            isBuffering: buffering,
            isPlaying: playing,
            hasPreparedOnce: prepareToken
        )
        state = transition.nextState
        prepareToken = transition.hasPreparedOnce
    }

    func decoder(_ decoder: IRFFDecoder, didChangeValueOfBufferedDuration bufferedDuration: TimeInterval) {
        self.playableTime = self.progress + bufferedDuration
    }

    func decoder(_ decoder: IRFFDecoder, didChangeValueOfProgress progress: TimeInterval) {
        self.progress = progress
    }

    func errorHandler(error: NSError) {
        let obj = IRError()
        obj.error = error
        self.abstractPlayer?.error = obj
        self.state = .failed
        self.abstractPlayer?.playbackBackendDidFail(obj)
    }
}

extension IRFFPlayer {

    var duration: TimeInterval {
        return decoder?.duration ?? 0
    }

    var presentationSize: CGSize {
        return decoder?.prepareToDecode == true ? decoder?.presentationSize ?? .zero : .zero
    }

    var bitrate: TimeInterval {
        return decoder?.prepareToDecode == true ? decoder?.bitrate ?? 0 : 0
    }

    func reloadVolume() {
        audioManager?.volume = IRPlayerVolume.normalizedFloat(from: abstractPlayer?.volume)
    }

    func reloadPlayableBufferInterval() {
        guard let decoder = decoder else { return }
        var bufferInterval = abstractPlayer?.playableBufferInterval ?? 0
        decoder.isLiveStream = abstractPlayer?.isLiveStream ?? false

        // For live streams (RTSP, no duration), use much lower buffer threshold
        // to prevent stuck buffering state
        if decoder.isLiveStream {
            // Use minimum of requested interval or 0.2 seconds for live streams
            bufferInterval = min(bufferInterval, 0.2)
            if bufferInterval == 0 {
                bufferInterval = 0.2 // Default for live streams
            }
        }

        decoder.minBufferedDuration = bufferInterval
    }

    func replaceVideo() {
        clean()

        let readiness = Self.replaceVideoReadiness(
            hasAbstractPlayer: abstractPlayer != nil,
            hasContentURL: abstractPlayer?.contentURL != nil,
            hasDisplayView: abstractPlayer?.displayView != nil
        )

        switch readiness {
        case .missingRequiredInput:
            return
        case .missingDisplayView:
            errorHandler(error: NSError(domain: "IRFFPlayer", code: -1, userInfo: [
                NSLocalizedDescriptionKey: "Cannot replace FFmpeg video without a display view."
            ]))
            return
        case .ready:
            break
        }

        guard let abstractPlayer = abstractPlayer,
              let contentURL = abstractPlayer.contentURL,
              let displayView = abstractPlayer.displayView else { return }

        decoder = IRFFDecoder(contentURL: contentURL as URL,
                              videoFormat: abstractPlayer.decoder.formatForContentURL(contentURL: contentURL),
                              videoOutput: displayView,
                              audioOutput: self)
        decoder?.source = abstractPlayer.videoInput
        decoder?.delegate = self
        decoder?.hardwareDecoderEnable = abstractPlayer.decoder.ffmpegHardwareDecoderEnable
        decoder?.open()
        reloadVolume()
        reloadPlayableBufferInterval()

        let pixelFormat: IRPixelFormat = decoder?.hardwareDecoderEnable == true ? .NV12_IRPixelFormat : .YUV_IRPixelFormat
        displayView.irPixelFormat = pixelFormat

        switch abstractPlayer.videoType {
        case .normal:
            displayView.rendererType = .FFmpegPixelBuffer
        case .vr:
            displayView.rendererType = .FFmpegPixelBufferVR
        case .fisheye, .pano, .custom:
            displayView.rendererType = .FFmpegPixelBuffer
        }
    }
}

extension IRFFPlayer: IRFFDecoderAudioOutput {
    var samplingRate: Float64 {
        return self.audioManager?.samplingRate ?? 0
    }

    var numberOfChannels: UInt32 {
        return self.audioManager?.numberOfChannels ?? 0
    }
}
