//
//  IRFFPlayer.swift
//  IRPlayer-swift
//
//  Created by irons on 2024/3/31.
//

import AVFoundation
import UIKit

class IRFFPlayer: NSObject {
    typealias AudioCopyPlan = IRFFAudioRenderer.CopyPlan
    typealias PlayTransition = IRFFPlayerStateMachine.PlayTransition
    typealias BufferingTransition =
        IRFFPlayerStateMachine.BufferingTransition

    enum ReplaceVideoReadiness: Equatable {
        case ready
        case missingRequiredInput
        case missingDisplayView
    }

    struct Dependencies {
        let executor: IRFFPlayerExecutor
        let decoderFactory: IRFFPlayerDecoderSession.DecoderFactory
        let audioRenderer: IRFFAudioRenderer

        static var system: Dependencies {
            Dependencies(
                executor: IRFFPlayerExecutor(),
                decoderFactory: {
                    IRFFDecoder(
                        contentURL: $0,
                        videoFormat: $1,
                        videoOutput: $2,
                        audioOutput: $3
                    )
                },
                audioRenderer: IRFFAudioRenderer()
            )
        }
    }

    weak var abstractPlayer: (any IRPlaybackBackendHost)?
    let runtime: IRFFPlayerRuntime
    private var presentationCommandGeneration: UInt64 = 0

    var decoder: IRFFDecoder? {
        get { runtime.currentDecoder }
        set { runtime.adopt(newValue) }
    }

    var audioRenderer: IRFFAudioRenderer {
        runtime.audioRenderer
    }

    var audioManager: IRAudioManager? {
        runtime.audioManager
    }

    var seeking: Bool {
        runtime.snapshot.isSeeking
    }

    var state: IRPlayerState {
        get { runtime.state }
        set { runtime.state = newValue }
    }

    var progress: TimeInterval {
        get { runtime.progress }
        set { runtime.progress = newValue }
    }

    var playableTime: TimeInterval {
        get { runtime.playableTime }
        set { runtime.playableTime = newValue }
    }

    var currentAudioFrame: IRFFAudioFrame? {
        get { runtime.currentAudioFrame }
        set { runtime.currentAudioFrame = newValue }
    }

    var playing: Bool {
        get { runtime.playRequested }
        set { runtime.playRequested = newValue }
    }

    var duration: TimeInterval {
        runtime.snapshot.duration
    }

    var presentationSize: CGSize {
        runtime.snapshot.presentationSize
    }

    var bitrate: TimeInterval {
        runtime.snapshot.bitrate
    }

    var snapshot: IRPlaybackBackendSnapshot {
        runtime.snapshot
    }

    init(
        abstractPlayer: any IRPlaybackBackendHost,
        dependencies: Dependencies = .system
    ) {
        self.abstractPlayer = abstractPlayer
        self.runtime = IRFFPlayerRuntime(
            host: abstractPlayer,
            audioManager: abstractPlayer.manager,
            executor: dependencies.executor,
            decoderFactory: dependencies.decoderFactory,
            audioRenderer: dependencies.audioRenderer
        )
        super.init()
    }

    deinit {
        runtime.close()
    }

    static func player(
        with abstractPlayer: any IRPlaybackBackendHost
    ) -> IRFFPlayer {
        IRFFPlayer(abstractPlayer: abstractPlayer)
    }

    static func replaceVideoReadiness(
        hasAbstractPlayer: Bool,
        hasContentURL: Bool,
        hasDisplayView: Bool
    ) -> ReplaceVideoReadiness {
        guard hasAbstractPlayer, hasContentURL else {
            return .missingRequiredInput
        }
        guard hasDisplayView else { return .missingDisplayView }
        return .ready
    }

    static func playTransition(from state: IRPlayerState) -> PlayTransition {
        IRFFPlayerStateMachine.playTransition(from: state)
    }

    static func pauseTransition(
        from state: IRPlayerState
    ) -> IRPlayerState? {
        IRFFPlayerStateMachine.pauseTransition(from: state)
    }

    static func bufferingTransition(
        isBuffering: Bool,
        isPlaying: Bool,
        hasPreparedOnce: Bool
    ) -> BufferingTransition {
        IRFFPlayerStateMachine.bufferingTransition(
            isBuffering: isBuffering,
            isPlaying: isPlaying,
            hasPreparedOnce: hasPreparedOnce
        )
    }

