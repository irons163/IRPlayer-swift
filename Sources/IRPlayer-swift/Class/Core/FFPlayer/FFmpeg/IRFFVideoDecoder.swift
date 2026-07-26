//
//  IRFFVideoDecoder.swift
//  IRPlayer-swift
//
//  Created by irons on 2024/7/13.
//

import Foundation
import AVFoundation
import CoreMedia
#if SWIFT_PACKAGE || DEBUG
internal import IRFFMpeg
internal import IRPlayerObjc
#else
@_implementationOnly import IRFFMpeg
@_implementationOnly import IRPlayerObjc
#endif

protocol IRFFVideoDecoderDelegate: AnyObject {
    func videoDecoder(
        _ videoDecoder: IRFFVideoDecoder,
        didError error: Error,
        generation: UInt64
    )
    func videoDecoderNeedUpdateBufferedDuration(
        _ videoDecoder: IRFFVideoDecoder,
        generation: UInt64
    )
    func videoDecoderNeedCheckBufferingStatus(
        _ videoDecoder: IRFFVideoDecoder,
        generation: UInt64
    )
}

enum IRFFVideoPacketAdmissionResult:
    Equatable,
    Sendable
{
    case accepted
    case deferred
    case rejected
}

struct IRFFVideoDecodeAdmissionDiagnostics:
    Equatable,
    Sendable
{
    let capacity:
        IRFFDecodeAdmission.Snapshot
    let queuedItemCount: Int
    let maximumQueuedItemCount: Int
    let acceptsPackets: Bool

    var canAdmitPacket: Bool {
        acceptsPackets &&
            queuedItemCount <
                maximumQueuedItemCount &&
            capacity.canAdmitPacket
    }

    var shouldThrottlePacketRead: Bool {
        !canAdmitPacket
    }
}

class IRFFVideoDecoder {
    static let packetAdmissionHeadroom = 8
    static let maximumQueuedPacketCount = 8

    enum DecodeBackend:
        Equatable
    {
        case undecided
        case ffmpeg
        case videoToolBox
    }

    enum VideoToolBoxResultKind:
        Equatable
    {
        case notAvailable
        case accepted
        case failed
    }

    enum VideoToolBoxRoute:
        Equatable
    {
        case fallbackToFFmpeg
        case consume
        case fail
    }

    struct VideoToolBoxTransition:
        Equatable
    {
        let backend: DecodeBackend
        let route: VideoToolBoxRoute
    }

    private struct RuntimeSnapshot {
        let canceled: Bool
        let error: NSError?
        let decoding: Bool
        let paused: Bool
        let endOfFile: Bool
        let videoToolBoxEnable: Bool
        let maxDecodeDuration: TimeInterval
        let generation: UInt64
        let transitionRevision: UInt64
        let backend: DecodeBackend
    }

    private final class PendingCustomDecode {
        let generation: UInt64
        weak var completion:
            IRFFCustomVideoDecodeCompletion?

        init(
            generation: UInt64,
            completion:
                IRFFCustomVideoDecodeCompletion
        ) {
            self.generation = generation
            self.completion = completion
        }
    }

    private let codecContext:
        UnsafeMutablePointer<AVCodecContext>
    private let codecDescriptor: IRFFVideoCodecDescriptor?
    private let decodeFrame: IRFFDecodeFrame?
    private let packetQueue: IRFFPacketQueue
    private let frameQueue: IRFFFrameQueue
    private let framePool: IRFFFramePool
    private let admissionLimits:
        IRFFDecodeAdmission.Limits
    private let maximumQueuedItemCount: Int
    private let softwareFrameBackpressureObserver:
        (() -> Void)?
    private let softwareFrameWillLeaseObserver:
        (() -> Void)?
    private let codecOperationLock = NSLock()
    private lazy var videoToolBox: IRFFVideoToolBox = {
        return IRFFVideoToolBox(
            codecContext: codecContext,
            timebase: timebase
        )
    }()
    private let sourceLock = NSLock()
    private weak var storedSource:
        IRFFVideoDecoderDataSource?
    private let runtimeLock = NSLock()
    private let customDecodeCondition =
        NSCondition()
    private var pendingCustomDecodes:
        [UInt64: PendingCustomDecode] = [:]
    private var nextCustomDecodeID:
        UInt64 = 0
    private let transitionLock = NSLock()
    private var runtimeCanceled = false
    private var runtimeError: NSError?
    private var runtimeDecodingGeneration:
        UInt64?
    private var runtimePaused = false
    private var runtimeEndOfFile = false
    private var runtimeVideoToolBoxEnable = true
    private var runtimeMaxDecodeDuration: TimeInterval = 2.0
    private var runtimeGeneration: UInt64 = 0
    private var runtimeTransitionRevision:
        UInt64 = 0
    private var runtimeBackend:
        DecodeBackend = .undecided

    weak var delegate: IRFFVideoDecoderDelegate?
    var source: IRFFVideoDecoderDataSource? {
        get {
            sourceLock.lock()
            defer { sourceLock.unlock() }
            return storedSource
        }
        set {
            sourceLock.lock()
            storedSource = newValue
            sourceLock.unlock()
        }
    }
    let timebase: TimeInterval
    let fps: TimeInterval

    var error: NSError? {
        runtimeSnapshot().error
    }

    var decoding: Bool {
        runtimeSnapshot().decoding
    }

    var paused: Bool {
        get { runtimeSnapshot().paused }
        set {
            runtimeLock.lock()
            runtimePaused = newValue
            runtimeLock.unlock()
        }
    }

    var endOfFile: Bool {
        runtimeSnapshot().endOfFile
    }

    var videoToolBoxEnable: Bool {
        get { runtimeSnapshot().videoToolBoxEnable }
        set {
            runtimeLock.lock()
            runtimeVideoToolBoxEnable = newValue
            runtimeLock.unlock()
        }
    }

