//
//  IRFFDecoder.swift
//  IRPlayer-swift
//
//  Created by irons on 2024/7/11.
//

import Foundation
import CoreGraphics
import AVFoundation
import IRFFMpeg

protocol IRFFDecoderDelegate: AnyObject {
    func decoderWillOpenInputStream(_ decoder: IRFFDecoder)
    func decoderDidPrepareToDecodeFrames(_ decoder: IRFFDecoder)
    func decoderDidEndOfFile(_ decoder: IRFFDecoder)
    func decoderDidPlaybackFinished(_ decoder: IRFFDecoder)
    func decoder(_ decoder: IRFFDecoder, didError error: Error)
    func decoder(_ decoder: IRFFDecoder, didChangeValueOfBuffering buffering: Bool)
    func decoder(_ decoder: IRFFDecoder, didChangeValueOfBufferedDuration bufferedDuration: TimeInterval)
    func decoder(_ decoder: IRFFDecoder, didChangeValueOfProgress progress: TimeInterval)
}

@objc public protocol IRFFDecoderVideoOutput: AnyObject {
    @objc optional func send(videoFrame frame: IRFFVideoFrame)
}

@objc protocol IRFFDecoderAudioOutput: AnyObject {
    var numberOfChannels: UInt32 { get }
    var samplingRate: Float64 { get }
}

@objcMembers public class IRFFDecoder: NSObject {
    struct BufferedDurationTransition: Equatable {
        let bufferedDuration: TimeInterval
        let shouldFinishPlayback: Bool
    }

    struct SeekCompletionTransition: Equatable {
        let endOfFile: Bool
        let playbackFinished: Bool
        let buffering: Bool
        let videoPaused: Bool
        let videoEndOfFile: Bool
        let seekToTime: TimeInterval
        let audioTimeClock: TimeInterval
        let shouldClearFrames: Bool
    }

    struct ReadPacketEOFTransition: Equatable {
        let endOfFile: Bool
        let videoEndOfFile: Bool
        let shouldFinishReadLoop: Bool
        let shouldNotifyDelegate: Bool
    }

    struct BufferingStatusTransition: Equatable {
        let buffering: Bool
        let bufferingStartTime: TimeInterval
    }

    enum PacketRoute: Equatable {
        case video
        case audio
        case ignored
    }

    struct SeekPreparation: Equatable {
        let clampedTime: TimeInterval
    }

    weak var delegate: IRFFDecoderDelegate?
    weak var source: IRFFVideoDecoderDataSource?
    weak var videoOutput: IRFFDecoderVideoOutput?
    weak var audioOutput: IRFFDecoderAudioOutput?

    private var ffmpegOperationQueue: OperationQueue? = OperationQueue()
    private var openFileOperation: Operation?
    private var readPacketOperation: Operation?
    private var decodeFrameOperation: Operation?
    private var displayOperation: Operation?

    private var formatContext: IRFFFormatContext?
    private var audioDecoder: IRFFAudioDecoder?
    private var videoDecoder: IRFFVideoDecoder?
    private let runtimeState = IRFFDecoderRuntimeState()

    private(set) var error: Error? {
        get { runtimeState.error }
        set { runtimeState.error = newValue }
    }
    private(set) var contentURL: URL
    private(set) var videoFormat: IRVideoFormat
    private(set) var progress: TimeInterval {
        get { runtimeState.snapshot.progress }
        set {
            guard let change = runtimeState.setProgress(newValue) else { return }
            delegate?.decoder(self, didChangeValueOfProgress: change.current)
        }
    }
    private(set) var bufferedDuration: TimeInterval {
        get { runtimeState.snapshot.bufferedDuration }
        set {
            let transition = Self.bufferedDurationTransition(
                bufferedDuration: newValue,
                endOfFile: endOfFile
            )
            guard let change = runtimeState.applyBufferedDuration(
                requestedValue: newValue,
                normalizedValue: transition.bufferedDuration
            ) else { return }
            delegate?.decoder(
                self,
                didChangeValueOfBufferedDuration: change.current
            )
            if transition.shouldFinishPlayback {
                playbackFinished = true
            }
            checkBufferingStatus()
        }
    }
    private(set) var buffering: Bool {
        get { runtimeState.snapshot.buffering }
        set {
            guard let change = runtimeState.setBuffering(newValue) else { return }
            delegate?.decoder(self, didChangeValueOfBuffering: change.current)
        }
    }
    private(set) var playbackFinished: Bool {
        get { runtimeState.snapshot.playbackFinished }
        set {
            guard let change = runtimeState.setPlaybackFinished(newValue),
                  change.current else { return }
            progress = duration
            delegate?.decoderDidPlaybackFinished(self)
        }
    }
    var closed: Bool { runtimeState.snapshot.closed }
    private(set) var endOfFile: Bool {
        get { runtimeState.snapshot.endOfFile }
        set { runtimeState.setEndOfFile(newValue) }
    }
    private(set) var paused: Bool {
        get { runtimeState.snapshot.paused }
        set { runtimeState.setPaused(newValue) }
    }
    private(set) var seeking: Bool {
        get { runtimeState.snapshot.seeking }
        set { runtimeState.setSeeking(newValue) }
    }
    private(set) var prepareToDecode: Bool {
        get { runtimeState.snapshot.prepareToDecode }
        set { runtimeState.setPrepareToDecode(newValue) }
    }