    static func audioSilenceByteCount(
        numberOfFrames: UInt32,
        numberOfChannels: UInt32
    ) -> Int? {
        IRFFAudioRenderer.silenceByteCount(
            numberOfFrames: numberOfFrames,
            numberOfChannels: numberOfChannels
        )
    }

    static func audioCopyPlan(
        frameSize: Int,
        outputOffset: Int,
        remainingFrames: UInt32,
        numberOfChannels: UInt32
    ) -> AudioCopyPlan? {
        IRFFAudioRenderer.copyPlan(
            frameSize: frameSize,
            outputOffset: outputOffset,
            remainingFrames: remainingFrames,
            numberOfChannels: numberOfChannels
        )
    }

    func play() {
        runtime.play()
    }

    func pause() {
        runtime.pause()
    }

    func stop() {
        IRMainThreadExecutor.sync {
            presentationCommandGeneration &+= 1
            let generation = presentationCommandGeneration
            _ = runtime.reset()
            guard presentationCommandGeneration == generation else {
                return
            }
            IRFFPlayerPresentation.clear(abstractPlayer?.displayView)
        }
    }

    func seek(to time: TimeInterval) {
        runtime.seek(to: time, completion: nil)
    }

    func seek(
        to time: TimeInterval,
        completionHandler: ((Bool) -> Void)? = nil
    ) {
        runtime.seek(to: time, completion: completionHandler)
    }

    func reloadVolume() {
        runtime.reloadVolume(abstractPlayer?.volume)
    }

    func reloadPlayableBufferInterval() {
        runtime.reloadPlayableBufferInterval(
            requestedInterval: abstractPlayer?.playableBufferInterval ?? 0,
            isLiveStream: abstractPlayer?.isLiveStream ?? false
        )
    }

    func replaceVideo() {
        IRMainThreadExecutor.sync {
            presentationCommandGeneration &+= 1
            replaceVideoOnMain(
                generation: presentationCommandGeneration
            )
        }
    }

    func errorHandler(error: NSError) {
        runtime.fail(error)
    }

    private func replaceVideoOnMain(generation: UInt64) {
        _ = runtime.reset()
        guard presentationCommandGeneration == generation else {
            return
        }
        let displayView = abstractPlayer?.displayView
        IRFFPlayerPresentation.clear(displayView)

        let readiness = Self.replaceVideoReadiness(
            hasAbstractPlayer: abstractPlayer != nil,
            hasContentURL: abstractPlayer?.contentURL != nil,
            hasDisplayView: displayView != nil
        )
        switch readiness {
        case .missingRequiredInput:
            return
        case .missingDisplayView:
            errorHandler(
                error: NSError(
                    domain: "IRFFPlayer",
                    code: -1,
                    userInfo: [
                        NSLocalizedDescriptionKey:
                            "Cannot replace FFmpeg video without a display view."
                    ]
                )
            )
            return
        case .ready:
            break
        }

        guard let abstractPlayer,
              let contentURL = abstractPlayer.contentURL,
              let displayView else {
            return
        }

        let hardwareDecoderEnabled =
            abstractPlayer.decoder.ffmpegHardwareDecoderEnable
        IRFFPlayerPresentation.configuration(
            hardwareDecoderEnabled: hardwareDecoderEnabled,
            videoType: abstractPlayer.videoType
        ).apply(to: displayView)

        let requestedBufferInterval =
            abstractPlayer.playableBufferInterval
        let isLiveStream = abstractPlayer.isLiveStream
        let configuration = IRFFPlayerDecoderSession.Configuration(
            contentURL: contentURL as URL,
            videoFormat: abstractPlayer.decoder.formatForContentURL(
                contentURL: contentURL
            ),
            videoOutput: displayView,
            audioOutput: self,
            source: abstractPlayer.videoInput,
            hardwareDecoderEnabled: hardwareDecoderEnabled,
            isLiveStream: isLiveStream,
            minimumBufferedDuration:
                IRFFPlayerRuntime.minimumBufferedDuration(
                    requestedInterval: requestedBufferInterval,
                    isLiveStream: isLiveStream
                )
        )
        _ = runtime.activate(
            configuration: configuration,
            volume: abstractPlayer.volume
        )
    }
}

extension IRFFPlayer: IRFFDecoderAudioOutput {
    var samplingRate: Float64 {
        runtime.samplingRate
    }

    var numberOfChannels: UInt32 {
        runtime.numberOfChannels
    }
}