    var maxDecodeDuration: TimeInterval {
        get { runtimeSnapshot().maxDecodeDuration }
        set {
            runtimeLock.lock()
            runtimeMaxDecodeDuration = newValue
            runtimeLock.unlock()
        }
    }

    init(
        codecContext:
            UnsafeMutablePointer<AVCodecContext>,
        timebase: TimeInterval,
        fps: TimeInterval,
        delegate:
            IRFFVideoDecoderDelegate?,
        framePool:
            IRFFFramePool = .videoPool(),
        packetAdmissionHeadroom:
            Int =
                IRFFVideoDecoder
                    .packetAdmissionHeadroom,
        maximumQueuedPacketCount:
            Int =
                IRFFVideoDecoder
                    .maximumQueuedPacketCount,
        softwareFrameBackpressureObserver:
            (() -> Void)? = nil,
        softwareFrameWillLeaseObserver:
            (() -> Void)? = nil
    ) {
        self.codecContext = codecContext
        self.codecDescriptor = IRFFVideoCodecDescriptor(
            copying: codecContext
        )
        self.timebase = timebase
        self.fps = fps
        self.delegate = delegate
        self.decodeFrame = IRFFDecodeFrame()
        self.packetQueue = IRFFPacketQueue(timebase: timebase)
        self.frameQueue = IRFFFrameQueue()
        self.framePool = framePool
        self.admissionLimits =
            IRFFDecodeAdmission.Limits(
                frameCapacity:
                    framePool
                        .diagnostics
                        .maximumCapacity,
                packetHeadroom:
                    packetAdmissionHeadroom
            )
        self.maximumQueuedItemCount =
            max(
                1,
                maximumQueuedPacketCount
            )
        self.softwareFrameBackpressureObserver =
            softwareFrameBackpressureObserver
        self.softwareFrameWillLeaseObserver =
            softwareFrameWillLeaseObserver
    }

    var decodeAdmission:
        IRFFVideoDecodeAdmissionDiagnostics
    {
        runtimeLock.lock()
        defer { runtimeLock.unlock() }
        return decodeAdmissionLocked()
    }

    func packetSize() -> Int {
        return Int(packetQueue.size)
    }

    func empty() -> Bool {
        let generation =
            runtimeSnapshot().generation
        return packetEmpty() &&
            frameEmpty() &&
            pendingCustomDecodeCount(
                generation: generation
            ) == 0
    }

    func packetEmpty() -> Bool {
        return packetQueue.count <= 0
    }

    var packetQueueWaitingConsumerCount: Int {
        packetQueue.waitingConsumerCount
    }

    func frameEmpty() -> Bool {
        return frameQueue.count <= 0
    }

    func duration() -> TimeInterval {
        return packetDuration() + frameDuration()
    }

    func packetDuration() -> TimeInterval {
        return packetQueue.duration
    }

    func frameDuration() -> TimeInterval {
        return frameQueue.duration
    }

    static func frameDuration(ticks: Int64, repeatPicture: Int32, timebase: TimeInterval, fps: TimeInterval) -> TimeInterval {
        if ticks != 0 {
            guard timebase.isFinite, timebase > 0 else {
                return 0
            }
            let baseDuration =
                TimeInterval(ticks) * timebase
            let repeatDuration =
                TimeInterval(max(0, repeatPicture)) *
                timebase *
                0.5
            let duration = baseDuration + repeatDuration
            return baseDuration.isFinite &&
                repeatDuration.isFinite &&
                duration.isFinite &&
                duration > 0
                ? duration
                : 0
        }

        guard fps.isFinite, fps > 0 else { return 0 }
        let duration = 1 / fps
        return duration.isFinite && duration > 0
            ? duration
            : 0
    }

    static func decodeBackpressureSleepInterval(frameDuration: TimeInterval,
                                                maxDecodeDuration: TimeInterval,
                                                paused: Bool) -> TimeInterval? {
        guard frameDuration.isFinite,
              maxDecodeDuration.isFinite,
              maxDecodeDuration > 0,
              frameDuration >= maxDecodeDuration else {
            return nil
        }
        return paused ? 0.5 : 0.1
    }

    static func packetDecodeResultIsFailure(_ result: Int32) -> Bool {
        return IRFFDecodeResult.isFailure(result)
    }

    static func shouldFinishDecode(endOfFile: Bool, packetEmpty: Bool) -> Bool {
        return endOfFile && packetEmpty
    }

    static func decodeIdleSleepInterval(paused: Bool) -> TimeInterval? {
        return paused ? 0.01 : nil
    }

    static func shouldCreateYUVFrame(hasFrame: Bool,
                                     hasLuma: Bool,
                                     hasChromaB: Bool,
                                     hasChromaR: Bool) -> Bool {
        return hasFrame &&
            hasLuma &&
            hasChromaB &&
            hasChromaR
    }

    static func packetQueueFallbackDuration(packetDuration: Int64,
                                            packetSize: Int32,
                                            timebase: TimeInterval,
                                            fps: TimeInterval) -> TimeInterval {
        guard packetDuration <= 0, packetSize > 0 else {
            return 0
        }
        return frameDuration(
            ticks: 0,
            repeatPicture: 0,
            timebase: timebase,
            fps: fps
        )
    }

    static func videoToolBoxTransition(
        backend: DecodeBackend,
        result: VideoToolBoxResultKind
    ) -> VideoToolBoxTransition {
        switch (backend, result) {
        case (.undecided, .notAvailable),
             (.ffmpeg, .notAvailable):
            return VideoToolBoxTransition(
                backend: .ffmpeg,
                route: .fallbackToFFmpeg
            )
        case (.undecided, .accepted),
             (.videoToolBox, .accepted):
            return VideoToolBoxTransition(
                backend: .videoToolBox,
                route: .consume
            )
        case (.videoToolBox, .notAvailable),
             (.ffmpeg, .accepted),
             (_, .failed):
            return VideoToolBoxTransition(
                backend: backend,
                route: .fail
            )
        }
    }