    private var selectAudioTrack = false
    private var selectAudioTrackIndex = 0
    private var currentVideoFrame: IRFFVideoFrame? {
        get { runtimeState.currentVideoFrame }
        set { runtimeState.currentVideoFrame = newValue }
    }
    private var currentAudioFrame: IRFFAudioFrame? {
        get { runtimeState.currentAudioFrame }
        set { runtimeState.currentAudioFrame = newValue }
    }

    private(set) var audioTimeClock: TimeInterval {
        get { runtimeState.snapshot.audioTimeClock }
        set { runtimeState.setAudioTimeClock(newValue) }
    }

    var hardwareDecoderEnable: Bool {
        get { runtimeState.snapshot.hardwareDecoderEnable }
        set { runtimeState.setHardwareDecoderEnable(newValue) }
    }
    var minBufferedDuration: TimeInterval {
        get { runtimeState.snapshot.minBufferedDuration }
        set { runtimeState.setMinBufferedDuration(newValue) }
    }
    private(set) var reading: Bool {
        get { runtimeState.snapshot.reading }
        set { runtimeState.setReading(newValue) }
    }
    var isLiveStream: Bool {
        get { runtimeState.snapshot.isLiveStream }
        set { runtimeState.setIsLiveStream(newValue) }
    }

    var videoEnable: Bool {
        return formatContext?.videoEnable ?? false
    }

    var audioEnable: Bool {
        return formatContext?.audioEnable ?? false
    }

    var videoTrack: IRFFTrack? {
        return formatContext?.videoTrack
    }

    var audioTrack: IRFFTrack? {
        return formatContext?.audioTrack
    }

    var videoTracks: [IRFFTrack] {
        return formatContext?.videoTracks ?? []
    }

    var audioTracks: [IRFFTrack] {
        return formatContext?.audioTracks ?? []
    }

    var metadata: [String: Any] {
        return formatContext?.metadata as? [String: Any] ?? [:]
    }

    var presentationSize: CGSize {
        return formatContext?.videoPresentationSize ?? .zero
    }

    var aspect: CGFloat {
        return formatContext?.videoAspect ?? 0
    }

    private var bufferingStartTime: TimeInterval {
        get { runtimeState.snapshot.bufferingStartTime }
        set { runtimeState.setBufferingStartTime(newValue) }
    }

    var duration: TimeInterval {
        return formatContext?.duration ?? 0
    }

    var bitrate: TimeInterval {
        return formatContext?.bitrate ?? 0
    }

    var seekEnable: Bool {
        return duration > 0
    }

    init(contentURL: URL, videoFormat: IRVideoFormat, videoOutput: IRFFDecoderVideoOutput?, audioOutput: IRFFDecoderAudioOutput?) {
        self.contentURL = contentURL
        self.videoFormat = videoFormat
        self.videoOutput = videoOutput
        self.audioOutput = audioOutput
        super.init()
        IRFFmpegBootstrap.initializeIfNeeded()
    }

    func open() {
        setupOperationQueue()
    }

    private func setupOperationQueue() {
        ffmpegOperationQueue?.maxConcurrentOperationCount = 3
        // .userInitiated is appropriate for streaming video: high-priority but not
        // user-interactive. Using .userInteractive here causes a priority inversion
        // because the display thread blocks on NSCondition.wait() in getFrameSync(),
        // and NSCondition does not propagate QoS to the signaling thread.
        ffmpegOperationQueue?.qualityOfService = .userInitiated
        setupOpenFileOperation()
    }

    private func setupOpenFileOperation() {
        let operation = BlockOperation { [weak self] in
            self?.openFormatContext()
        }
        operation.queuePriority = .veryHigh
        operation.qualityOfService = .userInitiated
        openFileOperation = operation
        Self.enqueue(operation, on: ffmpegOperationQueue)
    }

