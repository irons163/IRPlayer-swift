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

    private(set) var error: Error?
    private(set) var contentURL: URL
    private(set) var videoFormat: IRVideoFormat
    private(set) var progress: TimeInterval = 0 {
        didSet {
            guard progress != oldValue else {
                return
            }
            delegate?.decoder(self, didChangeValueOfProgress: progress)
        }
    }
    private(set) var bufferedDuration: TimeInterval = 0 {
        didSet {
            guard bufferedDuration != oldValue else {
                return
            }
            let transition = Self.bufferedDurationTransition(bufferedDuration: bufferedDuration, endOfFile: endOfFile)
            bufferedDuration = transition.bufferedDuration
            delegate?.decoder(self, didChangeValueOfBufferedDuration: bufferedDuration)
            if transition.shouldFinishPlayback {
                playbackFinished = true
            }
            checkBufferingStatus()
        }
    }
    private(set) var buffering: Bool = false {
        didSet {
            guard buffering != oldValue else {
                return
            }
            delegate?.decoder(self, didChangeValueOfBuffering: buffering)
        }
    }
    private(set) var playbackFinished: Bool = false {
        didSet {
            guard playbackFinished != oldValue,
                  playbackFinished else {
                return
            }
            progress = duration
            delegate?.decoderDidPlaybackFinished(self)
        }
    }
    private(set) var closed: Bool = false
    private(set) var endOfFile: Bool = false
    private(set) var paused: Bool = false
    private(set) var seeking: Bool = false
    private(set) var prepareToDecode: Bool = false

    private var seekToTime: TimeInterval = 0
    private var seekMinTime: TimeInterval = 0
    private var seekCompleteHandler: ((Bool) -> Void)?
    private var selectAudioTrack = false
    private var selectAudioTrackIndex = 0
    private var currentVideoFrame: IRFFVideoFrame?
    private var currentAudioFrame: IRFFAudioFrame?

    private(set) var audioTimeClock: TimeInterval = 0

    var hardwareDecoderEnable: Bool = true
    var minBufferedDuration: TimeInterval = 0
    var reading = false
    var isLiveStream: Bool = false

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

    // Buffering timeout tracking
    private var bufferingStartTime: TimeInterval = 0
    private let bufferingMaxDuration: TimeInterval = 2.0 // Maximum time to wait for buffering before forcing play
    private let bufferingMinimumThreshold: TimeInterval = 0.3 // Minimum buffered duration before playing on poor network
    private let liveStreamBufferingMaxDuration: TimeInterval = 1.0 // Shorter timeout for live streams

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
        setupFFmpeg()
    }

    private func setupFFmpeg() {
        DispatchQueue.once(token: "ffmpeg.setup") {
            av_log_set_callback { context, level, format, args in
                guard let format = format,
                      let formatString = String.init(utf8String: format),
                      let args = args else {
                    return
                }
                let message = NSString(format: formatString, arguments: args) as String
                switch level {
                default:
                    IRFFRuntimeDebugOutput.write(message.trimmingCharacters(in: .newlines))
                    break;
                }
            }
//            av_register_all()
            avformat_network_init()
        }
    }

    func open() {
        setupOperationQueue()
    }

    private func setupOperationQueue() {
        ffmpegOperationQueue?.maxConcurrentOperationCount = 3
        ffmpegOperationQueue?.qualityOfService = .userInteractive
        setupOpenFileOperation()
    }

    private func setupOpenFileOperation() {
        let operation = BlockOperation { [weak self] in
            self?.openFormatContext()
        }
        operation.queuePriority = .veryHigh
        operation.qualityOfService = .userInteractive
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
            operation.qualityOfService = .userInteractive
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
                operation.qualityOfService = .userInteractive
                Self.addDependency(openFileOperation, to: operation)
                decodeFrameOperation = operation
                Self.enqueue(operation, on: ffmpegOperationQueue)
            }
            if Self.needsScheduling(displayOperation) {
                let operation = BlockOperation { [weak self] in
                    self?.displayThread()
                }
                operation.queuePriority = .veryHigh
                operation.qualityOfService = .userInteractive
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
            if closed || error != nil {
                IRFFRuntimeDebugOutput.write("read packet thread quit")
                break
            }
            if let transition = Self.seekCompletionTransition(seeking: seeking, progress: progress) {
                endOfFile = transition.endOfFile
                playbackFinished = transition.playbackFinished
                formatContext?.seekFile(withFFTimebase: seekToTime)
                buffering = transition.buffering
                if buffering {
                    bufferingStartTime = Date().timeIntervalSince1970
                }
                audioDecoder?.flush()
                videoDecoder?.flush()
                videoDecoder?.paused = transition.videoPaused
                videoDecoder?.endOfFile = transition.videoEndOfFile
                seeking = false
                seekToTime = transition.seekToTime
                if let handler = seekCompleteHandler {
                    handler(true)
                    seekCompleteHandler = nil
                }
                audioTimeClock = transition.audioTimeClock
                if transition.shouldClearFrames {
                    currentVideoFrame = nil
                    currentAudioFrame = nil
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
                    if let seekTarget = Self.audioTrackSelectionSeekTarget(
                        selectionPending: selectAudioTrack,
                        decoderWasReset: decoderWasReset,
                        hasAudioDecoder: audioDecoder != nil,
                        playbackFinished: playbackFinished,
                        audioTimeClock: audioTimeClock
                    ) {
                        seek(to: seekTarget)
                    }
                }
                selectAudioTrack = false
                selectAudioTrackIndex = 0
                continue
            }
            let size: Int = Int(audioDecoder?.size() ?? 0)
            let packetSize = (videoDecoder?.packetSize() ?? 0)
            if let interval = Self.packetBufferBackpressureSleepInterval(audioSize: size,
                                                                         videoPacketSize: packetSize,
                                                                         paused: paused) {
                IRFFRuntimeDebugOutput.write("read thread sleep: \(interval)")
                Thread.sleep(forTimeInterval: interval)
                continue
            }
            let result = formatContext?.readFrame(&packet)
            if let transition = Self.readPacketEOFTransition(readFrameResult: result) {
                IRFFRuntimeDebugOutput.write("read packet finished")
                endOfFile = transition.endOfFile
                videoDecoder?.endOfFile = transition.videoEndOfFile
                finished = transition.shouldFinishReadLoop
                if transition.shouldNotifyDelegate {
                    delegate?.decoderDidEndOfFile(self)
                }
                break
            }
            switch Self.packetRoute(
                streamIndex: packet.stream_index,
                videoTrackIndex: formatContext?.videoTrack?.index,
                audioTrackIndex: formatContext?.audioTrack?.index
            ) {
            case .video:
                IRFFRuntimeDebugOutput.write("video: put packet")
                videoDecoder?.putPacket(packet)
                updateBufferedDurationByVideo()
            case .audio:
                IRFFRuntimeDebugOutput.write("audio: put packet")
                let audioPacketResult = audioDecoder?.putPacket(packet) ?? -1
                if audioPacketResult < 0 {
                    error = Self.audioPacketError(fromPacketResult: audioPacketResult)
                    delegateErrorCallback()
                    continue
                }
                updateBufferedDurationByAudio()
            case .ignored:
                break
            }
        }
        reading = false
        checkBufferingStatus()
    }

    private func displayThread() {
        while true {
            if closed || error != nil {
                IRFFRuntimeDebugOutput.write("display thread quit")
                break
            }
            if let sleepTime = Self.displayIdleSleepInterval(
                seeking: seeking,
                buffering: buffering,
                paused: paused,
                hasCurrentFrame: currentVideoFrame != nil
            ) {
                if paused, !seeking, !buffering, let currentFrame = currentVideoFrame {
                    videoOutput?.send?(videoFrame: currentFrame)
                }
                Thread.sleep(forTimeInterval: sleepTime)
                continue
            }
            if Self.shouldFinishDisplay(endOfFile: endOfFile, videoDecoderEmpty: videoDecoder?.empty() ?? true) {
                IRFFRuntimeDebugOutput.write("display finished")
                break
            }
            if formatContext?.audioEnable == true {
                let audioTimeClock = self.audioTimeClock
                if let currentFrame = currentVideoFrame {
                    if let sleepTime = Self.audioSyncedVideoSleepDuration(
                        framePosition: currentFrame.position,
                        frameDuration: currentFrame.duration,
                        audioTimeClock: audioTimeClock,
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
                if !Self.shouldAcceptVideoFrame(currentPosition: currentVideoFrame?.position,
                                                nextPosition: newFrame?.position) {
                    continue
                }
                currentVideoFrame = newFrame
                if let currentFrame = currentVideoFrame {
                    videoOutput?.send?(videoFrame: currentFrame)
                    updateProgressByVideo()
                    if endOfFile {
                        updateBufferedDurationByVideo()
                    }
                } else if endOfFile {
                    updateBufferedDurationByVideo()
                }
            } else {
                if videoDecoder?.frameEmpty() ?? true {
                    updateBufferedDurationByVideo()
                }
                let newFrame = videoDecoder?.getFrameSync()
                if !Self.shouldAcceptVideoFrame(currentPosition: currentVideoFrame?.position,
                                                nextPosition: newFrame?.position) {
                    continue
                }
                currentVideoFrame = newFrame
                if let currentFrame = currentVideoFrame {
                    videoOutput?.send?(videoFrame: currentFrame)
                    updateProgressByVideo()
                    if endOfFile {
                        updateBufferedDurationByVideo()
                    }
                    if let sleepTime = Self.standaloneVideoSleepDuration(frameDuration: currentFrame.duration, fps: videoDecoder?.fps ?? 1) {
                        Thread.sleep(forTimeInterval: sleepTime)
                    }
                } else if endOfFile {
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
        if let seekTarget = Self.resumeSeekTarget(playbackFinished: playbackFinished) {
            seek(to: seekTarget)
        }
    }

    func seek(to time: TimeInterval, completeHandler: ((Bool) -> Void)? = nil) {
        guard let preparation = Self.seekPreparation(
            requestedTime: time,
            seekEnabled: seekEnable,
            hasError: error != nil,
            hasAudio: formatContext?.audioEnable == true,
            seekMinTime: seekMinTime,
            duration: duration,
            minBufferedDuration: minBufferedDuration
        ) else {
            completeHandler?(false)
            return
        }

        seekToTime = preparation.clampedTime
        self.progress = seekToTime
        self.seekCompleteHandler = completeHandler
        self.seeking = true
        videoDecoder?.paused = true
        if endOfFile {
            setupReadPacketOperation()
        }
    }

    func fetchAudioFrame() -> IRFFAudioFrame? {
        if !Self.shouldFetchAudioFrame(closed: closed,
                                       seeking: seeking,
                                       buffering: buffering,
                                       paused: paused,
                                       playbackFinished: playbackFinished,
                                       audioEnabled: formatContext?.audioEnable == true) {
            return nil
        }
        if audioDecoder?.isEmpty() ?? true {
            updateBufferedDurationByAudio()
            return nil
        }
        currentAudioFrame = audioDecoder?.getFrameSync()
        if currentAudioFrame == nil { return nil }
        if endOfFile {
            updateBufferedDurationByAudio()
        }
        updateProgressByAudio()
        audioTimeClock = currentAudioFrame?.position ?? 0
        return currentAudioFrame
    }

    func closeFile() {
        closeFileAsync(true)
    }

    private func closeFileAsync(_ async: Bool) {
        if closed { return }
        closed = true
        videoDecoder?.destroy()
        audioDecoder?.destroy()
        if async {
            DispatchQueue.global().async { [weak self] in
                self?.ffmpegOperationQueue?.cancelAllOperations()
                self?.ffmpegOperationQueue?.waitUntilAllOperationsAreFinished()
                self?.closePropertyValue()
                self?.formatContext?.destroy()
                self?.closeOperation()
            }
        } else {
            ffmpegOperationQueue?.cancelAllOperations()
            ffmpegOperationQueue?.waitUntilAllOperationsAreFinished()
            closePropertyValue()
            formatContext?.destroy()
            closeOperation()
        }
    }

    private func closePropertyValue() {
        seeking = false
        buffering = false
        paused = false
        prepareToDecode = false
        endOfFile = false
        playbackFinished = false
        currentVideoFrame = nil
        currentAudioFrame = nil
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
        let nextBuffering = IRPlaybackTimePolicy.bufferingState(
            currentlyBuffering: buffering,
            bufferedDuration: bufferedDuration,
            minBufferedDuration: minBufferedDuration,
            endOfFile: endOfFile,
            bufferingElapsed: Date().timeIntervalSince1970 - bufferingStartTime,
            bufferingMaxDuration: bufferingMaxDuration,
            bufferingMinimumThreshold: bufferingMinimumThreshold,
            liveStreamBufferingMaxDuration: liveStreamBufferingMaxDuration,
            isLiveStream: isLiveStream
        )
        if nextBuffering && !buffering {
            bufferingStartTime = Date().timeIntervalSince1970
        } else if !nextBuffering {
            bufferingStartTime = 0
        }
        buffering = nextBuffering
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
        if let error = error {
            delegate?.decoder(self, didError: error)
        }
    }

    deinit {
        closeFileAsync(false)
    }
}

// MARK: - Extensions and Utility Functions

extension DispatchQueue {
    private static var onceTracker = [String]()

    class func once(token: String, block: () -> Void) {
        objc_sync_enter(self)
        defer { objc_sync_exit(self) }

        if onceTracker.contains(token) {
            return
        }
        onceTracker.append(token)
        block()
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