    func waitForFrame() -> IRFFVideoFrame? {
        frameQueue.waitForFrame()
            as? IRFFVideoFrame
    }

    func dequeueFrame() -> IRFFVideoFrame? {
        frameQueue.dequeue()
            as? IRFFVideoFrame
    }

    @discardableResult
    func putPacket(
        _ packet: IRFFPacket
    ) -> IRFFVideoPacketAdmissionResult {
        putPacket(
            packet,
            generation:
                runtimeSnapshot().generation
        )
    }

    @discardableResult
    func putPacket(
        _ packet: IRFFPacket,
        generation: UInt64
    ) -> IRFFVideoPacketAdmissionResult {
        guard let snapshot = packet.snapshot else {
            packet.close()
            return .rejected
        }
        let duration = Self.packetQueueFallbackDuration(
            packetDuration: snapshot.duration,
            packetSize: snapshot.size,
            timebase: timebase,
            fps: fps
        )
        runtimeLock.lock()
        guard !runtimeCanceled,
              runtimeError == nil,
              !runtimeEndOfFile,
              runtimeGeneration == generation else {
            runtimeLock.unlock()
            packet.close()
            return .rejected
        }
        guard decodeAdmissionLocked()
                .canAdmitPacket else {
            runtimeLock.unlock()
            return .deferred
        }
        let accepted = packetQueue.putPacket(
            packet,
            duration: duration,
            generation: generation
        )
        runtimeLock.unlock()
        return accepted
            ? .accepted
            : .rejected
    }

    @discardableResult
    func flush() -> Bool {
        flush(
            generation:
                runtimeSnapshot().generation
        )
    }

    @discardableResult
    func invalidate(
        generation: UInt64
    ) -> Bool {
        transitionLock.lock()
        defer { transitionLock.unlock() }
        runtimeLock.lock()
        guard !runtimeCanceled,
              generation >= runtimeGeneration,
              generation > runtimeGeneration ||
                runtimeDecodingGeneration ==
                    nil else {
            runtimeLock.unlock()
            return false
        }
        guard packetQueue.reset(
            to: generation
        ) else {
            runtimeLock.unlock()
            return false
        }
        runtimeGeneration = generation
        runtimeTransitionRevision &+= 1
        let invalidatedCompletions =
            removePendingCustomDecodesLocked()
        runtimeEndOfFile = false
        runtimeError = nil
        runtimeBackend = .undecided
        frameQueue.resume()
        frameQueue.flush()
        runtimeLock.unlock()
        for completion in
                invalidatedCompletions {
            completion.invalidate()
        }
        framePool.flush()
        return true
    }

    @discardableResult
    func flush(
        generation: UInt64
    ) -> Bool {
        invalidate(generation: generation)
    }

    @discardableResult
    func finish(
        generation: UInt64
    ) -> Bool {
        transitionLock.lock()
        defer { transitionLock.unlock() }
        runtimeLock.lock()
        guard !runtimeCanceled,
              runtimeError == nil,
              generation == runtimeGeneration else {
            runtimeLock.unlock()
            return false
        }
        guard packetQueue.putEndOfStream(
            generation: generation
        ) else {
            runtimeLock.unlock()
            return false
        }
        runtimeEndOfFile = true
        runtimeLock.unlock()
        return true
    }

    func destroy() {
        transitionLock.lock()
        defer { transitionLock.unlock() }
        runtimeLock.lock()
        runtimeCanceled = true
        runtimeGeneration &+= 1
        runtimeTransitionRevision &+= 1
        let invalidatedCompletions =
            removePendingCustomDecodesLocked()
        runtimeDecodingGeneration = nil
        runtimeBackend = .undecided
        runtimeLock.unlock()
        for completion in
                invalidatedCompletions {
            completion.invalidate()
        }
        frameQueue.close()
        packetQueue.destroy()
        framePool.close()
    }