    private func setupReadPacketOperation() {
        if error != nil {
            delegateErrorCallback()
            return
        }
        guard let openFileOperation else { return }

        if Self.needsScheduling(readPacketOperation) {
            let operation = BlockOperation { [weak self] in
                self?.readPacketThread()
            }
            operation.queuePriority = .veryHigh
            operation.qualityOfService = .userInitiated
            Self.addDependency(openFileOperation, to: operation)
            readPacketOperation = operation
            Self.enqueue(operation, on: ffmpegOperationQueue)
        }
        if formatContext?.videoEnable == true {
            if Self.needsScheduling(decodeFrameOperation) {
                let operation = BlockOperation { [weak self] in
                    self?.videoDecoder?.decodeFrameThread()
                }
                operation.queuePriority = .veryHigh
                operation.qualityOfService = .userInitiated
                Self.addDependency(openFileOperation, to: operation)
                decodeFrameOperation = operation
                Self.enqueue(operation, on: ffmpegOperationQueue)
            }
            if Self.needsScheduling(displayOperation) {
                let operation = BlockOperation { [weak self] in
                    self?.displayThread()
                }
                operation.queuePriority = .veryHigh
                operation.qualityOfService = .userInitiated
                Self.addDependency(openFileOperation, to: operation)
                displayOperation = operation
                Self.enqueue(operation, on: ffmpegOperationQueue)
            }
        }
    }

    static func needsScheduling(_ operation: Operation?) -> Bool {
        return IRFFDecoderOperationPolicy.needsScheduling(operation)
    }

    @discardableResult
    static func addDependency(_ dependency: Operation?, to operation: Operation?) -> Bool {
        return IRFFDecoderOperationPolicy.addDependency(dependency, to: operation)
    }

    @discardableResult
    static func enqueue(_ operation: Operation?, on queue: OperationQueue?) -> Bool {
        return IRFFDecoderOperationPolicy.enqueue(operation, on: queue)
    }

    static func videoCodecContext(from formatContext: IRFFFormatContext?) -> UnsafeMutablePointer<AVCodecContext>? {
        return IRFFDecoderCodecContextPolicy.videoCodecContext(from: formatContext)
    }

    static func audioCodecContext(from formatContext: IRFFFormatContext?) -> UnsafeMutablePointer<AVCodecContext>? {
        return IRFFDecoderCodecContextPolicy.audioCodecContext(from: formatContext)
    }

    static func audioPacketError(fromPacketResult packetResult: Int) -> NSError? {
        return IRFFDecoderAudioPolicy.audioPacketError(fromPacketResult: packetResult)
    }

    static func bufferedDurationTransition(bufferedDuration: TimeInterval, endOfFile: Bool) -> BufferedDurationTransition {
        return IRFFDecoderAudioPolicy.bufferedDurationTransition(bufferedDuration: bufferedDuration, endOfFile: endOfFile)
    }

    static func packetBufferBackpressureSleepInterval(audioSize: Int,
                                                      videoPacketSize: Int,
                                                      maxBufferSize: Int = 20 * 1024 * 1024,
                                                      paused: Bool) -> TimeInterval? {
        return IRFFDecoderPacketPolicy.packetBufferBackpressureSleepInterval(
            audioSize: audioSize,
            videoPacketSize: videoPacketSize,
            maxBufferSize: maxBufferSize,
            paused: paused
        )
    }

    static func seekPreparation(requestedTime: TimeInterval,
                                seekEnabled: Bool,
                                hasError: Bool,
                                hasAudio: Bool,
                                seekMinTime: TimeInterval,
                                duration: TimeInterval,
                                minBufferedDuration: TimeInterval) -> SeekPreparation? {
        return IRFFDecoderSeekPolicy.seekPreparation(
            requestedTime: requestedTime,
            seekEnabled: seekEnabled,
            hasError: hasError,
            hasAudio: hasAudio,
            seekMinTime: seekMinTime,
            duration: duration,
            minBufferedDuration: minBufferedDuration
        )
    }

    static func audioSyncedVideoSleepDuration(framePosition: TimeInterval,
                                              frameDuration: TimeInterval,
                                              audioTimeClock: TimeInterval,
                                              fps: TimeInterval) -> TimeInterval? {
        return IRFFDecoderDisplayPolicy.audioSyncedVideoSleepDuration(
            framePosition: framePosition,
            frameDuration: frameDuration,
            audioTimeClock: audioTimeClock,
            fps: fps
        )
    }

    static func standaloneVideoSleepDuration(frameDuration: TimeInterval, fps: TimeInterval) -> TimeInterval? {
        return IRFFDecoderDisplayPolicy.standaloneVideoSleepDuration(frameDuration: frameDuration, fps: fps)
    }

    static func videoFrameOrderingPosition(_ position: TimeInterval?) -> TimeInterval? {
        return IRFFDecoderDisplayPolicy.videoFrameOrderingPosition(position)
    }

    static func shouldAcceptVideoFrame(currentPosition: TimeInterval?, nextPosition: TimeInterval?) -> Bool {
        return IRFFDecoderDisplayPolicy.shouldAcceptVideoFrame(
            currentPosition: currentPosition,
            nextPosition: nextPosition
        )
    }

