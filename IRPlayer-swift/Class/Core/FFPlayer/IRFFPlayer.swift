//
//  IRFFPlayer.swift
//  IRPlayer-swift
//
//  Created by irons on 2024/3/31.
//

import UIKit // For CGSize
import AVFoundation // For NSTimeInterval

class IRFFPlayer: NSObject {
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
                    audioManager?.play(with: self)
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
            
            var duration = self.duration
            if progress <= 0.000001 || progress == duration {
                IRPlayerNotification.postPlayer(abstractPlayer, progressPercent: progress / duration as NSNumber, current: progress as NSNumber, total: duration as NSNumber)
            } else {
                let currentTime = Date().timeIntervalSince1970
                if currentTime - self.lastPostProgressTime >= 1 {
                    self.lastPostProgressTime = currentTime
                    if decoder?.seekEnable == false {
                        duration = progress
                    }
                    IRPlayerNotification.postPlayer(abstractPlayer, progressPercent: progress / duration as NSNumber, current: progress as NSNumber, total: duration as NSNumber)
                }
            }
        }
    }

    var playableTime: TimeInterval = 0 {
        didSet {
            var newPlayableTime = playableTime
            let duration = self.duration
            if newPlayableTime > duration {
                newPlayableTime = duration
            } else if newPlayableTime < 0 {
                newPlayableTime = 0
            }

            if playableTime != newPlayableTime {
                playableTime = newPlayableTime
                IRPlayerNotification.postPlayer(abstractPlayer, playablePercent: playableTime / duration as NSNumber, current: playableTime as NSNumber, total: duration as NSNumber)
            }
        }
    }

    var prepareToken: Bool = false

    var lastPostProgressTime: TimeInterval = 0.0
    var lastPostPlayableTime: TimeInterval = 0.0

    var currentAudioFrame: IRFFAudioFrame?

    var playing = false

    init?(abstractPlayer: IRPlayerImp) {
        self.abstractPlayer = abstractPlayer
        guard let manager = abstractPlayer.manager else { return nil }
        self.audioManager = manager
        manager.registerAudioSession()
    }

    deinit {
        clean()
        audioManager?.unregisterAudioSession()
        print("IRFFPlayer release")
    }

    static func player(with abstractPlayer: IRPlayerImp) -> IRFFPlayer {
        return IRFFPlayer(abstractPlayer: abstractPlayer)!
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
        audioManager?.volume = Float(abstractPlayer?.volume ?? 0)
    }

    func reloadPlayableBufferInterval() {
        decoder?.minBufferedDuration = abstractPlayer?.playableBufferInterval ?? 0
    }

    func replaceVideo() {
        clean()
        guard let contentURL = abstractPlayer?.contentURL else { return }

        decoder = IRFFDecoder(contentURL: contentURL as URL, delegate: self, videoOutput: abstractPlayer!.displayView!, audioOutput: self)
        decoder?.hardwareDecoderEnable = abstractPlayer?.decoder.ffmpegHardwareDecoderEnable ?? false
        decoder?.open()
        reloadVolume()
        reloadPlayableBufferInterval()

        let pixelFormat: IRPixelFormat = decoder?.hardwareDecoderEnable == true ? .NV12_IRPixelFormat : .YUV_IRPixelFormat
        abstractPlayer?.displayView?.pixelFormat = pixelFormat

        switch abstractPlayer?.videoType {
        case .normal:
            abstractPlayer?.displayView?.rendererType = .fFmpegPexelBuffer
        case .vr:
            abstractPlayer?.displayView?.rendererType = .fFmpegPexelBufferVR
        case .fisheye, .pano, .custom:
            abstractPlayer?.displayView?.rendererType = .fFmpegPexelBuffer
        case .none:
            break
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
            memset(outputData, 0, Int(numberOfFrames * numberOfChannels * UInt32(MemoryLayout<Float>.size)))
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
                    memset(currentOutputData, 0, Int(remainingFrames * numberOfChannels) * MemoryLayout<Float>.size)
                    return
                }

                let bytes = UnsafeRawPointer(currentAudioFrame.samples).advanced(by: Int(currentAudioFrame.output_offset)).assumingMemoryBound(to: UInt8.self)
                let bytesLeft = currentAudioFrame.length - currentAudioFrame.output_offset
                let frameSizeOf = Int(numberOfChannels) * MemoryLayout<Float>.size
                let bytesToCopy = min(Int(remainingFrames) * frameSizeOf, bytesLeft)
                let framesToCopy = bytesToCopy / frameSizeOf

                memcpy(currentOutputData, bytes, bytesToCopy)
                remainingFrames -= UInt32(framesToCopy)
                currentOutputData = currentOutputData.advanced(by: framesToCopy * Int(numberOfChannels))

                if bytesToCopy < bytesLeft {
                    currentAudioFrame.output_offset += bytesToCopy
                } else {
                    currentAudioFrame.stopPlaying()
                    self.currentAudioFrame = nil
                }
            }
//        }
    }

}