    func decodeFrameThread(
        generation requestedGeneration:
            UInt64? = nil
    ) {
        let workerGeneration =
            requestedGeneration
            ?? runtimeSnapshot().generation
        codecOperationLock.lock()
        defer {
            setDecoding(
                false,
                generation:
                    workerGeneration
            )
            codecOperationLock.unlock()
        }
        guard accepts(
            generation: workerGeneration
        ) else {
            return
        }
        if codecContext.pointee.codec != nil {
            avcodec_flush_buffers(
                codecContext
            )
        }
        videoToolBox.flush()
        setDecoding(
            true,
            generation: workerGeneration
        )
        decodeLoop: while true {
            let runtime = runtimeSnapshot()
            if runtime.canceled ||
                runtime.error != nil ||
                runtime.generation !=
                    workerGeneration {
                IRFFRuntimeDebugOutput.write("decode video thread quit")
                break
            }
            if !runtime.endOfFile,
               let sleepTime = Self.decodeIdleSleepInterval(
                   paused: runtime.paused
               ) {
                Thread.sleep(forTimeInterval: sleepTime)
                continue
            }
            if Self.shouldFinishDecode(endOfFile: runtime.endOfFile, packetEmpty: packetEmpty()) {
                IRFFRuntimeDebugOutput.write("decode video finished")
                break
            }
            if let interval = Self.decodeBackpressureSleepInterval(frameDuration: frameDuration(),
                                                                   maxDecodeDuration: runtime.maxDecodeDuration,
                                                                   paused: runtime.paused) {
                IRFFRuntimeDebugOutput.write("decode video thread sleep : \(interval)")
                Thread.sleep(forTimeInterval: interval)
                continue
            }

            let item = packetQueue.getItem()
            let packetRuntime = runtimeSnapshot()
            if packetRuntime.canceled || packetRuntime.error != nil {
                if case let .packet(
                    packet,
                    generation: _
                ) = item {
                    packet.close()
                }
                break
            }

            switch item {
            case .closed:
                break decodeLoop
            case .interrupted:
                break decodeLoop
            case let .flush(generation):
                guard generation ==
                        workerGeneration,
                      accepts(
                    generation: generation
                ) else {
                    break decodeLoop
                }
                IRFFRuntimeDebugOutput.write("video codec flush")
                if codecContext.pointee.codec != nil {
                    avcodec_flush_buffers(
                        codecContext
                    )
                }
                videoToolBox.flush()
                continue
            case let .endOfStream(generation):
                guard generation ==
                        workerGeneration,
                      accepts(
                    generation: generation
                ) else {
                    break decodeLoop
                }
                guard waitForCustomDecodes(
                    generation: generation,
                    transitionRevision:
                        packetRuntime
                            .transitionRevision
                ) else {
                    let current =
                        runtimeSnapshot()
                    if !current.canceled,
                       current.error == nil,
                       current.generation ==
                            generation {
                        continue decodeLoop
                    }
                    break decodeLoop
                }
                let didCommit =
                    drainAndCommitEndOfStream(
                    generation: generation,
                    transitionRevision:
                        packetRuntime
                            .transitionRevision
                ) { [self] in
                    drainCodec(
                        generation: generation
                    )
                }
                if !didCommit {
                    let current =
                        runtimeSnapshot()
                    if !current.canceled,
                       current.error == nil,
                       current.generation ==
                            generation {
                        continue decodeLoop
                    }
                }
                break decodeLoop
            case let .packet(
                packet,
                generation: generation
            ):
                guard generation ==
                        workerGeneration,
                      accepts(
                    generation: generation
                ) else {
                    packet.close()
                    continue
                }
                if packetRuntime.endOfFile {
                    delegate?
                        .videoDecoderNeedUpdateBufferedDuration(
                            self,
                            generation: generation
                        )
                }
                guard let snapshot = packet.snapshot,
                      snapshot.streamIndex >= 0,
                      snapshot.hasData else {
                    packet.close()
                    continue
                }

                let didBorrow = packet.withPacket {
                    borrowedPacket in
                    decodePacket(
                        packet: borrowedPacket,
                        generation: generation
                    )
                    return true
                }
                packet.close()
                if !didBorrow {
                    continue
                }
            }
        }
        delegate?.videoDecoderNeedCheckBufferingStatus(
            self,
            generation: workerGeneration
        )
    }

    @discardableResult
    func drainAndCommitEndOfStream(
        generation: UInt64,
        transitionRevision: UInt64,
        beforeCommit:
            (() -> Void)? = nil,
        drain: () -> Void
    ) -> Bool {
        beforeCommit?()
        transitionLock.lock()
        runtimeLock.lock()
        guard !runtimeCanceled,
              runtimeError == nil,
              runtimeEndOfFile,
              runtimeGeneration == generation,
              runtimeTransitionRevision ==
                transitionRevision else {
            runtimeLock.unlock()
            transitionLock.unlock()
            return false
        }
        runtimeLock.unlock()
        transitionLock.unlock()

        // Codec drain may wait for output capacity. Do not hold the transition
        // gate here: seek/close must be able to publish cancellation so those
        // waits observe a stale ticket and terminate.
        drain()

        transitionLock.lock()
        defer { transitionLock.unlock() }
        runtimeLock.lock()
        guard !runtimeCanceled,
              runtimeError == nil,
              runtimeEndOfFile,
              runtimeGeneration == generation,
              runtimeTransitionRevision ==
                transitionRevision else {
            runtimeLock.unlock()
            return false
        }
        let didFinish = frameQueue.finish()
        runtimeLock.unlock()
        return didFinish
    }

    private func decodePacket(
        packet: AVPacket,
        generation: UInt64
    ) {
        let runtime = runtimeSnapshot()
        if let source,
           let codecDescriptor {
            let info = IRFFVideoDecoderInfo(
                codec: codecDescriptor,
                isHardwareDecodingEnabled:
                    runtime.videoToolBoxEnable,
                maximumDecodeDuration:
                    runtime.maxDecodeDuration,
                timebase: timebase,
                framesPerSecond: fps
            )
            if let descriptor =
                    IRFFVideoPacketDescriptor(
                        borrowing: packet
                    ),
               source.shouldHandle(
                    info,
                    packet: descriptor
               ) {
                guard let packetValue =
                        IRFFCompressedVideoPacket(
                            copying: packet
                        ) else {
                    commitDecodingError(
                        IRFFCheckError(-1),
                        generation: generation
                    )
                    return
                }
                guard let completion =
                        registerCustomDecode(
                            generation:
                                generation
                        ) else {
                    return
                }
                let outcome = source.videoDecoder(
                    info,
                    decodeFrame: packetValue,
                    completion: completion
                )
                switch outcome {
                case let .frame(frame):
                    _ = completion.complete(
                        .frame(frame)
                    )
                case .dropped:
                    _ = completion.drop()
                case .deferred:
                    break
                case let .failed(error):
                    _ = completion.fail(error)
                }
                return
            }
        }

        if runtime.videoToolBoxEnable,
           codecContext.pointee.codec_id ==
                AV_CODEC_ID_H264,
           runtime.backend != .ffmpeg {
            let result =
                videoToolBox.sendPacket(packet)
            guard let transition =
                    commitVideoToolBoxTransition(
                        result: result,
                        generation: generation
                    ) else {
                return
            }
            switch (transition.route, result) {
            case let (
                .consume,
                .accepted(outputs)
            ):
                enqueueVideoToolBoxOutputs(
                    outputs,
                    generation: generation
                )
                return
            case (.fallbackToFFmpeg, .notAvailable):
                break
            case let (.fail, .failed(status)):
                failVideoToolBox(
                    status: status,
                    generation: generation
                )
                return
            case (.fail, _):
                failVideoToolBox(
                    status: -1,
                    generation: generation
                )
                return
            case (.consume, _),
                 (.fallbackToFFmpeg, _):
                failVideoToolBox(
                    status: -1,
                    generation: generation
                )
                return
            }
        } else {
            guard commitSoftwareBackend(
                generation: generation
            ) else {
                return
            }
        }

        pumpFFmpeg(
            input: .packet,
            packet: packet,
            generation: generation
        )
    }