    static func shouldFetchAudioFrame(closed: Bool,
                                      seeking: Bool,
                                      buffering: Bool,
                                      paused: Bool,
                                      playbackFinished: Bool,
                                      audioEnabled: Bool) -> Bool {
        return IRFFDecoderAudioPolicy.shouldFetchAudioFrame(
            closed: closed,
            seeking: seeking,
            buffering: buffering,
            paused: paused,
            playbackFinished: playbackFinished,
            audioEnabled: audioEnabled
        )
    }

    static func resumeSeekTarget(playbackFinished: Bool) -> TimeInterval? {
        return IRFFDecoderSeekPolicy.resumeSeekTarget(playbackFinished: playbackFinished)
    }

    static func seekCompletionTransition(seeking: Bool, progress: TimeInterval) -> SeekCompletionTransition? {
        return IRFFDecoderSeekPolicy.seekCompletionTransition(seeking: seeking, progress: progress)
    }

    static func audioTrackSelectionSeekTarget(selectionPending: Bool,
                                              decoderWasReset: Bool,
                                              hasAudioDecoder: Bool,
                                              playbackFinished: Bool,
                                              audioTimeClock: TimeInterval) -> TimeInterval? {
        return IRFFDecoderSeekPolicy.audioTrackSelectionSeekTarget(
            selectionPending: selectionPending,
            decoderWasReset: decoderWasReset,
            hasAudioDecoder: hasAudioDecoder,
            playbackFinished: playbackFinished,
            audioTimeClock: audioTimeClock
        )
    }

    static func readPacketEOFTransition(readFrameResult: Int32?) -> ReadPacketEOFTransition? {
        return IRFFDecoderPacketPolicy.readPacketEOFTransition(readFrameResult: readFrameResult)
    }

    static func packetRoute(streamIndex: Int32, videoTrackIndex: Int?, audioTrackIndex: Int?) -> PacketRoute {
        return IRFFDecoderPacketPolicy.packetRoute(
            streamIndex: streamIndex,
            videoTrackIndex: videoTrackIndex,
            audioTrackIndex: audioTrackIndex
        )
    }

    static func displayIdleSleepInterval(seeking: Bool,
                                         buffering: Bool,
                                         paused: Bool,
                                         hasCurrentFrame: Bool) -> TimeInterval? {
        return IRFFDecoderDisplayPolicy.displayIdleSleepInterval(
            seeking: seeking,
            buffering: buffering,
            paused: paused,
            hasCurrentFrame: hasCurrentFrame
        )
    }

    static func shouldFinishDisplay(endOfFile: Bool, videoDecoderEmpty: Bool) -> Bool {
        return IRFFDecoderDisplayPolicy.shouldFinishDisplay(endOfFile: endOfFile, videoDecoderEmpty: videoDecoderEmpty)
    }

    static func shouldNotifyError(closed: Bool, hasError: Bool) -> Bool {
        return IRFFDecoderOperationPolicy.shouldNotifyError(closed: closed, hasError: hasError)
    }

    static func readLoopExitAction(closed: Bool, hasError: Bool) -> IRFFDecoderReadLoopState.Action? {
        return IRFFDecoderReadLoopState.exitAction(closed: closed, hasError: hasError)
    }

    static func readLoopSeekCompletionAction(seeking: Bool,
                                             progress: TimeInterval) -> IRFFDecoderReadLoopState.Action? {
        return IRFFDecoderReadLoopState.seekCompletionAction(seeking: seeking, progress: progress)
    }

    static func readLoopAudioTrackSelectionAction(selectionPending: Bool,
                                                  decoderWasReset: Bool,
                                                  hasAudioDecoder: Bool,
                                                  playbackFinished: Bool,
                                                  audioTimeClock: TimeInterval) -> IRFFDecoderReadLoopState.AudioTrackSelectionAction? {
        return IRFFDecoderReadLoopState.audioTrackSelectionAction(
            selectionPending: selectionPending,
            decoderWasReset: decoderWasReset,
            hasAudioDecoder: hasAudioDecoder,
            playbackFinished: playbackFinished,
            audioTimeClock: audioTimeClock
        )
    }

    static func readLoopBackpressureAction(audioSize: Int,
                                           videoPacketSize: Int,
                                           paused: Bool) -> IRFFDecoderReadLoopState.Action? {
        return IRFFDecoderReadLoopState.backpressureAction(
            audioSize: audioSize,
            videoPacketSize: videoPacketSize,
            paused: paused
        )
    }

    static func readLoopEOFAction(readFrameResult: Int32?) -> IRFFDecoderReadLoopState.Action? {
        return IRFFDecoderReadLoopState.eofAction(readFrameResult: readFrameResult)
    }

    static func readLoopPacketAction(streamIndex: Int32,
                                     videoTrackIndex: Int?,
                                     audioTrackIndex: Int?) -> IRFFDecoderReadLoopState.Action {
        return IRFFDecoderReadLoopState.packetAction(
            streamIndex: streamIndex,
            videoTrackIndex: videoTrackIndex,
            audioTrackIndex: audioTrackIndex
        )
    }

