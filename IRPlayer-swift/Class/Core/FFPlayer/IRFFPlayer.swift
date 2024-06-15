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

    var progress: TimeInterval {
        get {
            return self.progress
        }
        set(newProgress) {
            guard progress != newProgress else { return }
            self.progress = newProgress
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
        decoder?.seek(toTime: time)
    }

    func seek(to time: TimeInterval, completeHandler: @escaping (Bool) -> Void) {
        decoder?.seek(toTime: time, completeHandler: completeHandler)
    }

    // Assuming a clean method exists to reset or clear the player's state
    private func clean() {
        // Implementation...
    }
}

// Assuming IRFFDecoderDelegate and IRFFDecoderAudioOutput are protocol names that have been translated or exposed to Swift.
extension IRFFPlayer: IRFFDecoderDelegate, IRFFDecoderAudioOutput {

    // Initialization within an extension isn't supported directly in Swift.
    // You might need to initialize these properties elsewhere or use a different pattern.

    // Example function skeletons based on the protocol conformances and properties.
    func decoderDidPrepare(toDecodeFrames decoder: IRFFDecoder) {
        // Implementation of protocol method
    }

    func decoderDidEnd(ofFile decoder: IRFFDecoder) {
        // Implementation of protocol method
    }

    // Additional functions for IRFFDecoderAudioOutput as needed
    func numberOfChannels() -> UInt32 {
        return 0
    }

    func samplingRate() -> Float64 {
        return 0
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
        decoder?.minBufferedDruation = abstractPlayer?.playableBufferInterval ?? 0
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

extension IRFFPlayer: IRAudioManagerDelegate {
    func audioManager(_ audioManager: IRAudioManager, outputData: UnsafeMutablePointer<Float>, numberOfFrames: UInt32, numberOfChannels: UInt32) {

    }
}