    private func drainCodec(
        generation: UInt64
    ) {
        let backend = runtimeSnapshot().backend
        switch backend {
        case .undecided:
            return
        case .ffmpeg:
            guard codecContext.pointee.codec != nil else {
                return
            }
            pumpFFmpeg(
                input: .drain,
                packet: nil,
                generation: generation
            )
        case .videoToolBox:
            let result =
                videoToolBox
                    .finishDelayedFrames()
            guard let transition =
                    commitVideoToolBoxTransition(
                        result: result,
                        generation: generation
                    ) else {
                return
            }
            switch (transition.route, result) {
            case let (
                .consume,
                .accepted(outputs)
            ):
                enqueueVideoToolBoxOutputs(
                    outputs,
                    generation: generation
                )
            case let (.fail, .failed(status)):
                failVideoToolBox(
                    status: status,
                    generation: generation
                )
            default:
                failVideoToolBox(
                    status: -1,
                    generation: generation
                )
            }
        }
    }

    private func commitSoftwareBackend(
        generation: UInt64
    ) -> Bool {
        runtimeLock.lock()
        defer { runtimeLock.unlock() }
        guard !runtimeCanceled,
              runtimeError == nil,
              runtimeGeneration == generation,
              runtimeBackend != .videoToolBox else {
            return false
        }
        runtimeBackend = .ffmpeg
        return true
    }

    private func commitVideoToolBoxTransition(
        result: IRFFVideoToolBox.DecodeResult,
        generation: UInt64
    ) -> VideoToolBoxTransition? {
        let kind: VideoToolBoxResultKind
        switch result {
        case .notAvailable:
            kind = .notAvailable
        case .accepted:
            kind = .accepted
        case .failed:
            kind = .failed
        }
        runtimeLock.lock()
        defer { runtimeLock.unlock() }
        guard !runtimeCanceled,
              runtimeError == nil,
              runtimeGeneration == generation else {
            return nil
        }
        let transition =
            Self.videoToolBoxTransition(
                backend: runtimeBackend,
                result: kind
            )
        runtimeBackend = transition.backend
        return transition
    }