    static func displayLoopExitAction(closed: Bool,
                                      hasError: Bool) -> IRFFDecoderDisplayLoopState.Action? {
        return IRFFDecoderDisplayLoopState.exitAction(closed: closed, hasError: hasError)
    }

    static func displayLoopIdleAction(seeking: Bool,
                                      buffering: Bool,
                                      paused: Bool,
                                      hasCurrentFrame: Bool) -> IRFFDecoderDisplayLoopState.Action? {
        return IRFFDecoderDisplayLoopState.idleAction(
            seeking: seeking,
            buffering: buffering,
            paused: paused,
            hasCurrentFrame: hasCurrentFrame
        )
    }

    static func displayLoopFinishAction(endOfFile: Bool,
                                        videoDecoderEmpty: Bool) -> IRFFDecoderDisplayLoopState.Action? {
        return IRFFDecoderDisplayLoopState.finishAction(
            endOfFile: endOfFile,
            videoDecoderEmpty: videoDecoderEmpty
        )
    }

    static func displayLoopAudioSyncAction(currentFramePosition: TimeInterval?,
                                           currentFrameDuration: TimeInterval?,
                                           audioTimeClock: TimeInterval,
                                           fps: TimeInterval) -> IRFFDecoderDisplayLoopState.Action? {
        return IRFFDecoderDisplayLoopState.audioSyncAction(
            currentFramePosition: currentFramePosition,
            currentFrameDuration: currentFrameDuration,
            audioTimeClock: audioTimeClock,
            fps: fps
        )
    }

    static func shouldAcceptDisplayFrame(currentPosition: TimeInterval?,
                                         nextPosition: TimeInterval?) -> Bool {
        return IRFFDecoderDisplayLoopState.shouldAcceptFrame(
            currentPosition: currentPosition,
            nextPosition: nextPosition
        )
    }

    static func displayLoopStandaloneSleepAction(frameDuration: TimeInterval,
                                                 fps: TimeInterval) -> IRFFDecoderDisplayLoopState.Action? {
        return IRFFDecoderDisplayLoopState.standaloneSleepAction(
            frameDuration: frameDuration,
            fps: fps
        )
    }

    private func openFormatContext() {
        delegate?.decoderWillOpenInputStream(self)
        formatContext = IRFFFormatContext(contentURL: contentURL, videoFormat: videoFormat)
        formatContext?.delegate = self
        formatContext?.setupSync()
        if let formatError = formatContext?.error {
            error = formatError
            delegateErrorCallback()
            return
        }
        prepareToDecode = true
        delegate?.decoderDidPrepareToDecodeFrames(self)
        if let formatContext,
           let videoCodecContext = Self.videoCodecContext(from: formatContext) {
            videoDecoder = IRFFVideoDecoder(codecContext: videoCodecContext, timebase: formatContext.videoTimebase, fps: formatContext.videoFPS, delegate: self)
            videoDecoder?.source = self
            videoDecoder?.videoToolBoxEnable = hardwareDecoderEnable
        }
        if let formatContext,
           let audioCodecContext = Self.audioCodecContext(from: formatContext) {
            audioDecoder = IRFFAudioDecoder.decoder(codecContext: audioCodecContext, timebase: formatContext.audioTimebase, delegate: self)
        }
        setupReadPacketOperation()
    }

