//
//  IRFFDecoder.swift
//  IRPlayer-swift
//
//  Created by irons on 2024/7/11.
//

import Foundation
import CoreGraphics
import AVFoundation
#if SWIFT_PACKAGE || DEBUG
internal import IRFFMpeg
internal import IRPlayerObjc
#else
@_implementationOnly import IRFFMpeg
@_implementationOnly import IRPlayerObjc
#endif

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
    /// Attempts a bounded, non-blocking frame delivery. A `false` result means
    /// the output rejected and reclaimed the frame.
    @objc optional func trySend(
        videoFrame frame: IRFFVideoFrame
    ) -> Bool
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

    private let collaborators:
        IRFFDecoderCollaboratorSession

    var delegate: IRFFDecoderDelegate? {
        get { collaborators.snapshot.delegate }
        set { collaborators.updateDelegate(newValue) }
    }

    var source: IRFFVideoDecoderDataSource? {
        get { collaborators.snapshot.source }
        set {
            collaborators.updateSource(newValue) { [session] source in
                session.updateVideoDecoderSource(source)
            }
        }
    }

    var videoOutput: IRFFDecoderVideoOutput? {
        get { collaborators.snapshot.videoOutput }
        set { collaborators.updateVideoOutput(newValue) }
    }

    var audioOutput: IRFFDecoderAudioOutput? {
        get { collaborators.snapshot.audioOutput }
        set { collaborators.updateAudioOutput(newValue) }
    }

    private let session = IRFFDecoderSession()
    private let runtimeState = IRFFDecoderRuntimeState()

    var error: Error? {
        runtimeState.error
    }
    private(set) var contentURL: URL
    private(set) var videoFormat: IRVideoFormat
    private(set) var contentHeaders:
        [String: String]
    private(set) var progress: TimeInterval {
        get { runtimeState.snapshot.progress }
        set {
            guard let normalizedProgress =
                    Self.normalizedProgress(
                        newValue,
                        duration: duration
                    ),
                  let change =
                    runtimeState.setProgress(
                        normalizedProgress
                    ) else {
                return
            }
            notifyDelegate {
                $0.decoder(
                    self,
                    didChangeValueOfProgress: change.current
                )
            }
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
            notifyDelegate {
                $0.decoder(
                    self,
                    didChangeValueOfBufferedDuration: change.current
                )
            }
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
            notifyDelegate {
                $0.decoder(
                    self,
                    didChangeValueOfBuffering: change.current
                )
            }
        }
    }
    private(set) var playbackFinished: Bool {
        get { runtimeState.snapshot.playbackFinished }
        set {
            guard let change = runtimeState.setPlaybackFinished(newValue),
                  change.current else { return }
            progress = duration
            notifyDelegate {
                $0.decoderDidPlaybackFinished(self)
            }
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

    private var currentVideoFrame: IRFFVideoFrame? {
        runtimeState.currentVideoFrame
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
        session.withResources(default: false) {
            $0.formatContext?.videoEnable ?? false
        }
    }

    var audioEnable: Bool {
        session.withResources(default: false) {
            $0.formatContext?.audioEnable ?? false
        }
    }

    var videoTrack: IRFFTrack? {
        session.withResources(default: nil) {
            $0.formatContext?.videoTrack
        }
    }

    var audioTrack: IRFFTrack? {
        session.withResources(default: nil) {
            $0.formatContext?.audioTrack
        }
    }

    var videoTracks: [IRFFTrack] {
        session.withResources(default: []) {
            $0.formatContext?.videoTracks ?? []
        }
    }

    var audioTracks: [IRFFTrack] {
        session.withResources(default: []) {
            $0.formatContext?.audioTracks ?? []
        }
    }

    var metadata: [String: Any] {
        session.withResources(default: [:]) {
            $0.formatContext?.metadata as? [String: Any] ?? [:]
        }
    }

    var presentationSize: CGSize {
        session.withResources(default: .zero) {
            $0.formatContext?.videoPresentationSize ?? .zero
        }
    }

    var aspect: CGFloat {
        session.withResources(default: 0) {
            $0.formatContext?.videoAspect ?? 0
        }
    }

    private var bufferingStartTime: TimeInterval {
        get { runtimeState.snapshot.bufferingStartTime }
        set { runtimeState.setBufferingStartTime(newValue) }
    }

    var duration: TimeInterval {
        session.withResources(default: 0) {
            $0.formatContext?.duration ?? 0
        }
    }

    var bitrate: TimeInterval {
        session.withResources(default: 0) {
            $0.formatContext?.bitrate ?? 0
        }
    }

    var seekEnable: Bool {
        return duration > 0
    }

    init(
        contentURL: URL,
        videoFormat: IRVideoFormat,
        contentHeaders:
            [String: String] = [:],
        videoOutput: IRFFDecoderVideoOutput?,
        audioOutput: IRFFDecoderAudioOutput?
    ) {
        self.contentURL = contentURL
        self.videoFormat = videoFormat
        self.contentHeaders =
            contentHeaders
        self.collaborators = IRFFDecoderCollaboratorSession(
            configuration: .init(
                delegate: nil,
                source: nil,
                videoOutput: videoOutput,
                audioOutput: audioOutput
            )
        )
        super.init()
        IRFFmpegBootstrap.initializeIfNeeded()
    }

    var collaboratorDiagnostics:
        IRFFDecoderCollaboratorSession.Diagnostics {
        collaborators.diagnostics
    }

    @discardableResult
    func installCollaborators(
        delegate: IRFFDecoderDelegate?,
        source: IRFFVideoDecoderDataSource?,
        videoOutput: IRFFDecoderVideoOutput?,
        audioOutput: IRFFDecoderAudioOutput?
    ) -> Bool {
        collaborators.install(
            .init(
                delegate: delegate,
                source: source,
                videoOutput: videoOutput,
                audioOutput: audioOutput
            )
        ) { [session] snapshot in
            session.updateVideoDecoderSource(snapshot.source)
        }
    }

    @discardableResult
    func installDelegatePreservingCollaborators(
        _ delegate: IRFFDecoderDelegate
    ) -> Bool {
        collaborators.installDelegatePreservingCollaborators(
            delegate
        ) { [session] snapshot in
            session.updateVideoDecoderSource(snapshot.source)
        }
    }

    @discardableResult
    func revokeCollaborators() -> Bool {
        collaborators.revoke { [session] in
            session.updateVideoDecoderSource(nil)
        }
    }

    private func notifyDelegate(
        _ notification: (IRFFDecoderDelegate) -> Void
    ) {
        collaborators.withDelegate(default: ()) {
            notification($0)
        }
    }

    func open() {
        session.start { [weak self] in
            self?.openFormatContext()
        }
    }

    private func scheduleWorkers(
        deferIfRunning: Bool = false,
        includeRead: Bool = true
    ) {
        if error != nil {
            delegateErrorCallback()
            return
        }
        let resources = session.workerResources
        let includeAudio =
            resources.formatContext?.audioEnable == true &&
            resources.audioDecoder != nil
        let generation =
            runtimeState.snapshot.decodeGeneration
        session.scheduleWorkers(
            includeRead: includeRead,
            includeVideo: resources.formatContext?.videoEnable == true,
            read: { [weak self] in
                self?.readPacketThread()
            },
            decode: { [weak self] in
                self?.session.workerResources
                    .videoDecoder?
                    .decodeFrameThread(
                        generation: generation
                    )
            },
            display: { [weak self] in
                self?.displayThread(
                    generation: generation
                )
            },
            deferIfRunning: deferIfRunning
        )
        if includeAudio {
            session.scheduleAudioMonitor { [weak self] in
                self?.audioMonitoringThread()
            }
        }
    }

    static func videoCodecContext(
        from formatContext: IRFFFormatContext?
    ) -> UnsafeMutablePointer<AVCodecContext>? {
        guard formatContext?.videoEnable == true else {
            return nil
        }
        return formatContext?.videoCodecContext
    }

    static func audioCodecContext(
        from formatContext: IRFFFormatContext?
    ) -> UnsafeMutablePointer<AVCodecContext>? {
        guard formatContext?.audioEnable == true else {
            return nil
        }
        return formatContext?.audioCodecContext
    }

    static func audioPacketError(fromPacketResult packetResult: Int) -> NSError? {
        guard packetResult < 0 else { return nil }
        guard let result = Int32(exactly: packetResult) else {
            return NSError(
                domain:
                    "ffmpeg code outside Int32: \(packetResult)",
                code:
                    IRFFDecoderErrorCode
                        .codecAudioSendPacket.rawValue,
                userInfo: nil
            )
        }
        return IRFFCheckErrorCode(
            result,
            errorCode:
                IRFFDecoderErrorCode
                    .codecAudioSendPacket.rawValue
        )
    }

    static func audioPumpFailureError(
        code: Int32
    ) -> NSError {
        var userInfo: [String: Any] = [
            NSLocalizedDescriptionKey:
                "The audio decoder could not make progress."
        ]
        if let underlyingError = IRFFCheckError(code) {
            userInfo[NSUnderlyingErrorKey] =
                underlyingError
        }
        return NSError(
            domain: "IRFFAudioDecoder",
            code: Int(
                IRFFDecoderErrorCode
                    .codecAudioSendPacket.rawValue
            ),
            userInfo: userInfo
        )
    }

    static func audioUnexpectedEndOfStreamError()
        -> NSError {
        NSError(
            domain: "IRFFAudioDecoder",
            code: Int(
                IRFFDecoderErrorCode
                    .codecAudioSendPacket.rawValue
            ),
            userInfo: [
                NSLocalizedDescriptionKey:
                    "The audio decoder ended before the input stream."
            ]
        )
    }

    static func decodeAdmissionSleepInterval(
        paused: Bool
    ) -> TimeInterval {
        paused ? 0.05 : 0.002
    }

    static func bufferedDurationTransition(bufferedDuration: TimeInterval, endOfFile: Bool) -> BufferedDurationTransition {
        let normalizedDuration =
            bufferedDuration.isFinite &&
            bufferedDuration > 0.000001
            ? bufferedDuration
            : 0
        return BufferedDurationTransition(
            bufferedDuration: normalizedDuration,
            shouldFinishPlayback:
                normalizedDuration <= 0 && endOfFile
        )
    }

    static func normalizedProgress(
        _ progress: TimeInterval,
        duration: TimeInterval
    ) -> TimeInterval? {
        guard progress.isFinite else {
            return nil
        }
        let lowerBounded = max(0, progress)
        guard duration.isFinite,
              duration > 0 else {
            return lowerBounded
        }
        return min(lowerBounded, duration)
    }

    static func packetBufferBackpressureSleepInterval(audioSize: Int,
                                                      videoPacketSize: Int,
                                                      maxBufferSize: Int = 20 * 1024 * 1024,
                                                      paused: Bool) -> TimeInterval? {
        guard audioSize >= 0,
              videoPacketSize >= 0,
              maxBufferSize > 0 else {
            return nil
        }
        if audioSize >= maxBufferSize ||
            videoPacketSize >= maxBufferSize ||
            videoPacketSize >= maxBufferSize - audioSize {
            return paused ? 0.5 : 0.1
        }
        return nil
    }

    static func seekPreparation(requestedTime: TimeInterval,
                                seekEnabled: Bool,
                                hasError: Bool,
                                hasAudio: Bool,
                                seekMinTime: TimeInterval,
                                duration: TimeInterval,
                                minBufferedDuration: TimeInterval) -> SeekPreparation? {
        guard seekEnabled,
              !hasError,
              requestedTime.isFinite,
              seekMinTime.isFinite,
              duration.isFinite,
              minBufferedDuration.isFinite,
              seekMinTime >= 0,
              duration >= 0,
              minBufferedDuration >= 0 else {
            return nil
        }

        let tailBufferDuration: TimeInterval = hasAudio ? 8 : 15
        let reservedDuration =
            minBufferedDuration + tailBufferDuration
        let rawSeekMaxTime = duration - reservedDuration
        guard reservedDuration.isFinite,
              rawSeekMaxTime.isFinite else {
            return nil
        }

        let seekMaxTime = max(rawSeekMaxTime, seekMinTime)
        return SeekPreparation(
            clampedTime:
                min(max(requestedTime, seekMinTime), seekMaxTime)
        )
    }

    static func audioSyncedVideoSleepDuration(framePosition: TimeInterval,
                                              frameDuration: TimeInterval,
                                              audioTimeClock: TimeInterval,
                                              fps: TimeInterval) -> TimeInterval? {
        guard framePosition.isFinite,
              audioTimeClock.isFinite else {
            return nil
        }

        let sleepTime: TimeInterval
        if framePosition >= audioTimeClock {
            guard let frameInterval =
                    frameInterval(forFPS: fps) else {
                return nil
            }
            sleepTime = frameInterval / 2
        } else {
            guard frameDuration.isFinite,
                  frameDuration > 0 else {
                return nil
            }
            let frameEnd = framePosition + frameDuration
            guard frameEnd.isFinite,
                  frameEnd >= audioTimeClock else {
                return nil
            }
            sleepTime = frameDuration / 2
        }
        guard sleepTime.isFinite, sleepTime > 0 else {
            return nil
        }
        return max(0.015, sleepTime)
    }

    static func standaloneVideoSleepDuration(frameDuration: TimeInterval, fps: TimeInterval) -> TimeInterval? {
        if frameDuration.isFinite,
           frameDuration >= 0.0001 {
            return frameDuration
        }
        return frameInterval(forFPS: fps)
    }

    static func videoFrameOrderingPosition(_ position: TimeInterval?) -> TimeInterval? {
        guard let position else { return 0 }
        return position.isFinite ? position : nil
    }

    static func shouldAcceptVideoFrame(currentPosition: TimeInterval?, nextPosition: TimeInterval?) -> Bool {
        guard let nextPosition =
                videoFrameOrderingPosition(nextPosition) else {
            return false
        }
        guard let currentPosition =
                videoFrameOrderingPosition(currentPosition) else {
            return true
        }
        return currentPosition <= nextPosition
    }

    static func shouldFetchAudioFrame(closed: Bool,
                                      hasError: Bool,
                                      seeking: Bool,
                                      buffering: Bool,
                                      paused: Bool,
                                      playbackFinished: Bool,
                                      audioEnabled: Bool) -> Bool {
        return !closed &&
            !hasError &&
            !seeking &&
            !buffering &&
            !paused &&
            !playbackFinished &&
            audioEnabled
    }

    static func resumeSeekTarget(playbackFinished: Bool) -> TimeInterval? {
        return playbackFinished ? 0 : nil
    }

    static func seekCompletionTransition(seeking: Bool, progress: TimeInterval) -> SeekCompletionTransition? {
        guard seeking, progress.isFinite else { return nil }
        return SeekCompletionTransition(
            endOfFile: false,
            playbackFinished: false,
            buffering: true,
            videoPaused: false,
            videoEndOfFile: false,
            seekToTime: 0,
            audioTimeClock: progress,
            shouldClearFrames: true
        )
    }

    static func readPacketEOFTransition(readFrameResult: Int32?) -> ReadPacketEOFTransition? {
        guard readFrameResult ==
                IR_AVERROR_EOF else {
            return nil
        }
        return ReadPacketEOFTransition(
            endOfFile: true,
            videoEndOfFile: true,
            shouldFinishReadLoop: true,
            shouldNotifyDelegate: true
        )
    }

    static func packetRoute(streamIndex: Int32, videoTrackIndex: Int?, audioTrackIndex: Int?) -> PacketRoute {
        if let videoTrackIndex,
           let videoStreamIndex =
                Int32(exactly: videoTrackIndex),
           streamIndex == videoStreamIndex {
            return .video
        }
        if let audioTrackIndex,
           let audioStreamIndex =
                Int32(exactly: audioTrackIndex),
           streamIndex == audioStreamIndex {
            return .audio
        }
        return .ignored
    }

    static func displayIdleSleepInterval(seeking: Bool,
                                         buffering: Bool,
                                         paused: Bool,
                                         hasCurrentFrame: Bool) -> TimeInterval? {
        if seeking || buffering {
            return 0.01
        }
        if paused, hasCurrentFrame {
            return 0.03
        }
        return nil
    }

    static func shouldFinishDisplay(endOfFile: Bool, videoDecoderEmpty: Bool) -> Bool {
        return endOfFile && videoDecoderEmpty
    }

    static func bufferingStatusTransition(
        buffering: Bool,
        bufferedDuration: TimeInterval,
        endOfFile: Bool,
        isLiveStream: Bool,
        minBufferedDuration: TimeInterval,
        bufferingStartTime: TimeInterval,
        currentTime: TimeInterval
    ) -> BufferingStatusTransition {
        let unchanged = BufferingStatusTransition(
            buffering: buffering,
            bufferingStartTime: bufferingStartTime
        )
        guard bufferedDuration.isFinite,
              minBufferedDuration.isFinite,
              bufferingStartTime.isFinite,
              currentTime.isFinite,
              bufferedDuration >= 0,
              minBufferedDuration >= 0 else {
            return unchanged
        }

        if buffering {
            let elapsed =
                currentTime - bufferingStartTime
            guard elapsed.isFinite else {
                return unchanged
            }
            let maxDuration: TimeInterval =
                isLiveStream ? 1 : 2
            let minimumThreshold: TimeInterval =
                isLiveStream ? 0.2 : 0.3
            let requiredDuration =
                isLiveStream ? 0 : minBufferedDuration
            if bufferedDuration >= requiredDuration ||
                endOfFile ||
                (
                    elapsed > maxDuration &&
                    bufferedDuration >= minimumThreshold
                ) {
                return BufferingStatusTransition(
                    buffering: false,
                    bufferingStartTime: 0
                )
            }
        } else {
            let entryThreshold: TimeInterval =
                isLiveStream ? 0.05 : 0.2
            if bufferedDuration <= entryThreshold,
               !endOfFile {
                return BufferingStatusTransition(
                    buffering: true,
                    bufferingStartTime: currentTime
                )
            }
        }
        return unchanged
    }

    private static func frameInterval(
        forFPS fps: TimeInterval
    ) -> TimeInterval? {
        guard fps.isFinite, fps > 0 else { return nil }
        let interval = 1 / fps
        return interval.isFinite && interval > 0
            ? interval
            : nil
    }

    static func readLoopExitAction(closed: Bool, hasError: Bool) -> IRFFDecoderReadLoopState.Action? {
        return IRFFDecoderReadLoopState.exitAction(closed: closed, hasError: hasError)
    }

    static func readLoopSeekCompletionAction(seeking: Bool,
                                             progress: TimeInterval) -> IRFFDecoderReadLoopState.Action? {
        return IRFFDecoderReadLoopState.seekCompletionAction(seeking: seeking, progress: progress)
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

    static func readLoopReadAction(
        readFrameResult: Int32,
        retryAttempt: Int
    ) -> IRFFDecoderReadLoopState.Action? {
        IRFFDecoderReadLoopState.readAction(
            readFrameResult:
                readFrameResult,
            retryAttempt: retryAttempt
        )
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

    static func admitDisplayFrame(
        _ frame: IRFFVideoFrame?,
        after currentPosition:
            TimeInterval?
    ) -> Bool {
        guard shouldAcceptDisplayFrame(
            currentPosition: currentPosition,
            nextPosition: frame?.position
        ) else {
            frame?.cancel()
            return false
        }
        return true
    }

    static func retainDeliveredDisplayFrame(
        _ frame: IRFFVideoFrame,
        delivered: Bool
    ) -> IRFFVideoFrame? {
        guard delivered else {
            frame.cancel()
            return nil
        }
        return frame
    }

    static func displayLoopStandaloneSleepAction(frameDuration: TimeInterval,
                                                 fps: TimeInterval) -> IRFFDecoderDisplayLoopState.Action? {
        return IRFFDecoderDisplayLoopState.standaloneSleepAction(
            frameDuration: frameDuration,
            fps: fps
        )
    }

    private func openFormatContext() {
        let openSnapshot =
            runtimeState.snapshot
        guard !openSnapshot.closed else {
            return
        }
        let openGeneration =
            openSnapshot.decodeGeneration
        notifyDelegate {
            $0.decoderWillOpenInputStream(self)
        }
        guard !closed else { return }

        let formatContext = IRFFFormatContext(
            contentURL: contentURL,
            videoFormat: videoFormat,
            contentHeaders: contentHeaders
        )
        formatContext.delegate = self
        guard session.installFormatContext(formatContext) else {
            formatContext.destroy()
            return
        }

        formatContext.setupSync()
        if let formatError = formatContext.error {
            session.markOpenFailed()
            _ = runtimeState.commitDecodeError(
                formatError,
                generation: openGeneration,
                notification: {
                    delegateErrorCallback()
                }
            )
            return
        }
        guard !closed else { return }

        if let videoCodecContext = Self.videoCodecContext(from: formatContext) {
            let videoDecoder = IRFFVideoDecoder(
                codecContext: videoCodecContext,
                timebase: formatContext.videoTimebase,
                fps: formatContext.videoFPS,
                delegate: self
            )
            videoDecoder.videoToolBoxEnable = hardwareDecoderEnable
            let didInstallVideoDecoder = collaborators.withSnapshot(
                default: false
            ) { [session] snapshot in
                videoDecoder.source = snapshot.source
                return session.installVideoDecoder(videoDecoder)
            }
            guard didInstallVideoDecoder else {
                videoDecoder.destroy()
                return
            }
        }
        if let audioCodecContext = Self.audioCodecContext(from: formatContext) {
            let audioDecoder = IRFFAudioDecoder.decoder(
                codecContext: audioCodecContext,
                timebase: formatContext.audioTimebase,
                delegate: self
            )
            guard session.installAudioDecoder(audioDecoder) else {
                audioDecoder.destroy()
                return
            }
        }
        guard session.markOpenSucceeded() else { return }
        guard !closed else { return }

        guard runtimeState.markPreparedIfOpen() else { return }
        notifyDelegate {
            $0.decoderDidPrepareToDecodeFrames(self)
        }
        guard !closed else { return }

        scheduleWorkers()
    }

    private func readPacketThread() {
        let initialResources = session.workerResources
        let initialGeneration =
            runtimeState.snapshot.decodeGeneration
        initialResources.videoDecoder?.flush(
            generation: initialGeneration
        )
        initialResources.audioDecoder?.flush(
            generation: initialGeneration
        )
        reading = true
        var finished = false
        var readRetryAttempt = 0
        var pendingAudioPacket: (
            packet: IRFFPacket,
            generation: UInt64
        )?
        var pendingVideoPacket: (
            packet: IRFFPacket,
            generation: UInt64
        )?
        var pendingEOF: (
            transition: ReadPacketEOFTransition,
            generation: UInt64
        )?
        var maintenanceGeneration =
            initialGeneration
        defer {
            pendingAudioPacket?.packet.close()
            pendingVideoPacket?.packet.close()
        }

        func commitAudioError(
            _ error: NSError,
            generation: UInt64
        ) -> Bool {
            runtimeState.commitDecodeError(
                error,
                generation: generation,
                notification: {
                    delegateErrorCallback()
                }
            )
        }

        while !finished {
            let runtimeSnapshot = runtimeState.snapshot
            if Self.readLoopExitAction(
                closed: runtimeSnapshot.closed,
                hasError: runtimeSnapshot.hasError
            ) == .quit {
                IRFFRuntimeDebugOutput.write("read packet thread quit")
                break
            }
            let resources = session.workerResources
            if let seekRequest =
                    runtimeState.takePendingSeek(),
               let transition =
                    Self.seekCompletionTransition(
                        seeking: true,
                        progress:
                            seekRequest.target
                    ) {
                pendingAudioPacket?.packet.close()
                pendingAudioPacket = nil
                pendingVideoPacket?.packet.close()
                pendingVideoPacket = nil
                pendingEOF = nil
                resources.formatContext?.seekFile(
                    withFFTimebase: seekRequest.target
                )
                resources.audioDecoder?.flush(
                    generation:
                        seekRequest.decodeGeneration
                )
                resources.videoDecoder?.flush(
                    generation:
                        seekRequest.decodeGeneration
                )
                resources.videoDecoder?.paused =
                    transition.videoPaused
                let commit = runtimeState.commitSeek(
                    seekRequest,
                    transition: transition,
                    bufferingStartTime:
                        Date().timeIntervalSince1970
                )
                if let bufferingChange =
                        commit?.bufferingChange {
                    notifyDelegate {
                        $0.decoder(
                            self,
                            didChangeValueOfBuffering:
                                bufferingChange.current
                        )
                    }
                }
                maintenanceGeneration =
                    seekRequest.decodeGeneration
                updateBufferedDurationByVideo(
                    generation:
                        seekRequest.decodeGeneration
                )
                updateBufferedDurationByAudio(
                    generation:
                        seekRequest.decodeGeneration
                )
                commit?.completion?(true)
                readRetryAttempt = 0
                continue
            }

            if let pendingEnd = pendingEOF {
                guard runtimeState
                        .acceptsDecodeGeneration(
                            pendingEnd.generation
                        ) else {
                    pendingEOF = nil
                    continue
                }
                let drainResult =
                    resources.audioDecoder?.drain(
                        generation:
                            pendingEnd.generation
                    ) ?? .endOfStream
                switch drainResult {
                case .needsInput:
                    continue
                case .backpressured:
                    Thread.sleep(
                        forTimeInterval:
                            Self
                                .decodeAdmissionSleepInterval(
                                    paused:
                                        runtimeSnapshot.paused
                                )
                    )
                    continue
                case .canceled:
                    pendingEOF = nil
                    continue
                case let .failed(code):
                    pendingEOF = nil
                    if commitAudioError(
                        Self.audioPumpFailureError(
                            code: code
                        ),
                        generation:
                            pendingEnd.generation
                    ) {
                        finished = true
                    }
                    continue
                case .endOfStream:
                    break
                }

                pendingEOF = nil
                resources.videoDecoder?.finish(
                    generation:
                        pendingEnd.generation
                )
                let didCommitEOF =
                    runtimeState.commitEndOfFile(
                        generation:
                            pendingEnd.generation,
                        notification: {
                            if pendingEnd
                                .transition
                                .shouldNotifyDelegate {
                                notifyDelegate {
                                    $0.decoderDidEndOfFile(
                                        self
                                    )
                                }
                            }
                        }
                    )
                guard didCommitEOF else {
                    continue
                }
                finished =
                    pendingEnd.transition
                        .shouldFinishReadLoop
                continue
            }

            if let pending = pendingAudioPacket {
                guard runtimeState
                        .acceptsDecodeGeneration(
                            pending.generation
                        ) else {
                    pending.packet.close()
                    pendingAudioPacket = nil
                    continue
                }
                guard let audioDecoder =
                        resources.audioDecoder else {
                    pending.packet.close()
                    pendingAudioPacket = nil
                    continue
                }
                let packetResult =
                    audioDecoder.putPacket(
                        pending.packet,
                        generation:
                            pending.generation
                    )
                switch packetResult {
                case .deferred:
                    updateBufferedDurationByAudio(
                        generation:
                            pending.generation
                    )
                    Thread.sleep(
                        forTimeInterval:
                            Self
                                .decodeAdmissionSleepInterval(
                                    paused:
                                        runtimeSnapshot.paused
                                )
                    )
                    continue
                case let .consumed(result):
                    pendingAudioPacket = nil
                    updateBufferedDurationByAudio(
                        generation:
                            pending.generation
                    )
                    switch result {
                    case .needsInput:
                        break
                    case .backpressured:
                        continue
                    case .canceled:
                        continue
                    case let .failed(code):
                        if commitAudioError(
                            Self.audioPumpFailureError(
                                code: code
                            ),
                            generation:
                                pending.generation
                        ) {
                            finished = true
                        }
                        continue
                    case .endOfStream:
                        if commitAudioError(
                            Self
                                .audioUnexpectedEndOfStreamError(),
                            generation:
                                pending.generation
                        ) {
                            finished = true
                        }
                        continue
                    }
                }
            }

            if let pending = pendingVideoPacket {
                guard runtimeState
                        .acceptsDecodeGeneration(
                            pending.generation
                        ) else {
                    pending.packet.close()
                    pendingVideoPacket = nil
                    continue
                }
                guard let videoDecoder =
                        resources.videoDecoder else {
                    pending.packet.close()
                    pendingVideoPacket = nil
                    continue
                }
                switch videoDecoder.putPacket(
                    pending.packet,
                    generation:
                        pending.generation
                ) {
                case .accepted:
                    pendingVideoPacket = nil
                    maintenanceGeneration =
                        pending.generation
                    updateBufferedDurationByVideo(
                        generation:
                            pending.generation
                    )
                case .deferred:
                    Thread.sleep(
                        forTimeInterval:
                            Self
                                .decodeAdmissionSleepInterval(
                                    paused:
                                        runtimeSnapshot.paused
                                )
                    )
                    continue
                case .rejected:
                    pendingVideoPacket = nil
                    continue
                }
            }

            if let audioDecoder =
                    resources.audioDecoder {
                let admission =
                    audioDecoder.decodeAdmission
                if admission.requiresOutputResume {
                    switch audioDecoder
                        .resumePendingOutput(
                            generation:
                                runtimeSnapshot
                                    .decodeGeneration
                        ) {
                    case .needsInput:
                        updateBufferedDurationByAudio(
                            generation:
                                runtimeSnapshot
                                    .decodeGeneration
                        )
                    case .backpressured:
                        updateBufferedDurationByAudio(
                            generation:
                                runtimeSnapshot
                                    .decodeGeneration
                        )
                        Thread.sleep(
                            forTimeInterval:
                                Self
                                    .decodeAdmissionSleepInterval(
                                        paused:
                                            runtimeSnapshot
                                                .paused
                                    )
                        )
                        continue
                    case .canceled:
                        continue
                    case let .failed(code):
                        if commitAudioError(
                            Self.audioPumpFailureError(
                                code: code
                            ),
                            generation:
                                runtimeSnapshot
                                    .decodeGeneration
                        ) {
                            finished = true
                        }
                        continue
                    case .endOfStream:
                        if commitAudioError(
                            Self
                                .audioUnexpectedEndOfStreamError(),
                            generation:
                                runtimeSnapshot
                                    .decodeGeneration
                        ) {
                            finished = true
                        }
                        continue
                    }
                }
                if audioDecoder.decodeAdmission
                    .shouldThrottlePacketRead {
                    Thread.sleep(
                        forTimeInterval:
                            Self
                                .decodeAdmissionSleepInterval(
                                    paused:
                                        runtimeSnapshot.paused
                                )
                    )
                    continue
                }
            }
            if let videoDecoder =
                    resources.videoDecoder,
               videoDecoder.decodeAdmission
                .shouldThrottlePacketRead {
                Thread.sleep(
                    forTimeInterval:
                        Self
                            .decodeAdmissionSleepInterval(
                                paused:
                                    runtimeSnapshot.paused
                            )
                )
                continue
            }

            let size = Int(resources.audioDecoder?.size() ?? 0)
            let packetSize = resources.videoDecoder?.packetSize() ?? 0
            if case let .sleep(interval)? = Self.readLoopBackpressureAction(
                audioSize: size,
                videoPacketSize: packetSize,
                paused: runtimeState.snapshot.paused
            ) {
                IRFFRuntimeDebugOutput.write("read thread sleep: \(interval)")
                Thread.sleep(forTimeInterval: interval)
                continue
            }
            let readGeneration =
                runtimeState.snapshot.decodeGeneration
            let packet = IRFFPacket()
            let result = packet.fill {
                rawPacket in
                resources.formatContext?
                    .readFrame(&rawPacket) ?? -1
            }
            guard runtimeState
                    .acceptsDecodeGeneration(
                        readGeneration
                    ) else {
                packet.close()
                readRetryAttempt = 0
                continue
            }
            maintenanceGeneration =
                readGeneration
            if case let .retryRead(interval)? =
                    Self.readLoopReadAction(
                        readFrameResult: result,
                        retryAttempt:
                            readRetryAttempt
                    ) {
                readRetryAttempt += 1
                Thread.sleep(
                    forTimeInterval: interval
                )
                continue
            }
            if case let .failRead(code)? =
                    Self.readLoopReadAction(
                        readFrameResult: result,
                        retryAttempt:
                            readRetryAttempt
                    ) {
                let readError = IRFFCheckErrorCode(
                    code,
                    errorCode:
                        IRFFDecoderErrorCode
                            .formatReadFrame.rawValue
                )
                if let readError,
                   runtimeState.commitDecodeError(
                       readError,
                       generation:
                           readGeneration,
                       notification: {
                           delegateErrorCallback()
                       }
                   ) {
                    finished = true
                    break
                }
                continue
            }
            readRetryAttempt = 0
            if case let .finishEOF(transition)? =
                    Self.readLoopReadAction(
                        readFrameResult: result,
                        retryAttempt: 0
                    ) {
                IRFFRuntimeDebugOutput.write("read packet finished")
                pendingEOF = (
                    transition,
                    readGeneration
                )
                continue
            }
            guard let packetSnapshot = packet.snapshot else {
                packet.close()
                continue
            }
            let packetAction = Self.readLoopPacketAction(
                streamIndex: packetSnapshot.streamIndex,
                videoTrackIndex: resources.formatContext?.videoTrack?.index,
                audioTrackIndex: resources.formatContext?.audioTrack?.index
            )
            switch packetAction {
            case .routePacket(.video):
                IRFFRuntimeDebugOutput.write("video: put packet")
                if let videoDecoder =
                        resources.videoDecoder {
                    switch videoDecoder.putPacket(
                        packet,
                        generation: readGeneration
                    ) {
                    case .accepted:
                        updateBufferedDurationByVideo(
                            generation:
                                readGeneration
                        )
                    case .deferred:
                        pendingVideoPacket = (
                            packet,
                            readGeneration
                        )
                    case .rejected:
                        break
                    }
                } else {
                    packet.close()
                }
            case .routePacket(.audio):
                IRFFRuntimeDebugOutput.write("audio: put packet")
                guard let audioDecoder =
                        resources.audioDecoder else {
                    packet.close()
                    continue
                }
                switch audioDecoder.putPacket(
                    packet,
                    generation: readGeneration
                ) {
                case .deferred:
                    pendingAudioPacket = (
                        packet,
                        readGeneration
                    )
                    updateBufferedDurationByAudio(
                        generation:
                            readGeneration
                    )
                case let .consumed(result):
                    updateBufferedDurationByAudio(
                        generation:
                            readGeneration
                    )
                    switch result {
                    case .needsInput:
                        break
                    case .backpressured,
                         .canceled:
                        continue
                    case let .failed(code):
                        if commitAudioError(
                            Self.audioPumpFailureError(
                                code: code
                            ),
                            generation:
                                readGeneration
                        ) {
                            finished = true
                        }
                    case .endOfStream:
                        if commitAudioError(
                            Self
                                .audioUnexpectedEndOfStreamError(),
                            generation:
                                readGeneration
                        ) {
                            finished = true
                        }
                    }
                }
            case .routePacket(.ignored):
                packet.close()
            case .quit,
                 .completeSeek(_),
                 .sleep(_),
                 .retryRead(_),
                 .finishEOF(_),
                 .failRead(_):
                packet.close()
            }
        }
        reading = false
        checkBufferingStatus(
            generation:
                maintenanceGeneration
        )
    }

    private func displayThread(
        generation: UInt64
    ) {
        while true {
            let runtimeSnapshot = runtimeState.snapshot
            if runtimeSnapshot
                .decodeGeneration != generation ||
                Self.displayLoopExitAction(
                closed: runtimeSnapshot.closed,
                hasError: runtimeSnapshot.hasError
            ) == .quit {
                IRFFRuntimeDebugOutput.write("display thread quit")
                break
            }
            let resources = session.workerResources
            let displayedFrame = currentVideoFrame
            if case let .idleSleep(interval: sleepTime, replayCurrentFrame: replayCurrentFrame)? = Self.displayLoopIdleAction(
                seeking: runtimeSnapshot.seeking,
                buffering: runtimeSnapshot.buffering,
                paused: runtimeSnapshot.paused,
                hasCurrentFrame: displayedFrame != nil
            ) {
                if replayCurrentFrame {
                    _ = runtimeState
                        .replayCurrentVideoFrame(
                            generation:
                                generation,
                            delivery: {
                                [collaborators] frame in
                                collaborators
                                    .deliverVideoFrame(
                                        frame
                                    )
                            }
                        )
                }
                Thread.sleep(forTimeInterval: sleepTime)
                continue
            }
            if Self.displayLoopFinishAction(
                endOfFile: runtimeSnapshot.endOfFile,
                videoDecoderEmpty: resources.videoDecoder?.empty() ?? true
            ) == .finish {
                IRFFRuntimeDebugOutput.write("display finished")
                break
            }
            if resources.formatContext?.audioEnable == true {
                if let currentFrame = displayedFrame {
                    if case let .waitForAudio(interval: sleepTime)? = Self.displayLoopAudioSyncAction(
                        currentFramePosition: currentFrame.position,
                        currentFrameDuration: currentFrame.duration,
                        audioTimeClock: runtimeSnapshot.audioTimeClock,
                        fps: resources.videoDecoder?.fps ?? 1
                    ) {
                        IRFFRuntimeDebugOutput.write("display thread sleep: \(sleepTime)")
                        Thread.sleep(forTimeInterval: sleepTime)
                        continue
                    }
                }
                if resources.videoDecoder?.frameEmpty() ?? true {
                    updateBufferedDurationByVideo(
                        generation: generation
                    )
                }
                let newFrame = resources.videoDecoder?.waitForFrame()
                guard runtimeState
                        .acceptsDecodeGeneration(
                            generation
                        ) else {
                    newFrame?.cancel()
                    break
                }
                if !Self.admitDisplayFrame(
                    newFrame,
                    after:
                        displayedFrame?.position
                ) {
                    continue
                }
                if let currentFrame = newFrame {
                    guard commitDeliveredVideoFrame(
                        currentFrame,
                        generation: generation,
                        updatesProgress: false
                    ) else {
                        currentFrame.cancel()
                        continue
                    }
                    if runtimeSnapshot.endOfFile {
                        updateBufferedDurationByVideo(
                            generation:
                                generation
                        )
                    }
                } else if runtimeSnapshot.endOfFile {
                    _ = runtimeState
                        .clearCurrentVideoFrame(
                            generation:
                                generation
                        )
                    updateBufferedDurationByVideo(
                        generation: generation
                    )
                }
            } else {
                if resources.videoDecoder?.frameEmpty() ?? true {
                    updateBufferedDurationByVideo(
                        generation: generation
                    )
                }
                let newFrame = resources.videoDecoder?.waitForFrame()
                guard runtimeState
                        .acceptsDecodeGeneration(
                            generation
                        ) else {
                    newFrame?.cancel()
                    break
                }
                if !Self.admitDisplayFrame(
                    newFrame,
                    after:
                        displayedFrame?.position
                ) {
                    continue
                }
                if let currentFrame = newFrame {
                    guard commitDeliveredVideoFrame(
                        currentFrame,
                        generation: generation,
                        updatesProgress: true
                    ) else {
                        currentFrame.cancel()
                        continue
                    }
                    if runtimeSnapshot.endOfFile {
                        updateBufferedDurationByVideo(
                            generation:
                                generation
                        )
                    }
                    if case let .sleepAfterFrame(interval: sleepTime)? = Self.displayLoopStandaloneSleepAction(
                        frameDuration: currentFrame.duration,
                        fps: resources.videoDecoder?.fps ?? 1
                    ) {
                        Thread.sleep(forTimeInterval: sleepTime)
                    }
                } else if runtimeSnapshot.endOfFile {
                    _ = runtimeState
                        .clearCurrentVideoFrame(
                            generation:
                                generation
                        )
                    updateBufferedDurationByVideo(
                        generation: generation
                    )
                }
            }
        }
        checkBufferingStatus(
            generation: generation
        )
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
        let hasAudio = session.withResources(default: false) { resources in
            resources.formatContext?.audioEnable == true
        }
        let mediaDuration = duration
        guard let preparation = Self.seekPreparation(
            requestedTime: time,
            seekEnabled: mediaDuration > 0,
            hasError: runtimeSnapshot.hasError,
            hasAudio: hasAudio,
            seekMinTime: 0,
            duration: mediaDuration,
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
        session.withResources(default: ()) {
            resources in
            resources.audioDecoder?.invalidate(
                generation:
                    seekResult.decodeGeneration
            )
            resources.videoDecoder?.invalidate(
                generation:
                    seekResult.decodeGeneration
            )
            resources.videoDecoder?.paused = true
        }
        seekResult.displacedCompletion?(false)
        if let progressChange = seekResult.progressChange {
            notifyDelegate {
                $0.decoder(
                    self,
                    didChangeValueOfProgress: progressChange.current
                )
            }
        }
        scheduleWorkers(
            deferIfRunning: true,
            includeRead:
                seekResult.needsWorkerRestart
        )
    }

    func fetchAudioFrame() -> IRFFAudioRenderLease? {
        runtimeState.tryFetchAudioFrame {
            runtimeSnapshot in
            guard Self.shouldFetchAudioFrame(
                closed: runtimeSnapshot.closed,
                hasError:
                    runtimeSnapshot.hasError,
                seeking: runtimeSnapshot.seeking,
                buffering: runtimeSnapshot.buffering,
                paused: runtimeSnapshot.paused,
                playbackFinished:
                    runtimeSnapshot.playbackFinished,
                audioEnabled: true
            ) else {
                return nil
            }
            return session.tryDequeueAudioFrame()
        }
    }

    func finishAudioFrame(
        _ identifier: ObjectIdentifier
    ) -> Bool {
        runtimeState.tryFinishAudioFrame(identifier)
    }

    func finishAudioFrameSynchronously(
        _ identifier: ObjectIdentifier
    ) -> Bool {
        runtimeState.finishAudioFrame(identifier)
    }

    func closeFile() {
        closeFileAsync(true)
    }

    private func closeFileAsync(_ async: Bool) {
        _ = revokeCollaborators()
        guard runtimeState.beginClose() else { return }
        let seekCompletions = runtimeState.cancelSeeks()
        seekCompletions.forEach { $0(false) }
        let cleanup = { [self] in
            session.close()
            closePropertyValue()
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
        bufferingStartTime = 0
    }

    private func checkBufferingStatus(
        generation: UInt64? = nil
    ) {
        if let generation {
            _ = runtimeState
                .commitVideoBufferingStatus(
                    generation: generation,
                    currentTime:
                        Date()
                            .timeIntervalSince1970,
                    notification: {
                        bufferingChange in
                        notifyDelegate {
                            $0.decoder(
                                self,
                                didChangeValueOfBuffering:
                                    bufferingChange
                                        .current
                            )
                        }
                    }
                )
            return
        }
        let runtimeSnapshot = runtimeState.snapshot
        let transition = Self.bufferingStatusTransition(
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
            notifyDelegate {
                $0.decoder(
                    self,
                    didChangeValueOfBuffering: bufferingChange.current
                )
            }
        }
    }

    private func audioMonitoringThread() {
        while true {
            while let frame =
                    runtimeState.takeFinishedAudioFrame() {
                frame.cancel()
            }
            let runtimeSnapshot = runtimeState.snapshot
            guard !runtimeSnapshot.closed,
                  !runtimeSnapshot.hasError else {
                return
            }
            let generation =
                runtimeSnapshot.decodeGeneration
            if !runtimeSnapshot.seeking {
                updateProgressByAudio(
                    generation: generation
                )
                updateBufferedDurationByAudio(
                    generation: generation
                )
            }
            Thread.sleep(forTimeInterval: 0.01)
        }
    }

    private func updateBufferedDurationByVideo(
        generation: UInt64
    ) {
        let duration = session.withResources(
            default: Optional<TimeInterval>.none
        ) { resources -> TimeInterval? in
            guard resources.formatContext?.audioEnable == false else {
                return nil
            }
            return resources.videoDecoder?.duration() ?? 0
        }
        guard let duration else { return }
        commitBufferedDuration(
            duration,
            generation: generation
        )
    }

    private func updateBufferedDurationByAudio(
        generation: UInt64
    ) {
        let duration = session.withResources(
            default: Optional<TimeInterval>.none
        ) { resources -> TimeInterval? in
            guard resources.formatContext?.audioEnable == true else {
                return nil
            }
            return (resources.audioDecoder?.duration() ?? 0)
                + runtimeState.activeAudioFrameDuration
        }
        guard let duration else { return }
        commitBufferedDuration(
            duration,
            generation: generation
        )
    }

    private func commitBufferedDuration(
        _ duration: TimeInterval,
        generation: UInt64
    ) {
        _ = runtimeState.commitBufferedDuration(
            duration,
            playbackDuration: self.duration,
            generation: generation,
            currentTime:
                Date().timeIntervalSince1970,
            notification: {
                [self] commit in
                notifyDelegate {
                    $0.decoder(
                        self,
                        didChangeValueOfBufferedDuration:
                            commit
                                .bufferedDurationChange
                                .current
                    )
                }
                if let progressChange =
                        commit.progressChange {
                    _ = runtimeState
                        .notifyIfCurrentDecodeGeneration(
                            generation,
                            notification: {
                                notifyDelegate {
                                    $0.decoder(
                                        self,
                                        didChangeValueOfProgress:
                                            progressChange
                                                .current
                                    )
                                }
                            }
                        )
                }
                if commit.didFinishPlayback {
                    _ = runtimeState
                        .notifyIfCurrentDecodeGeneration(
                            generation,
                            notification: {
                                notifyDelegate {
                                    $0.decoderDidPlaybackFinished(
                                        self
                                    )
                                }
                            }
                        )
                }
                if let bufferingChange =
                        commit.bufferingChange {
                    _ = runtimeState
                        .notifyIfCurrentDecodeGeneration(
                            generation,
                            notification: {
                                notifyDelegate {
                                    $0.decoder(
                                        self,
                                        didChangeValueOfBuffering:
                                            bufferingChange
                                                .current
                                    )
                                }
                            }
                        )
                }
            }
        )
    }

    private func commitDeliveredVideoFrame(
        _ frame: IRFFVideoFrame,
        generation: UInt64,
        updatesProgress: Bool
    ) -> Bool {
        runtimeState.commitDeliveredVideoFrame(
            frame,
            generation: generation,
            progress:
                updatesProgress
                ? frame.position
                : nil,
            playbackDuration: duration,
            delivery: {
                [collaborators] frame in
                collaborators.deliverVideoFrame(
                    frame
                )
            },
            notification: {
                [self] progressChange in
                notifyDelegate {
                    $0.decoder(
                        self,
                        didChangeValueOfProgress:
                            progressChange.current
                    )
                }
            }
        )
    }

    private func updateProgressByAudio(
        generation: UInt64
    ) {
        let shouldUpdate = session.withResources(default: false) {
            $0.formatContext?.audioEnable == true
        }
        guard shouldUpdate else { return }
        _ = runtimeState.commitPendingAudioProgress(
            generation: generation,
            playbackDuration: duration,
            notification: {
                [self] progressChange in
                notifyDelegate {
                    $0.decoder(
                        self,
                        didChangeValueOfProgress:
                            progressChange.current
                    )
                }
            }
        )
    }

    private func delegateErrorCallback() {
        let runtimeSnapshot = runtimeState.snapshot
        guard !runtimeSnapshot.closed,
              runtimeSnapshot.hasError,
              let error = error else { return }
        notifyDelegate {
            $0.decoder(self, didError: error)
        }
    }

    deinit {
        closeFileAsync(false)
    }
}

extension IRFFDecoder: IRFFFormatContextDelegate {
    public func formatContextNeedInterrupt(_ formatContext: IRFFFormatContext) -> Bool {
        let snapshot = runtimeState.snapshot
        return snapshot.closed || snapshot.seeking
    }
}

extension IRFFDecoder: IRFFAudioDecoderDelegate {
    func audioDecoder(_ audioDecoder: IRFFAudioDecoder, samplingRate: inout Float64) {
        samplingRate = collaborators.withAudioOutput(default: 0) {
            $0.samplingRate
        }
    }

    func audioDecoder(_ audioDecoder: IRFFAudioDecoder, channelCount: inout UInt32) {
        channelCount = collaborators.withAudioOutput(default: 0) {
            $0.numberOfChannels
        }
    }
}

extension IRFFDecoder: IRFFVideoDecoderDelegate {
    func videoDecoderNeedUpdateBufferedDuration(
        _ videoDecoder: IRFFVideoDecoder,
        generation: UInt64
    ) {
        updateBufferedDurationByVideo(
            generation: generation
        )
    }

    func videoDecoderNeedCheckBufferingStatus(
        _ videoDecoder: IRFFVideoDecoder,
        generation: UInt64
    ) {
        checkBufferingStatus(
            generation: generation
        )
    }

    func videoDecoder(
        _ videoDecoder: IRFFVideoDecoder,
        didError error: Error,
        generation: UInt64
    ) {
        _ = runtimeState.commitDecodeError(
            error,
            generation: generation,
            notification: {
                delegateErrorCallback()
            }
        )
    }
}

extension IRFFDecoder: IRFFDecoderVideoOutput {
    public func send(videoFrame: IRFFVideoFrame) {
        _ = trySend(videoFrame: videoFrame)
    }

    public func trySend(
        videoFrame: IRFFVideoFrame
    ) -> Bool {
        session.withResources(default: false) {
            guard let videoDecoder =
                    $0.videoDecoder else {
                videoFrame.cancel()
                return false
            }
            return videoDecoder.trySend(
                videoFrame: videoFrame
            )
        }
    }
}