    private func failVideoToolBox(
        status: OSStatus,
        generation: UInt64
    ) {
        videoToolBox.flush()
        _ = commitDecodingError(
            NSError(
                domain:
                    "IRFFVideoToolBox",
                code: Int(status),
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "VideoToolbox decode failed with status \(status)"
                ]
            ),
            generation: generation
        )
    }

    private func pumpFFmpeg(
        input: IRFFCodecPump.Input,
        packet: AVPacket?,
        generation: UInt64
    ) {
        guard let decodeFrame else { return }
        let packet = packet
        var receivedFrame:
            IRFFAVYUVVideoFrame?
        var frameBorrowFailed = false
        let outcome = IRFFCodecPump.run(
            input: input,
            send: {
                if var packet {
                    return avcodec_send_packet(
                        codecContext,
                        &packet
                    )
                }
                return avcodec_send_packet(
                    codecContext,
                    nil
                )
            },
            receive: {
                guard let videoFrame =
                        waitForSoftwareFrameLease(
                            generation:
                                generation
                        ) else {
                    return AVERROR(EAGAIN)
                }
                var receiveResult: Int32 = -1
                let didBorrow = decodeFrame.withFrame {
                    frame in
                    receiveResult =
                        avcodec_receive_frame(
                            codecContext,
                            frame
                        )
                    if receiveResult >= 0 {
                        if populateVideoFrame(
                            videoFrame,
                            fromDecodedFrame:
                                frame
                        ) {
                            receivedFrame =
                                videoFrame
                        } else {
                            videoFrame.cancel()
                        }
                    } else {
                        videoFrame.cancel()
                    }
                    return true
                }
                if !didBorrow {
                    videoFrame.cancel()
                    frameBorrowFailed = true
                    return -1
                }
                return receiveResult
            },
            isGenerationCurrent: {
                accepts(
                    generation: generation
                )
            },
            didReceiveFrame: {
                let frame = receivedFrame
                receivedFrame = nil
                enqueueReservedSoftwareFrame(
                    frame,
                    generation: generation
                )
            }
        )
        receivedFrame?.cancel()
        guard !frameBorrowFailed else {
            commitDecodingError(
                IRFFCheckError(-1),
                generation: generation
            )
            return
        }
        if case let .failed(
            code,
            frameCount: _
        ) = outcome {
            commitDecodingError(
                IRFFCheckError(code),
                generation: generation
            )
        }
    }

    private func enqueueDecodedFrame(
        _ frame: IRFFVideoFrame?,
        generation: UInt64
    ) {
        guard let frame else { return }
        while true {
            runtimeLock.lock()
            guard !runtimeCanceled,
                  runtimeError == nil,
                  runtimeGeneration ==
                    generation else {
                runtimeLock.unlock()
                frame.cancel()
                return
            }
            let capacity =
                decodeCapacitySnapshot()
            if capacity.canResumeOutput {
                _ = enqueueNonPooledFrameLocked(
                    frame
                )
                runtimeLock.unlock()
                return
            }
            runtimeLock.unlock()
            Thread.sleep(
                forTimeInterval: 0.002
            )
        }
    }

    @discardableResult
    private func admitExternalFrame(
        _ frame: IRFFVideoFrame,
        generation: UInt64
    ) -> Bool {
        runtimeLock.lock()
        guard !runtimeCanceled,
              runtimeError == nil,
              runtimeGeneration ==
                generation else {
            runtimeLock.unlock()
            frame.cancel()
            return false
        }
        let capacity =
            decodeCapacitySnapshot()
        guard capacity.canResumeOutput else {
            runtimeLock.unlock()
            frame.cancel()
            return false
        }
        let accepted =
            enqueueNonPooledFrameLocked(frame)
        runtimeLock.unlock()
        return accepted
    }

    private func enqueueReservedSoftwareFrame(
        _ frame: IRFFVideoFrame?,
        generation: UInt64
    ) {
        guard let frame else { return }
        runtimeLock.lock()
        guard !runtimeCanceled,
              runtimeError == nil,
              runtimeGeneration ==
                generation else {
            runtimeLock.unlock()
            frame.cancel()
            return
        }
        _ = frameQueue.enqueueSorted(
            frame,
            capacityClass: .pooled
        )
        runtimeLock.unlock()
    }

    private func waitForSoftwareFrameLease(
        generation: UInt64
    ) -> IRFFAVYUVVideoFrame? {
        var didNotifyBackpressure =
            false
        while true {
            runtimeLock.lock()
            guard !runtimeCanceled,
                  runtimeError == nil,
                  runtimeGeneration ==
                    generation else {
                runtimeLock.unlock()
                return nil
            }
            let capacity =
                decodeCapacitySnapshot()
            guard capacity.phase == .open else {
                runtimeLock.unlock()
                return nil
            }
            if capacity.canResumeOutput {
                // The observer is an internal deterministic test gate. It is
                // intentionally inside `runtimeLock`, immediately between the
                // shared-credit check and the only upward pool transition.
                softwareFrameWillLeaseObserver?()
                let leasedFrame =
                    framePool.leaseFrame()
                let videoFrame =
                    leasedFrame
                        as? IRFFAVYUVVideoFrame
                if leasedFrame != nil,
                   videoFrame == nil {
                    leasedFrame?.cancel()
                }
                runtimeLock.unlock()
                if let videoFrame {
                    return videoFrame
                }
            } else {
                runtimeLock.unlock()
            }
            if !didNotifyBackpressure {
                didNotifyBackpressure = true
                softwareFrameBackpressureObserver?()
            }
            Thread.sleep(
                forTimeInterval: 0.002
            )
        }
        return nil
    }

    func waitForSoftwareFrameLeaseForTesting(
        generation: UInt64
    ) -> IRFFAVYUVVideoFrame? {
        waitForSoftwareFrameLease(
            generation: generation
        )
    }

    private func accepts(
        generation: UInt64
    ) -> Bool {
        runtimeLock.lock()
        defer { runtimeLock.unlock() }
        return !runtimeCanceled &&
            runtimeError == nil &&
            runtimeGeneration == generation
    }

    private func populateVideoFrame(
        _ videoFrame:
            IRFFAVYUVVideoFrame,
        fromDecodedFrame frame:
            UnsafeMutablePointer<AVFrame>
    ) -> Bool {
        guard Self.shouldCreateYUVFrame(
            hasFrame: true,
            hasLuma: frame.pointee.data.0 != nil,
            hasChromaB: frame.pointee.data.1 != nil,
            hasChromaR: frame.pointee.data.2 != nil
        ) else {
            return false
        }
        videoFrame.setFrameData(frame, width: Int(codecContext.pointee.width), height: Int(codecContext.pointee.height))
        videoFrame.position = IRFFFrameTime.position(timestamp: frame.pointee.best_effort_timestamp, timebase: timebase)

        videoFrame.duration = Self.frameDuration(ticks: frame.pointee.duration,
                                                 repeatPicture: frame.pointee.repeat_pict,
                                                 timebase: timebase,
                                                 fps: fps)
        return true
    }

    private func enqueueVideoToolBoxOutputs(
        _ outputs: [IRFFVideoToolBox.Output],
        generation: UInt64
    ) {
        for output in outputs {
            enqueueDecodedFrame(
                videoFrame(
                    fromVideoToolBox: output
                ),
                generation: generation
            )
        }
    }

    private func videoFrame(
        fromVideoToolBox output:
            IRFFVideoToolBox.Output
    ) -> IRFFVideoFrame {
        let videoFrame = IRFFCVYUVVideoFrame(
            pixelBuffer: output.imageBuffer
        )
        videoFrame.position =
            Self.videoToolBoxFramePosition(
                presentationTimeStamp:
                    output
                        .presentationTimeStamp,
                packetTiming:
                    output.packetTiming,
                timebase: timebase
            )
        videoFrame.duration =
            Self.videoToolBoxFrameDuration(
                presentationDuration:
                    output
                        .presentationDuration,
                packetTiming:
                    output.packetTiming,
                timebase: timebase,
                fps: fps
            )
        return videoFrame
    }

    static func videoToolBoxFramePosition(
        presentationTimeStamp: CMTime,
        packetTiming:
            IRFFVideoToolBox.PacketTiming?,
        timebase: TimeInterval
    ) -> TimeInterval {
        let callbackPosition =
            CMTimeGetSeconds(
                presentationTimeStamp
            )
        guard !callbackPosition.isFinite ||
                callbackPosition < 0 else {
            return callbackPosition
        }
        guard let packetTiming else {
            return 0
        }
        return IRFFFrameTime.packetPosition(
            pts: packetTiming.pts,
            dts: packetTiming.dts,
            timebase: timebase
        )
    }

    static func videoToolBoxFrameDuration(
        presentationDuration: CMTime,
        packetTiming:
            IRFFVideoToolBox.PacketTiming?,
        timebase: TimeInterval,
        fps: TimeInterval
    ) -> TimeInterval {
        let callbackDuration =
            CMTimeGetSeconds(
                presentationDuration
            )
        guard !callbackDuration.isFinite ||
                callbackDuration <= 0 else {
            return callbackDuration
        }
        return frameDuration(
            ticks:
                packetTiming?.duration ?? 0,
            repeatPicture: 0,
            timebase: timebase,
            fps: fps
        )
    }

    @discardableResult
    func commitDecodingError(
        _ error: NSError?,
        generation: UInt64
    ) -> Bool {
        guard let error else { return false }
        return commitDecodingError(
            error,
            generation: generation,
            requiringPendingIdentifier:
                nil
        )
    }

    @discardableResult
    private func commitDecodingError(
        _ error: NSError,
        generation: UInt64,
        requiringPendingIdentifier:
            UInt64?
    ) -> Bool {
        transitionLock.lock()
        runtimeLock.lock()
        guard let invalidatedCompletions =
                beginDecodingErrorTransitionLocked(
                    error,
                    generation: generation,
                    requiringPendingIdentifier:
                        requiringPendingIdentifier
                ) else {
            runtimeLock.unlock()
            transitionLock.unlock()
            return false
        }
        runtimeLock.unlock()
        transitionLock.unlock()
        completeDecodingErrorTransition(
            error,
            generation: generation,
            invalidatedCompletions:
                invalidatedCompletions
        )
        return true
    }

    /// `transitionLock` and `runtimeLock` must be held. The first error owns
    /// the generation-wide transition and removes every pending reservation
    /// before any waiter can observe the error.
    private func beginDecodingErrorTransitionLocked(
        _ error: NSError,
        generation: UInt64,
        requiringPendingIdentifier:
            UInt64?
    ) -> [IRFFCustomVideoDecodeCompletion]? {
        guard !runtimeCanceled,
              runtimeGeneration == generation,
              runtimeError == nil else {
            return nil
        }
        customDecodeCondition.lock()
        if let identifier =
                requiringPendingIdentifier,
           pendingCustomDecodes[
                identifier
           ]?.generation != generation {
            customDecodeCondition.unlock()
            return nil
        }
        runtimeError = error
        runtimeTransitionRevision &+= 1
        let invalidatedCompletions =
            pendingCustomDecodes
                .values
                .compactMap(\.completion)
        pendingCustomDecodes.removeAll(
            keepingCapacity: true
        )
        customDecodeCondition.broadcast()
        customDecodeCondition.unlock()

        // The persistent token wakes a worker already sleeping in getItem()
        // and also drains packet ownership, including a queued EOF marker.
        _ = packetQueue.interrupt(
            generation: generation
        )
        return invalidatedCompletions
    }

    /// Completion invalidation and delegate reentry are external callbacks;
    /// both must remain outside transition/runtime/custom locks.
    private func completeDecodingErrorTransition(
        _ error: NSError,
        generation: UInt64,
        invalidatedCompletions:
            [IRFFCustomVideoDecodeCompletion]
    ) {
        for completion in
                invalidatedCompletions {
            completion.invalidate()
        }
        delegate?.videoDecoder(
            self,
            didError: error,
            generation: generation
        )
    }

    private func decodeAdmissionLocked()
        -> IRFFVideoDecodeAdmissionDiagnostics
    {
        let capacity =
            decodeCapacitySnapshot()
        return IRFFVideoDecodeAdmissionDiagnostics(
            capacity: capacity,
            queuedItemCount:
                packetQueue.count,
            maximumQueuedItemCount:
                maximumQueuedItemCount,
            acceptsPackets:
                !runtimeCanceled &&
                runtimeError == nil &&
                !runtimeEndOfFile &&
                capacity.phase == .open
        )
    }

    /// `runtimeLock` must be held so every upward occupancy transition is
    /// linearized with this exact union.
    private func decodeCapacitySnapshot()
        -> IRFFDecodeAdmission.Snapshot
    {
        let pool = framePool.diagnostics
        let queue = frameQueue.diagnostics
        let (poolOccupied, poolOverflow) =
            pool.leasedCount
                .addingReportingOverflow(
                    pool.playingCount
                )
        let pending =
            pendingCustomDecodeCountLocked()
        let (
            occupiedIncludingNonPooled,
            nonPooledOverflow
        ) = poolOccupied.addingReportingOverflow(
            queue.nonPooledCount
        )
        let (
            occupiedIncludingPending,
            pendingOverflow
        ) = occupiedIncludingNonPooled
            .addingReportingOverflow(
                pending
            )
        let overflow =
            poolOverflow ||
            nonPooledOverflow ||
            pendingOverflow
        let phase:
            IRFFDecodeAdmission.Phase =
                !runtimeCanceled &&
                runtimeError == nil &&
                pool.phase == .open &&
                queue.phase == .open
                ? .open
                : .closed
        return IRFFDecodeAdmission.Snapshot(
            limits: admissionLimits,
            occupiedFrameCount:
                overflow
                ? admissionLimits
                    .frameCapacity
                : min(
                    admissionLimits
                        .frameCapacity,
                    occupiedIncludingPending
                ),
            phase: phase
        )
    }

    private func registerCustomDecode(
        generation: UInt64
    ) -> IRFFCustomVideoDecodeCompletion? {
        while true {
            runtimeLock.lock()
            guard !runtimeCanceled,
                  runtimeError == nil,
                  runtimeGeneration ==
                    generation else {
                runtimeLock.unlock()
                return nil
            }
            let capacity =
                decodeCapacitySnapshot()
            guard capacity.phase == .open else {
                runtimeLock.unlock()
                return nil
            }
            guard capacity
                    .availableCredits > 0 else {
                runtimeLock.unlock()
                Thread.sleep(
                    forTimeInterval: 0.002
                )
                continue
            }

            customDecodeCondition.lock()
            var identifier =
                nextCustomDecodeID
            nextCustomDecodeID &+= 1
            while pendingCustomDecodes[
                    identifier
                  ] != nil {
                identifier =
                    nextCustomDecodeID
                nextCustomDecodeID &+= 1
            }
            let completion =
                IRFFCustomVideoDecodeCompletion {
                    [weak self]
                    result in
                    guard let self else {
                        result.reclaimFrame()
                        return false
                    }
                    return self
                        .resolveCustomDecode(
                            identifier:
                                identifier,
                            generation:
                                generation,
                            result: result
                        )
                }
            pendingCustomDecodes[
                identifier
            ] = PendingCustomDecode(
                generation: generation,
                completion: completion
            )
            customDecodeCondition.unlock()
            runtimeLock.unlock()
            return completion
        }
    }

    private func resolveCustomDecode(
        identifier: UInt64,
        generation: UInt64,
        result:
            IRFFCustomVideoDecodeCompletionResult
    ) -> Bool {
        if case let .failed(error) =
                result {
            return commitDecodingError(
                error as NSError,
                generation: generation,
                requiringPendingIdentifier:
                    identifier
            )
        }
        transitionLock.lock()
        runtimeLock.lock()
        guard !runtimeCanceled,
              runtimeError == nil,
              runtimeGeneration ==
                generation else {
            runtimeLock.unlock()
            transitionLock.unlock()
            result.reclaimFrame()
            return false
        }
        customDecodeCondition.lock()
        guard pendingCustomDecodes[
                identifier
              ]?.generation ==
                generation else {
            customDecodeCondition.unlock()
            runtimeLock.unlock()
            transitionLock.unlock()
            result.reclaimFrame()
            return false
        }
        let accepted: Bool
        switch result {
        case let .frame(frame):
            accepted =
                enqueueNonPooledFrameLocked(
                    frame
                )
        case .dropped:
            accepted = true
        case .failed:
            accepted = false
        }
        pendingCustomDecodes[
            identifier
        ] = nil
        customDecodeCondition.broadcast()
        customDecodeCondition.unlock()
        runtimeLock.unlock()
        transitionLock.unlock()
        return accepted
    }

    /// `runtimeLock` must be held so the shared capacity check and this
    /// upward transition are linearized. The queue owns the corresponding
    /// downward credit transition with the entry itself.
    @discardableResult
    private func enqueueNonPooledFrameLocked(
        _ frame: IRFFVideoFrame
    ) -> Bool {
        frameQueue.enqueueSorted(
            frame,
            capacityClass: .nonPooled
        ) == .accepted
    }

    private func waitForCustomDecodes(
        generation: UInt64,
        transitionRevision: UInt64
    ) -> Bool {
        customDecodeCondition.lock()
        while pendingCustomDecodes
                .values
                .contains(
                    where: {
                        $0.generation ==
                            generation
                    }
                ) {
            customDecodeCondition.wait()
        }
        customDecodeCondition.unlock()
        runtimeLock.lock()
        defer { runtimeLock.unlock() }
        return !runtimeCanceled &&
            runtimeError == nil &&
            runtimeGeneration ==
                generation &&
            runtimeTransitionRevision ==
                transitionRevision
    }

    private func pendingCustomDecodeCount(
        generation: UInt64
    ) -> Int {
        customDecodeCondition.lock()
        defer {
            customDecodeCondition.unlock()
        }
        return pendingCustomDecodes
            .values
            .reduce(into: 0) {
                count,
                pending in
                if pending.generation ==
                    generation {
                    count += 1
                }
            }
    }

    private func pendingCustomDecodeCountLocked()
        -> Int
    {
        customDecodeCondition.lock()
        defer {
            customDecodeCondition.unlock()
        }
        return pendingCustomDecodes.count
    }

    /// `runtimeLock` must be held before this method. This keeps invalidation
    /// ordered before any racing completion attempts.
    private func removePendingCustomDecodesLocked()
        -> [IRFFCustomVideoDecodeCompletion]
    {
        customDecodeCondition.lock()
        let completions =
            pendingCustomDecodes
                .values
                .compactMap(\.completion)
        pendingCustomDecodes
            .removeAll(
                keepingCapacity: true
            )
        customDecodeCondition.broadcast()
        customDecodeCondition.unlock()
        return completions
    }

    private func setDecoding(
        _ decoding: Bool,
        generation: UInt64
    ) {
        runtimeLock.lock()
        if decoding {
            if !runtimeCanceled,
               runtimeGeneration ==
                generation {
                runtimeDecodingGeneration =
                    generation
            }
        } else if runtimeDecodingGeneration ==
                    generation {
            runtimeDecodingGeneration = nil
        }
        runtimeLock.unlock()
    }

    private func runtimeSnapshot() -> RuntimeSnapshot {
        runtimeLock.lock()
        defer { runtimeLock.unlock() }
        return RuntimeSnapshot(
            canceled: runtimeCanceled,
            error: runtimeError,
            decoding:
                runtimeDecodingGeneration ==
                runtimeGeneration,
            paused: runtimePaused,
            endOfFile: runtimeEndOfFile,
            videoToolBoxEnable: runtimeVideoToolBoxEnable,
            maxDecodeDuration: runtimeMaxDecodeDuration,
            generation: runtimeGeneration,
            transitionRevision:
                runtimeTransitionRevision,
            backend: runtimeBackend
        )
    }

}

extension IRFFVideoDecoder: IRFFDecoderVideoOutput {
    func send(videoFrame: IRFFVideoFrame) {
        _ = trySend(videoFrame: videoFrame)
    }

    func trySend(
        videoFrame: IRFFVideoFrame
    ) -> Bool {
        admitExternalFrame(
            videoFrame,
            generation:
                runtimeSnapshot().generation
        )
    }
}