    private func readPacketThread() {
        videoDecoder?.flush()
        audioDecoder?.flush()
        reading = true
        var finished = false
        var packet = AVPacket()
        while !finished {
            let runtimeSnapshot = runtimeState.snapshot
            if Self.readLoopExitAction(
                closed: runtimeSnapshot.closed,
                hasError: runtimeSnapshot.hasError
            ) == .quit {
                IRFFRuntimeDebugOutput.write("read packet thread quit")
                break
            }
            if case let .completeSeek(transition)? = Self.readLoopSeekCompletionAction(
                seeking: runtimeSnapshot.seeking,
                progress: runtimeSnapshot.progress
            ) {
                guard let seekRequest = runtimeState.takePendingSeek() else {
                    continue
                }
                endOfFile = transition.endOfFile
                playbackFinished = transition.playbackFinished
                formatContext?.seekFile(withFFTimebase: seekRequest.target)
                buffering = transition.buffering
                if buffering {
                    bufferingStartTime = Date().timeIntervalSince1970
                }
                audioDecoder?.flush()
                videoDecoder?.flush()
                videoDecoder?.paused = transition.videoPaused
                videoDecoder?.endOfFile = transition.videoEndOfFile
                let seekCompletion = runtimeState.finishSeek(seekRequest)
                seekCompletion?(true)
                audioTimeClock = transition.audioTimeClock
                if transition.shouldClearFrames {
                    runtimeState.clearFrames()
                }
                updateBufferedDurationByVideo()
                updateBufferedDurationByAudio()
                continue
            }
            if selectAudioTrack {
                let selectionResult = formatContext?.selectAudioTrackIndexResult(selectAudioTrackIndex)
                let decoderWasReset = selectionResult?.didChangeTrack == true
                if decoderWasReset {
                    audioDecoder?.destroy()
                    if let formatContext,
                       let audioCodecContext = Self.audioCodecContext(from: formatContext) {
                        audioDecoder = IRFFAudioDecoder.decoder(codecContext: audioCodecContext, timebase: formatContext.audioTimebase, delegate: self)
                    }
                    let selectionSnapshot = runtimeState.snapshot
                    let selectionAction = Self.readLoopAudioTrackSelectionAction(
                        selectionPending: selectAudioTrack,
                        decoderWasReset: decoderWasReset,
                        hasAudioDecoder: audioDecoder != nil,
                        playbackFinished: selectionSnapshot.playbackFinished,
                        audioTimeClock: selectionSnapshot.audioTimeClock
                    )
                    if let seekTarget = selectionAction?.seekTarget {
                        seek(to: seekTarget)
                    }
                }
                selectAudioTrack = false
                selectAudioTrackIndex = 0
                continue
            }
            let size: Int = Int(audioDecoder?.size() ?? 0)
            let packetSize = (videoDecoder?.packetSize() ?? 0)
            if case let .sleep(interval)? = Self.readLoopBackpressureAction(
                audioSize: size,
                videoPacketSize: packetSize,
                paused: runtimeState.snapshot.paused
            ) {
                IRFFRuntimeDebugOutput.write("read thread sleep: \(interval)")
                Thread.sleep(forTimeInterval: interval)
                continue
            }
            let result = formatContext?.readFrame(&packet)
            if case let .finishEOF(transition)? = Self.readLoopEOFAction(readFrameResult: result) {
                IRFFRuntimeDebugOutput.write("read packet finished")
                endOfFile = transition.endOfFile
                videoDecoder?.endOfFile = transition.videoEndOfFile
                finished = transition.shouldFinishReadLoop
                if transition.shouldNotifyDelegate {
                    delegate?.decoderDidEndOfFile(self)
                }
                break
            }
            let packetAction = Self.readLoopPacketAction(
                streamIndex: packet.stream_index,
                videoTrackIndex: formatContext?.videoTrack?.index,
                audioTrackIndex: formatContext?.audioTrack?.index
            )
            switch packetAction {
            case .routePacket(.video):
                IRFFRuntimeDebugOutput.write("video: put packet")
                videoDecoder?.putPacket(packet)
                updateBufferedDurationByVideo()
            case .routePacket(.audio):
                IRFFRuntimeDebugOutput.write("audio: put packet")
                let audioPacketResult = audioDecoder?.putPacket(packet) ?? -1
                if audioPacketResult < 0 {
                    error = Self.audioPacketError(fromPacketResult: audioPacketResult)
                    delegateErrorCallback()
                    continue
                }
                updateBufferedDurationByAudio()
            case .routePacket(.ignored):
                break
            case .quit, .completeSeek(_), .sleep(_), .finishEOF(_):
                break
            }
        }
        reading = false
        checkBufferingStatus()
    }

