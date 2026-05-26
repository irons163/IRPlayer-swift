//
//  IRFFPlayer.swift
//  IRPlayer-swift
//
//  Created by irons on 2024/3/31.
//

import UIKit // For CGSize
import AVFoundation // For NSTimeInterval

class IRFFPlayer: NSObject {
    struct AudioCopyPlan {
        let bytesToCopy: Int
        let framesToCopy: Int
        let hasRemainingFrameBytes: Bool
    }

    private let stateLock = NSLock()
    weak var abstractPlayer: IRPlayerImp?
    var decoder: IRFFDecoder?
    var audioManager: IRAudioManager?
    private(set) var seeking: Bool = false

    var state: IRPlayerState = .none {
        didSet {
            self.stateLock.lock()
            defer { stateLock.unlock() }

            if oldValue != state {
                if state != .failed {
                    abstractPlayer?.error = nil
                }
                if state == .playing {
                    audioManager?.play(withDelegate: self)
                } else {
                    audioManager?.pause()
                }

                // Assuming IRPlayerNotification has been adapted to Swift
                IRPlayerNotification.postPlayer(abstractPlayer, statePrevious: oldValue, current: state)
            }
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
            IRPlayerNotification.postPlayer(
                abstractPlayer,
                progressPercent: IRPlaybackTimePolicy.percent(current: decision.current, total: decision.total),
                current: decision.current as NSNumber,
                total: decision.total as NSNumber
            )
        }
    }

    var playableTime: TimeInterval = 0 {
        didSet {
            let duration = self.duration
            let newPlayableTime = IRPlaybackTimePolicy.clampedPlayableTime(playableTime, duration: duration)
            if playableTime != newPlayableTime {
                playableTime = newPlayableTime
                IRPlayerNotification.postPlayer(
                    abstractPlayer,
                    playablePercent: IRPlaybackTimePolicy.percent(current: playableTime, total: duration),
                    current: playableTime as NSNumber,
                    total: duration as NSNumber
                )
            }
        }
    }

    var prepareToken: Bool = false

    var lastPostProgressTime: TimeInterval = 0.0
    var lastPostPlayableTime: TimeInterval = 0.0

    var currentAudioFrame: IRFFAudioFrame?

    var playing = false

    init(abstractPlayer: IRPlayerImp) {
        self.abstractPlayer = abstractPlayer
        self.audioManager = abstractPlayer.manager
        _ = audioManager?.registerAudioSession()
    }

    deinit {
        clean()
        audioManager?.unregisterAudioSession()
        print("IRFFPlayer release")
    }

    static func player(with abstractPlayer: IRPlayerImp) -> IRFFPlayer {
        return IRFFPlayer(abstractPlayer: abstractPlayer)
    }

    static func audioSilenceByteCount(numberOfFrames: UInt32, numberOfChannels: UInt32) -> Int? {
        guard numberOfFrames > 0, numberOfChannels > 0 else { return nil }

        let (sampleCount, sampleCountOverflow) = Int(numberOfFrames).multipliedReportingOverflow(by: Int(numberOfChannels))
        guard !sampleCountOverflow, sampleCount > 0 else { return nil }

        let (byteCount, byteCountOverflow) = sampleCount.multipliedReportingOverflow(by: MemoryLayout<Float>.size)
        guard !byteCountOverflow else { return nil }
        return byteCount
    }

    static func audioCopyPlan(frameSize: Int, outputOffset: Int, remainingFrames: UInt32, numberOfChannels: UInt32) -> AudioCopyPlan? {
        guard frameSize > 0,
              outputOffset >= 0,
              outputOffset <= frameSize,
              remainingFrames > 0,
              numberOfChannels > 0 else {
            return nil
        }

        let (frameSizeOf, frameSizeOverflow) = Int(numberOfChannels).multipliedReportingOverflow(by: MemoryLayout<Float>.size)
        guard !frameSizeOverflow, frameSizeOf > 0 else { return nil }

        let bytesLeft = frameSize - outputOffset
        guard bytesLeft > 0 else { return nil }

        let (requestedBytes, requestedBytesOverflow) = Int(remainingFrames).multipliedReportingOverflow(by: frameSizeOf)
        guard !requestedBytesOverflow else { return nil }

        let boundedBytesToCopy = min(requestedBytes, bytesLeft)
        let bytesToCopy = boundedBytesToCopy - (boundedBytesToCopy % frameSizeOf)
        let framesToCopy = bytesToCopy / frameSizeOf
        guard bytesToCopy > 0, framesToCopy > 0 else { return nil }

        return AudioCopyPlan(
            bytesToCopy: bytesToCopy,
            framesToCopy: framesToCopy,
            hasRemainingFrameBytes: bytesToCopy < bytesLeft
        )
    }