    private func displayThread() {
        while true {
            let runtimeSnapshot = runtimeState.snapshot
            if Self.displayLoopExitAction(
                closed: runtimeSnapshot.closed,
                hasError: runtimeSnapshot.hasError
            ) == .quit {
                IRFFRuntimeDebugOutput.write("display thread quit")
                break
            }
            let displayedFrame = currentVideoFrame
            if case let .idleSleep(interval: sleepTime, replayCurrentFrame: replayCurrentFrame)? = Self.displayLoopIdleAction(
                seeking: runtimeSnapshot.seeking,
                buffering: runtimeSnapshot.buffering,
                paused: runtimeSnapshot.paused,
                hasCurrentFrame: displayedFrame != nil
            ) {
                if replayCurrentFrame, let currentFrame = displayedFrame {
                    videoOutput?.send?(videoFrame: currentFrame)
                }
                Thread.sleep(forTimeInterval: sleepTime)
                continue
            }
            if Self.displayLoopFinishAction(
                endOfFile: runtimeSnapshot.endOfFile,
                videoDecoderEmpty: videoDecoder?.empty() ?? true
            ) == .finish {
                IRFFRuntimeDebugOutput.write("display finished")
                break
            }
            if formatContext?.audioEnable == true {
                if let currentFrame = displayedFrame {
                    if case let .waitForAudio(interval: sleepTime)? = Self.displayLoopAudioSyncAction(
                        currentFramePosition: currentFrame.position,
                        currentFrameDuration: currentFrame.duration,
                        audioTimeClock: runtimeSnapshot.audioTimeClock,
                        fps: videoDecoder?.fps ?? 1
                    ) {
                        IRFFRuntimeDebugOutput.write("display thread sleep: \(sleepTime)")
                        Thread.sleep(forTimeInterval: sleepTime)
                        continue
                    }
                }
                if videoDecoder?.frameEmpty() ?? true {
                    updateBufferedDurationByVideo()
                }
                let newFrame = videoDecoder?.getFrameSync()
                if !Self.shouldAcceptDisplayFrame(
                    currentPosition: displayedFrame?.position,
                    nextPosition: newFrame?.position
                ) {
                    continue
                }
                currentVideoFrame = newFrame
                if let currentFrame = newFrame {
                    videoOutput?.send?(videoFrame: currentFrame)
                    updateProgressByVideo()
                    if runtimeSnapshot.endOfFile {
                        updateBufferedDurationByVideo()
                    }
                } else if runtimeSnapshot.endOfFile {
                    updateBufferedDurationByVideo()
                }
            } else {
                if videoDecoder?.frameEmpty() ?? true {
                    updateBufferedDurationByVideo()
                }
                let newFrame = videoDecoder?.getFrameSync()
                if !Self.shouldAcceptDisplayFrame(
                    currentPosition: displayedFrame?.position,
                    nextPosition: newFrame?.position
                ) {
                    continue
                }
                currentVideoFrame = newFrame
                if let currentFrame = newFrame {
                    videoOutput?.send?(videoFrame: currentFrame)
                    updateProgressByVideo()
                    if runtimeSnapshot.endOfFile {
                        updateBufferedDurationByVideo()
                    }
                    if case let .sleepAfterFrame(interval: sleepTime)? = Self.displayLoopStandaloneSleepAction(
                        frameDuration: currentFrame.duration,
                        fps: videoDecoder?.fps ?? 1
                    ) {
                        Thread.sleep(forTimeInterval: sleepTime)
                    }
                } else if runtimeSnapshot.endOfFile {
                    updateBufferedDurationByVideo()
                }
            }
        }
        checkBufferingStatus()
    }

    func pause() {
        paused = true
    }

    func resume() {
        paused = false
        if let seekTarget = Self.resumeSeekTarget(
            playbackFinished: runtimeState.snapshot.playbackFinished
        ) {
            seek(to: seekTarget)
        }
    }

    func seek(to time: TimeInterval, completeHandler: ((Bool) -> Void)? = nil) {
        let runtimeSnapshot = runtimeState.snapshot
        guard !runtimeSnapshot.closed else {
            completeHandler?(false)
            return
        }
        guard let preparation = Self.seekPreparation(
            requestedTime: time,
            seekEnabled: seekEnable,
            hasError: runtimeSnapshot.hasError,
            hasAudio: formatContext?.audioEnable == true,
            seekMinTime: 0,
            duration: duration,
            minBufferedDuration: runtimeSnapshot.minBufferedDuration
        ) else {
            completeHandler?(false)
            return
        }

        guard let seekResult = runtimeState.beginSeek(
            to: preparation.clampedTime,
            completion: completeHandler
        ) else {
            completeHandler?(false)
            return
        }
        seekResult.displacedCompletion?(false)
        if let progressChange = seekResult.progressChange {
            delegate?.decoder(
                self,
                didChangeValueOfProgress: progressChange.current
            )
        }
        videoDecoder?.paused = true
        if runtimeState.snapshot.endOfFile {
            setupReadPacketOperation()
        }
    }

    func fetchAudioFrame() -> IRFFAudioFrame? {
        let runtimeSnapshot = runtimeState.snapshot
        if !Self.shouldFetchAudioFrame(
            closed: runtimeSnapshot.closed,
            seeking: runtimeSnapshot.seeking,
            buffering: runtimeSnapshot.buffering,
            paused: runtimeSnapshot.paused,
            playbackFinished: runtimeSnapshot.playbackFinished,
            audioEnabled: formatContext?.audioEnable == true
        ) {
            return nil
        }
        if audioDecoder?.isEmpty() ?? true {
            updateBufferedDurationByAudio()
            return nil
        }
        guard let audioFrame = audioDecoder?.getFrameSync() else { return nil }
        currentAudioFrame = audioFrame
        if runtimeSnapshot.endOfFile {
            updateBufferedDurationByAudio()
        }
        updateProgressByAudio()
        audioTimeClock = audioFrame.position
        return audioFrame
    }

    func closeFile() {
        closeFileAsync(true)
    }