    func play() {
        playing = true
        decoder?.resume()

        switch state {
        case .finished:
            seek(to: 0)
        case .none, .failed, .buffering:
            state = .buffering
        case .readyToPlay, .playing, .suspend:
            state = .playing
        }
    }

    func pause() {
        playing = false
        decoder?.pause()

        switch state {
        case .none, .suspend:
            break
        case .failed, .readyToPlay, .finished, .playing, .buffering:
            state = .suspend
        }
    }

    func stop() {
        clean()
    }

    func seek(to time: TimeInterval) {
        decoder?.seek(to: time)
    }

    func seek(to time: TimeInterval, completeHandler: ((Bool) -> Void)? = nil) {
        decoder?.seek(to: time, completeHandler: completeHandler)
    }
}

// MARK: - Clean
extension IRFFPlayer {

    private func clean() {
        cleanDecoder()
        cleanFrame()
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

    private func cleanFrame() {
        currentAudioFrame?.stopPlaying()
        currentAudioFrame = nil
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
        if buffering {
            self.state = .buffering
        } else {
            if self.playing {
                self.state = .playing
            } else if !self.prepareToken {
                self.state = .readyToPlay
                self.prepareToken = true
            } else {
                self.state = .suspend
            }
        }
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
        IRPlayerNotification.postPlayer(self.abstractPlayer, error: obj)
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
        decoder?.minBufferedDuration = abstractPlayer?.playableBufferInterval ?? 0
    }

    func replaceVideo() {
        clean()
        guard let abstractPlayer = abstractPlayer,
              let contentURL = abstractPlayer.contentURL else { return }
        guard let displayView = abstractPlayer.displayView else {
            errorHandler(error: NSError(domain: "IRFFPlayer", code: -1, userInfo: [
                NSLocalizedDescriptionKey: "Cannot replace FFmpeg video without a display view."
            ]))
            return
        }

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

extension IRFFPlayer: IRAudioManagerDelegate {
    
    func audioManager(_ audioManager: IRAudioManager, outputData: UnsafeMutablePointer<Float>, numberOfFrames: UInt32, numberOfChannels: UInt32) {
        guard self.playing else {
            if let byteCount = Self.audioSilenceByteCount(numberOfFrames: numberOfFrames, numberOfChannels: numberOfChannels) {
                memset(outputData, 0, byteCount)
            }
            return
        }

//        autoreleasepool {
            var remainingFrames = numberOfFrames
            var currentOutputData = outputData

            while remainingFrames > 0 {
                if self.currentAudioFrame == nil {
                    self.currentAudioFrame = self.decoder?.fetchAudioFrame()
                    self.currentAudioFrame?.startPlaying()
                }

                guard let currentAudioFrame = self.currentAudioFrame else {
                    if let byteCount = Self.audioSilenceByteCount(numberOfFrames: remainingFrames, numberOfChannels: numberOfChannels) {
                        memset(currentOutputData, 0, byteCount)
                    }
                    return
                }

                guard let samples = currentAudioFrame.samples else {
                    currentAudioFrame.stopPlaying()
                    self.currentAudioFrame = nil
                    if let byteCount = Self.audioSilenceByteCount(numberOfFrames: remainingFrames, numberOfChannels: numberOfChannels) {
                        memset(currentOutputData, 0, byteCount)
                    }
                    return
                }

                guard let copyPlan = Self.audioCopyPlan(
                    frameSize: currentAudioFrame.size,
                    outputOffset: currentAudioFrame.outputOffset,
                    remainingFrames: remainingFrames,
                    numberOfChannels: numberOfChannels
                ) else {
                    currentAudioFrame.stopPlaying()
                    self.currentAudioFrame = nil
                    if let byteCount = Self.audioSilenceByteCount(numberOfFrames: remainingFrames, numberOfChannels: numberOfChannels) {
                        memset(currentOutputData, 0, byteCount)
                    }
                    return
                }

                let bytes = UnsafeRawPointer(samples).advanced(by: Int(currentAudioFrame.outputOffset)).assumingMemoryBound(to: UInt8.self)
                let bytesToCopy = copyPlan.bytesToCopy
                let framesToCopy = copyPlan.framesToCopy
                memcpy(currentOutputData, bytes, bytesToCopy)
                remainingFrames -= UInt32(framesToCopy)
                currentOutputData = currentOutputData.advanced(by: framesToCopy * Int(numberOfChannels))

                if copyPlan.hasRemainingFrameBytes {
                    currentAudioFrame.outputOffset += bytesToCopy
                } else {
                    currentAudioFrame.stopPlaying()
                    self.currentAudioFrame = nil
                }
            }
//        }
    }

}