    private func closeFileAsync(_ async: Bool) {
        guard runtimeState.beginClose() else { return }
        let seekCompletions = runtimeState.cancelSeeks()
        seekCompletions.forEach { $0(false) }
        videoDecoder?.destroy()
        audioDecoder?.destroy()
        let cleanup = { [self] in
            ffmpegOperationQueue?.cancelAllOperations()
            ffmpegOperationQueue?.waitUntilAllOperationsAreFinished()
            closePropertyValue()
            formatContext?.destroy()
            closeOperation()
        }
        if async {
            DispatchQueue.global().async(execute: cleanup)
        } else {
            cleanup()
        }
    }

    private func closePropertyValue() {
        seeking = false
        buffering = false
        paused = false
        prepareToDecode = false
        endOfFile = false
        playbackFinished = false
        runtimeState.clearFrames()
        videoDecoder?.paused = false
        videoDecoder?.endOfFile = false
        selectAudioTrack = false
        selectAudioTrackIndex = 0
        bufferingStartTime = 0
    }

    private func closeOperation() {
        readPacketOperation = nil
        openFileOperation = nil
        displayOperation = nil
        decodeFrameOperation = nil
        ffmpegOperationQueue = nil
    }

    private func checkBufferingStatus() {
        let runtimeSnapshot = runtimeState.snapshot
        let transition = IRFFDecoderBufferingPolicy.statusTransition(
            buffering: runtimeSnapshot.buffering,
            bufferedDuration: runtimeSnapshot.bufferedDuration,
            endOfFile: runtimeSnapshot.endOfFile,
            isLiveStream: runtimeSnapshot.isLiveStream,
            minBufferedDuration: runtimeSnapshot.minBufferedDuration,
            bufferingStartTime: runtimeSnapshot.bufferingStartTime,
            currentTime: Date().timeIntervalSince1970
        )
        if let bufferingChange = runtimeState.applyBuffering(
            transition.buffering,
            startTime: transition.bufferingStartTime
        ) {
            delegate?.decoder(
                self,
                didChangeValueOfBuffering: bufferingChange.current
            )
        }
    }

    private func updateBufferedDurationByVideo() {
        if formatContext?.audioEnable == false {
            bufferedDuration = videoDecoder?.duration() ?? 0.0
        }
    }

    private func updateBufferedDurationByAudio() {
        if formatContext?.audioEnable == true {
            bufferedDuration = audioDecoder?.duration() ?? 0.0
        }
    }

    private func updateProgressByVideo() {
        if formatContext?.audioEnable == false && formatContext?.videoEnable == true {
            progress = currentVideoFrame?.position ?? 0
        }
    }

    private func updateProgressByAudio() {
        if formatContext?.audioEnable == true {
            progress = currentAudioFrame?.position ?? 0
        }
    }

    private func delegateErrorCallback() {
        let runtimeSnapshot = runtimeState.snapshot
        guard Self.shouldNotifyError(
            closed: runtimeSnapshot.closed,
            hasError: runtimeSnapshot.hasError
        ),
              let error = error else { return }
        delegate?.decoder(self, didError: error)
    }

    deinit {
        closeFileAsync(false)
    }
}

extension IRFFDecoder: IRFFFormatContextDelegate {
    public func formatContextNeedInterrupt(_ formatContext: IRFFFormatContext) -> Bool {
        return closed
    }
}

extension IRFFDecoder: IRFFAudioDecoderDelegate {
    func audioDecoder(_ audioDecoder: IRFFAudioDecoder, samplingRate: inout Float64) {
        samplingRate = audioOutput?.samplingRate ?? 0
    }

    func audioDecoder(_ audioDecoder: IRFFAudioDecoder, channelCount: inout UInt32) {
        channelCount = audioOutput?.numberOfChannels ?? 0
    }
}

extension IRFFDecoder: IRFFVideoDecoderDelegate {
    func videoDecoderNeedUpdateBufferedDuration(_ videoDecoder: IRFFVideoDecoder) {
        updateBufferedDurationByVideo()
    }

    func videoDecoderNeedCheckBufferingStatus(_ videoDecoder: IRFFVideoDecoder) {
        checkBufferingStatus()
    }

    func videoDecoder(_ videoDecoder: IRFFVideoDecoder, didError error: Error) {
        self.error = error
        delegateErrorCallback()
    }
}

extension IRFFDecoder: IRFFVideoDecoderDataSource {

    public func shouldHandle(_ videoDecoder: IRFFVideoDecoderInfo, decodeFrame packet: AVPacket) -> Bool {
        return source?.shouldHandle(videoDecoder, decodeFrame: packet) ?? false
    }

    public func videoDecoder(_ videoDecoder: IRFFVideoDecoderInfo, decodeFrame packet: AVPacket) -> IRFFVideoFrame? {
        return source?.videoDecoder(videoDecoder, decodeFrame: packet)
    }
}

extension IRFFDecoder: IRFFDecoderVideoOutput {
    public func send(videoFrame: IRFFVideoFrame) {
        self.videoDecoder?.send(videoFrame: videoFrame)
    }
}
