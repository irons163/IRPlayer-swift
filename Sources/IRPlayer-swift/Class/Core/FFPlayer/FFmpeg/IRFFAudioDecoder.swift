//
//  IRFFAudioDecoder.swift
//  IRPlayer-swift
//
//  Created by irons on 2024/7/18.
//

import Foundation
import Accelerate
#if SWIFT_PACKAGE || DEBUG
internal import IRFFMpeg
internal import IRPlayerObjc
#else
@_implementationOnly import IRFFMpeg
@_implementationOnly import IRPlayerObjc
#endif

protocol IRFFAudioDecoderDelegate: AnyObject {
    func audioDecoder(_ audioDecoder: IRFFAudioDecoder, samplingRate: inout Float64)
    func audioDecoder(_ audioDecoder: IRFFAudioDecoder, channelCount: inout UInt32)
}

struct IRFFAudioFrameTransfer {
    let frame: IRFFAudioFrame
    let position: TimeInterval
    let duration: TimeInterval
    let size: Int
}

/// A render-owned frame plus metadata frozen at queue admission.
///
/// The audio callback owns `outputOffset`; decode and pool workers must not
/// mutate the frame until `finishAudioFrame` acknowledges this lease.
struct IRFFAudioRenderLease {
    let frame: IRFFAudioFrame
    let byteCount: Int
    var outputOffset: Int

    init(
        frame: IRFFAudioFrame,
        byteCount: Int,
        outputOffset: Int = 0
    ) {
        self.frame = frame
        self.byteCount = byteCount
        self.outputOffset = outputOffset
    }
}

enum IRFFAudioCodecPumpResult:
    Equatable,
    Sendable
{
    case needsInput
    case backpressured
    case endOfStream
    case canceled
    case failed(Int32)
}

/// Packet ownership is part of the result contract.
///
/// `consumed` means the decoder closed the packet, whether FFmpeg accepted it
/// or the generation rejected it terminally. `deferred` means FFmpeg has not
/// seen the packet and the caller retains the still-open owner for retry.
enum IRFFAudioPacketDecodeResult:
    Equatable,
    Sendable
{
    case consumed(IRFFAudioCodecPumpResult)
    case deferred
}

struct IRFFAudioDecodeAdmissionDiagnostics:
    Equatable,
    Sendable
{
    let capacity: IRFFDecodeAdmission.Snapshot
    let requiresOutputResume: Bool
    let acceptsPackets: Bool

    var hasPacketAdmissionCapacity: Bool {
        acceptsPackets &&
            !requiresOutputResume &&
            capacity.canAdmitPacket
    }

    var shouldThrottlePacketRead: Bool {
        !hasPacketAdmissionCapacity
    }
}

struct IRFFAudioDecoderHooks {
    var willEnqueueFrame: (() -> Void)?
    var didPublishInvalidation:
        ((UInt64) -> Void)?

    static let none =
        IRFFAudioDecoderHooks()
}

class IRFFAudioDecoder {

    static let packetAdmissionHeadroom = 8

    weak var delegate: IRFFAudioDecoderDelegate?
    private let codecContext:
        UnsafeMutablePointer<AVCodecContext>
    private let decodeFrame: IRFFDecodeFrame?
    private let timebase: TimeInterval
    private var samplingRate: Float64 = 0
    private var channelCount: UInt32 = 0
    private var resampleSession: IRFFAudioResampleSession?

    private let frameQueue: IRFFFrameQueue
    private let framePool: IRFFFramePool
    private let admissionPacketHeadroom: Int
    private let hooks:
        IRFFAudioDecoderHooks
    private let transitionLock = NSLock()
    private let generationLock = NSLock()
    private var storedGeneration: UInt64 = 0
    private var generationTransitionRevision:
        UInt64 = 0
    private var generationTransitioning = false
    private var generationClosed = false
    private let codecLock = NSLock()
    private var codecPhase:
        CodecPhase = .acceptingInput

    private enum CodecPhase {
        case acceptingInput
        case packetOutputPending
        case draining
        case endOfStream
        case closed
    }

    private struct PumpOutcome {
        let result: IRFFAudioCodecPumpResult
        let receivedFrameCount: Int
    }

    static func decoder(codecContext: UnsafeMutablePointer<AVCodecContext>, timebase: TimeInterval, delegate: IRFFAudioDecoderDelegate) -> IRFFAudioDecoder {
        return IRFFAudioDecoder(codecContext: codecContext, timebase: timebase, delegate: delegate)
    }

    init(
        codecContext: UnsafeMutablePointer<AVCodecContext>,
        timebase: TimeInterval,
        delegate: IRFFAudioDecoderDelegate,
        framePool: IRFFFramePool = .audioPool(),
        packetAdmissionHeadroom: Int =
            IRFFAudioDecoder
                .packetAdmissionHeadroom,
        hooks:
            IRFFAudioDecoderHooks = .none
    ) {
        self.codecContext = codecContext
        self.decodeFrame = IRFFDecodeFrame()
        self.timebase = timebase
        self.delegate = delegate
        self.frameQueue = IRFFFrameQueue()
        self.framePool = framePool
        self.admissionPacketHeadroom =
            packetAdmissionHeadroom
        self.hooks = hooks
        setupResampler()
    }

    private func setupResampler() {
        reloadAudioOutputInfo()
        updateResampler()
    }

    private func updateResampler() {
        guard let outputInfo = Self.swrOutputInfo(samplingRate: samplingRate, channelCount: channelCount),
              let inputInfo = Self.swrInputInfo(from: codecContext),
              codecContext.pointee.ch_layout.nb_channels > 0 else {
            resampleSession = nil
            return
        }

        let setup = IRFFAudioResampleSetup(
            outputSamplingRate:
                outputInfo.samplingRate,
            outputChannelCount:
                outputInfo.channelCount,
            inputSamplingRate:
                inputInfo.samplingRate,
            inputChannelLayout:
                codecContext.pointee.ch_layout,
            inputSampleFormat:
                inputInfo.sampleFormat
        )
        guard resampleSession?.matches(setup)
                != true else {
            return
        }
        resampleSession =
            IRFFAudioResampleSession(setup: setup)
    }

    func size() -> Int {
        return Int(frameQueue.size)
    }

    func isEmpty() -> Bool {
        return frameQueue.count <= 0
    }

    var decodeAdmission:
        IRFFAudioDecodeAdmissionDiagnostics
    {
        let capacity = capacitySnapshot()
        codecLock.lock()
        let phase = codecPhase
        codecLock.unlock()
        generationLock.lock()
        let generationIsClosed =
            generationClosed
        let generationIsReady =
            !generationClosed &&
            !generationTransitioning
        generationLock.unlock()

        let isClosed =
            phase == .closed ||
            generationIsClosed ||
            capacity.phase == .closed
        let effectiveCapacity =
            isClosed
            ? IRFFDecodeAdmission.Snapshot(
                limits: capacity.limits,
                occupiedFrameCount:
                    capacity.occupiedFrameCount,
                phase: .closed
            )
            : capacity
        return IRFFAudioDecodeAdmissionDiagnostics(
            capacity: effectiveCapacity,
            requiresOutputResume:
                phase == .packetOutputPending ||
                phase == .draining,
            acceptsPackets:
                phase == .acceptingInput &&
                generationIsReady &&
                !isClosed
        )
    }

    var hasPacketAdmissionCapacity: Bool {
        decodeAdmission
            .hasPacketAdmissionCapacity
    }

    static func sampleElementCount(numberOfFrames: Int, channelCount: UInt32) -> Int? {
        guard numberOfFrames > 0, channelCount > 0 else {
            return nil
        }
        let (count, overflow) =
            numberOfFrames.multipliedReportingOverflow(
                by: Int(channelCount)
            )
        return overflow ? nil : count
    }

    static func sampleByteCount(numberOfElements: Int) -> Int? {
        guard numberOfElements > 0 else { return nil }
        let (byteCount, overflow) =
            numberOfElements.multipliedReportingOverflow(
                by: MemoryLayout<Float>.size
            )
        return overflow ? nil : byteCount
    }

    static func fallbackDuration(sampleByteCount: Int, channelCount: UInt32, samplingRate: Float64) -> TimeInterval? {
        guard sampleByteCount > 0,
              channelCount > 0,
              samplingRate.isFinite,
              samplingRate > 0 else {
            return nil
        }

        let bytesPerSecond =
            Double(MemoryLayout<Float32>.size) *
            Double(channelCount) *
            samplingRate
        guard bytesPerSecond.isFinite,
              bytesPerSecond > 0 else {
            return nil
        }

        let duration =
            Double(sampleByteCount) / bytesPerSecond
        return duration.isFinite && duration > 0
            ? duration
            : nil
    }

    static func swrOutputInfo(samplingRate: Float64, channelCount: UInt32) -> (samplingRate: Int32, channelCount: Int32)? {
        guard samplingRate.isFinite,
              samplingRate > 0,
              samplingRate <= Float64(Int32.max),
              channelCount > 0,
              channelCount <= UInt32(Int32.max) else {
            return nil
        }
        return (
            Int32(samplingRate),
            Int32(channelCount)
        )
    }

    static func swrInputInfo(from codecContext: UnsafeMutablePointer<AVCodecContext>?) -> (samplingRate: Int32, channelCount: Int32, sampleFormat: AVSampleFormat)? {
        guard let codecContext else { return nil }
        let samplingRate = codecContext.pointee.sample_rate
        let channelCount =
            codecContext.pointee.ch_layout.nb_channels
        let sampleFormat = codecContext.pointee.sample_fmt
        guard samplingRate > 0,
              channelCount > 0,
              sampleFormat != AV_SAMPLE_FMT_NONE else {
            return nil
        }
        return (
            samplingRate,
            channelCount,
            sampleFormat
        )
    }

    static func decodedFrameDuration(ticks: Int64, timebase: TimeInterval, fallbackDuration: TimeInterval?) -> TimeInterval {
        if ticks > 0, timebase.isFinite, timebase > 0 {
            let duration = Double(ticks) * timebase
            if duration.isFinite, duration > 0 {
                return duration
            }
        }
        guard let fallbackDuration,
              fallbackDuration.isFinite,
              fallbackDuration > 0 else {
            return 0
        }
        return fallbackDuration
    }

    static func resampleRatio(outputSamplingRate: Float64, inputSamplingRate: Int32, outputChannelCount: UInt32, inputChannelCount: Int32) -> Int? {
        guard outputSamplingRate.isFinite,
              outputSamplingRate > 0,
              inputSamplingRate > 0,
              outputChannelCount > 0,
              inputChannelCount > 0 else {
            return nil
        }

        let samplingRatioValue =
            outputSamplingRate / Float64(inputSamplingRate)
        guard samplingRatioValue.isFinite,
              samplingRatioValue < Float64(Int.max) else {
            return nil
        }
        let samplingRatio =
            max(1, Int(ceil(samplingRatioValue)))

        let inputChannels = Int(inputChannelCount)
        let (channelNumerator, channelOverflow) =
            Int(outputChannelCount).addingReportingOverflow(
                inputChannels - 1
            )
        guard !channelOverflow else { return nil }
        let channelRatio =
            max(1, channelNumerator / inputChannels)

        let (audioRatio, audioOverflow) =
            samplingRatio.multipliedReportingOverflow(
                by: channelRatio
            )
        guard !audioOverflow else { return nil }
        let (ratio, ratioOverflow) =
            audioRatio.multipliedReportingOverflow(by: 2)
        guard !ratioOverflow, ratio > 0 else {
            return nil
        }
        return ratio
    }

    static func resampleFrameCapacity(inputFrameCount: Int32, ratio: Int) -> Int32? {
        guard inputFrameCount > 0,
              ratio > 0,
              ratio <= Int(Int32.max) else {
            return nil
        }
        let (capacity, overflow) =
            Int(inputFrameCount).multipliedReportingOverflow(
                by: ratio
            )
        guard !overflow,
              capacity > 0,
              capacity <= Int(Int32.max) else {
            return nil
        }
        return Int32(capacity)
    }

    static func packetDecodeResultIsFailure(_ result: Int32) -> Bool {
        return IRFFDecodeResult.isFailure(result)
    }

    static func shouldDecodePacket(hasData: Bool) -> Bool {
        return hasData
    }

    static func shouldDecodeFrame(hasFrame: Bool, hasPrimaryData: Bool) -> Bool {
        return hasFrame && hasPrimaryData
    }

    static func canUseDirectOutput(sampleFormat: AVSampleFormat) -> Bool {
        return sampleFormat == AV_SAMPLE_FMT_S16
    }

    func duration() -> TimeInterval {
        return frameQueue.duration
    }

    func flush() {
        _ = flush(generation: generation)
    }

    @discardableResult
    func invalidate(
        generation: UInt64
    ) -> Bool {
        transitionLock.lock()
        defer { transitionLock.unlock() }
        generationLock.lock()
        guard !generationClosed,
              generation >= storedGeneration else {
            generationLock.unlock()
            return false
        }
        storedGeneration = generation
        generationTransitionRevision &+= 1
        let transitionRevision =
            generationTransitionRevision
        generationTransitioning = true
        generationLock.unlock()
        hooks.didPublishInvalidation?(
            generation
        )

        // Changing the generation first cancels an in-flight pump. Waiting on
        // the codec gate then guarantees that no old receive can enqueue after
        // this queue flush completes.
        codecLock.lock()
        frameQueue.flush()
        framePool.flush()
        codecPhase = .acceptingInput
        avcodec_flush_buffers(codecContext)

        generationLock.lock()
        let didComplete =
            !generationClosed &&
            storedGeneration == generation &&
            generationTransitionRevision ==
                transitionRevision
        if didComplete {
            generationTransitioning = false
        }
        if generationClosed {
            codecPhase = .closed
        }
        generationLock.unlock()
        codecLock.unlock()
        return didComplete
    }

    @discardableResult
    func flush(
        generation: UInt64
    ) -> Bool {
        invalidate(generation: generation)
    }

    func destroy() {
        transitionLock.lock()
        defer { transitionLock.unlock() }
        generationLock.lock()
        generationClosed = true
        generationTransitionRevision &+= 1
        generationTransitioning = true
        storedGeneration &+= 1
        generationLock.unlock()
        codecLock.lock()
        codecPhase = .closed
        frameQueue.close()
        framePool.close()
        codecLock.unlock()
    }

    func waitForFrame() -> IRFFAudioFrame? {
        return frameQueue.waitForFrame() as? IRFFAudioFrame
    }

    func dequeueFrame() -> IRFFAudioFrame? {
        return frameQueue.dequeue() as? IRFFAudioFrame
    }

    func tryDequeueFrame() -> IRFFAudioFrameTransfer? {
        guard let transfer =
                frameQueue.tryDequeueTransfer(),
              let frame =
                transfer.frame as? IRFFAudioFrame else {
            return nil
        }
        return IRFFAudioFrameTransfer(
            frame: frame,
            position: transfer.position,
            duration: transfer.duration,
            size: transfer.size
        )
    }

    func putPacket(
        _ packet: IRFFPacket
    ) -> IRFFAudioPacketDecodeResult {
        putPacket(
            packet,
            generation: generation
        )
    }

    func putPacket(
        _ packet: IRFFPacket,
        generation: UInt64
    ) -> IRFFAudioPacketDecodeResult {
        guard accepts(
            generation: generation
        ) else {
            packet.close()
            return .consumed(.canceled)
        }
        guard let snapshot = packet.snapshot,
              Self.shouldDecodePacket(
                  hasData: snapshot.hasData
              ) else {
            packet.close()
            return .consumed(.needsInput)
        }

        codecLock.lock()
        defer { codecLock.unlock() }
        guard accepts(
            generation: generation
        ) else {
            packet.close()
            return .consumed(.canceled)
        }

        switch prepareForInputLocked(
            generation: generation
        ).result {
        case .needsInput:
            break
        case .backpressured:
            return .deferred
        case .endOfStream:
            packet.close()
            return .consumed(.endOfStream)
        case .canceled:
            packet.close()
            return .consumed(.canceled)
        case let .failed(code):
            packet.close()
            return .consumed(.failed(code))
        }
        guard capacitySnapshot()
                .canAdmitPacket else {
            return .deferred
        }

        var submission:
            IRFFAudioPacketDecodeResult =
                .consumed(.failed(-1))
        let didBorrow = packet.withPacket {
            borrowedPacket in
            var borrowedPacket = borrowedPacket
            submission = submitPacketLocked(
                &borrowedPacket,
                generation: generation
            )
            return true
        }
        guard didBorrow else {
            packet.close()
            return .consumed(.failed(-1))
        }
        if case .consumed = submission {
            packet.close()
        }
        return submission
    }

    func resumePendingOutput(
        generation: UInt64
    ) -> IRFFAudioCodecPumpResult {
        codecLock.lock()
        defer { codecLock.unlock() }
        guard accepts(
            generation: generation
        ) else {
            return .canceled
        }
        switch codecPhase {
        case .acceptingInput:
            return .needsInput
        case .packetOutputPending,
             .draining:
            return pumpPendingOutputLocked(
                generation: generation
            ).result
        case .endOfStream:
            return .endOfStream
        case .closed:
            return .canceled
        }
    }

    func drain(
        generation: UInt64
    ) -> IRFFAudioCodecPumpResult {
        codecLock.lock()
        defer { codecLock.unlock() }
        guard accepts(
            generation: generation
        ) else {
            return .canceled
        }

        let pendingOutcome =
            prepareForInputLocked(
                generation: generation
            )
        switch pendingOutcome.result {
        case .needsInput:
            break
        case .backpressured,
             .endOfStream,
             .canceled,
             .failed:
            return pendingOutcome.result
        }

        while true {
            guard accepts(
                generation: generation
            ) else {
                return .canceled
            }
            guard capacitySnapshot()
                    .canResumeOutput else {
                return .backpressured
            }

            let sendResult =
                avcodec_send_packet(
                    codecContext,
                    nil
                )
            if sendResult >= 0 {
                codecPhase = .draining
                return pumpPendingOutputLocked(
                    generation: generation
                ).result
            }
            if sendResult == IR_AVERROR_EOF {
                codecPhase = .endOfStream
                return .endOfStream
            }
            guard sendResult ==
                    AVERROR(EAGAIN) else {
                codecPhase = .acceptingInput
                return .failed(sendResult)
            }

            codecPhase = .packetOutputPending
            let outcome =
                pumpPendingOutputLocked(
                    generation: generation
                )
            switch outcome.result {
            case .needsInput:
                guard outcome.receivedFrameCount > 0 else {
                    codecPhase = .acceptingInput
                    return .failed(sendResult)
                }
                continue
            case .backpressured,
                 .endOfStream,
                 .canceled,
                 .failed:
                return outcome.result
            }
        }
    }

    private func submitPacketLocked(
        _ packet: inout AVPacket,
        generation: UInt64
    ) -> IRFFAudioPacketDecodeResult {
        while true {
            guard accepts(
                generation: generation
            ) else {
                return .consumed(.canceled)
            }
            guard capacitySnapshot()
                    .canAdmitPacket else {
                return .deferred
            }

            let sendResult =
                avcodec_send_packet(
                    codecContext,
                    &packet
                )
            if sendResult >= 0 {
                codecPhase =
                    .packetOutputPending
                return .consumed(
                    pumpPendingOutputLocked(
                        generation: generation
                    ).result
                )
            }
            if sendResult == IR_AVERROR_EOF {
                codecPhase = .endOfStream
                return .consumed(.endOfStream)
            }
            guard sendResult ==
                    AVERROR(EAGAIN) else {
                codecPhase = .acceptingInput
                return .consumed(
                    .failed(sendResult)
                )
            }

            codecPhase = .packetOutputPending
            let outcome =
                pumpPendingOutputLocked(
                    generation: generation
                )
            switch outcome.result {
            case .needsInput:
                guard outcome.receivedFrameCount > 0 else {
                    codecPhase = .acceptingInput
                    return .consumed(
                        .failed(sendResult)
                    )
                }
                continue
            case .backpressured:
                return .deferred
            case .endOfStream:
                return .consumed(.endOfStream)
            case .canceled:
                return .consumed(.canceled)
            case let .failed(code):
                return .consumed(.failed(code))
            }
        }
    }

    private func prepareForInputLocked(
        generation: UInt64
    ) -> PumpOutcome {
        switch codecPhase {
        case .acceptingInput:
            return PumpOutcome(
                result: .needsInput,
                receivedFrameCount: 0
            )
        case .packetOutputPending:
            return pumpPendingOutputLocked(
                generation: generation
            )
        case .draining:
            return pumpPendingOutputLocked(
                generation: generation
            )
        case .endOfStream:
            return PumpOutcome(
                result: .endOfStream,
                receivedFrameCount: 0
            )
        case .closed:
            return PumpOutcome(
                result: .canceled,
                receivedFrameCount: 0
            )
        }
    }

    private func pumpPendingOutputLocked(
        generation: UInt64
    ) -> PumpOutcome {
        guard let decodeFrame else {
            return PumpOutcome(
                result: .failed(-1),
                receivedFrameCount: 0
            )
        }
        var receivedFrameCount = 0

        while true {
            guard accepts(
                generation: generation
            ) else {
                return PumpOutcome(
                    result: .canceled,
                    receivedFrameCount:
                        receivedFrameCount
                )
            }
            guard capacitySnapshot()
                    .canResumeOutput else {
                return PumpOutcome(
                    result: .backpressured,
                    receivedFrameCount:
                        receivedFrameCount
                )
            }
            guard let audioFrame =
                    framePool.leaseFrame()
                        as? IRFFAudioFrame else {
                let capacity = capacitySnapshot()
                let result:
                    IRFFAudioCodecPumpResult =
                        capacity.phase == .closed ||
                        !accepts(
                            generation: generation
                        )
                        ? .canceled
                        : capacity.canResumeOutput
                            ? .failed(-1)
                            : .backpressured
                return PumpOutcome(
                    result: result,
                    receivedFrameCount:
                        receivedFrameCount
                )
            }

            var receiveResult: Int32 = -1
            var didPopulateFrame = false
            let didBorrow = decodeFrame.withFrame {
                decodedFrame in
                receiveResult =
                    avcodec_receive_frame(
                        codecContext,
                        decodedFrame
                    )
                if receiveResult >= 0 {
                    didPopulateFrame =
                        autoreleasepool {
                            decode(
                                frame: decodedFrame,
                                into: audioFrame
                            )
                        }
                }
                return true
            }
            guard didBorrow else {
                audioFrame.cancel()
                codecPhase = .acceptingInput
                return PumpOutcome(
                    result: .failed(-1),
                    receivedFrameCount:
                        receivedFrameCount
                )
            }

            if receiveResult >= 0 {
                let (nextFrameCount, overflow) =
                    receivedFrameCount
                        .addingReportingOverflow(1)
                guard !overflow else {
                    audioFrame.cancel()
                    codecPhase = .acceptingInput
                    return PumpOutcome(
                        result: .failed(-1),
                        receivedFrameCount:
                            receivedFrameCount
                    )
                }
                receivedFrameCount =
                    nextFrameCount

                guard accepts(
                    generation: generation
                ) else {
                    audioFrame.cancel()
                    return PumpOutcome(
                        result: .canceled,
                        receivedFrameCount:
                            receivedFrameCount
                    )
                }
                guard didPopulateFrame else {
                    audioFrame.cancel()
                    codecPhase = .acceptingInput
                    return PumpOutcome(
                        result: .failed(-1),
                        receivedFrameCount:
                            receivedFrameCount
                    )
                }
                hooks.willEnqueueFrame?()
                guard frameQueue.enqueue(audioFrame) ==
                        .accepted else {
                    codecPhase = .acceptingInput
                    return PumpOutcome(
                        result: .failed(-1),
                        receivedFrameCount:
                            receivedFrameCount
                    )
                }
                continue
            }

            audioFrame.cancel()
            if receiveResult ==
                AVERROR(EAGAIN) {
                if codecPhase == .draining {
                    codecPhase =
                        .acceptingInput
                    return PumpOutcome(
                        result:
                            .failed(receiveResult),
                        receivedFrameCount:
                            receivedFrameCount
                    )
                }
                codecPhase = .acceptingInput
                return PumpOutcome(
                    result: .needsInput,
                    receivedFrameCount:
                        receivedFrameCount
                )
            }
            if receiveResult ==
                IR_AVERROR_EOF {
                codecPhase = .endOfStream
                return PumpOutcome(
                    result: .endOfStream,
                    receivedFrameCount:
                        receivedFrameCount
                )
            }

            codecPhase = .acceptingInput
            return PumpOutcome(
                result: .failed(receiveResult),
                receivedFrameCount:
                    receivedFrameCount
            )
        }
    }

    private func capacitySnapshot()
        -> IRFFDecodeAdmission.Snapshot
    {
        let pool = framePool.diagnostics
        let limits = IRFFDecodeAdmission.Limits(
            frameCapacity:
                pool.maximumCapacity,
            packetHeadroom:
                admissionPacketHeadroom
        )
        let (occupiedFrameCount, overflow) =
            pool.leasedCount
                .addingReportingOverflow(
                    pool.playingCount
                )
        let phase: IRFFDecodeAdmission.Phase =
            pool.phase == .open
            ? .open
            : .closed
        return IRFFDecodeAdmission.Snapshot(
            limits: limits,
            occupiedFrameCount:
                overflow
                ? limits.frameCapacity
                : occupiedFrameCount,
            phase: phase
        )
    }

    private var generation: UInt64 {
        generationLock.lock()
        defer { generationLock.unlock() }
        return storedGeneration
    }

    private func accepts(
        generation: UInt64
    ) -> Bool {
        generationLock.lock()
        defer { generationLock.unlock() }
        return !generationClosed &&
            !generationTransitioning &&
            storedGeneration == generation
    }

    private func decode(
        frame decodedFrame:
            UnsafeMutablePointer<AVFrame>,
        into audioFrame: IRFFAudioFrame
    ) -> Bool {
        guard Self.shouldDecodeFrame(
            hasFrame: true,
            hasPrimaryData:
                decodedFrame.pointee.data.0 != nil
        ) else {
            return false
        }

        reloadAudioOutputInfo()
        updateResampler()

        if let resampleSession {
            guard Self.swrOutputInfo(
                samplingRate: samplingRate,
                channelCount: channelCount
            ) != nil,
                  let ratio = Self.resampleRatio(outputSamplingRate: samplingRate,
                                                 inputSamplingRate: codecContext.pointee.sample_rate,
                                                 outputChannelCount: channelCount,
                                                 inputChannelCount: codecContext.pointee.ch_layout.nb_channels),
                  let frameCapacity = Self.resampleFrameCapacity(inputFrameCount: decodedFrame.pointee.nb_samples, ratio: ratio) else {
                return false
            }
            let outcome =
                resampleSession.withConvertedSamples(
                    from: decodedFrame,
                    outputFrameCapacity:
                        frameCapacity
                ) { samples, numberOfFrames in
                    populate(
                        audioFrame,
                        from: samples,
                        numberOfFrames:
                            numberOfFrames,
                        decodedFrame:
                            decodedFrame
                    )
                }
            if case let .ffmpegError(code) = outcome {
                let error: Error? =
                    IRFFCheckError(code)
                IRFFErrorLog(
                    "audio codec error : "
                        + "\(String(describing: error))"
                )
            }
            guard case .converted = outcome else {
                return false
            }
        } else {
            if !Self.canUseDirectOutput(sampleFormat: codecContext.pointee.sample_fmt) {
                IRFFErrorLog("audio format error")
                return false
            }
            guard let decodedData =
                    decodedFrame.pointee.data.0,
                  let numberOfElements =
                    Self.sampleElementCount(
                        numberOfFrames:
                            Int(
                                decodedFrame
                                    .pointee.nb_samples
                        ),
                        channelCount: channelCount
                    ) else {
                return false
            }
            let samples = UnsafeBufferPointer(
                start: UnsafeRawPointer(decodedData)
                    .assumingMemoryBound(
                        to: Int16.self
                    ),
                count: numberOfElements
            )
            guard populate(
                audioFrame,
                from: samples,
                numberOfFrames:
                    Int(
                        decodedFrame
                            .pointee.nb_samples
                    ),
                decodedFrame: decodedFrame
            ) else {
                return false
            }
        }

        return true
    }

    private func populate(
        _ audioFrame: IRFFAudioFrame,
        from inputSamples:
            UnsafeBufferPointer<Int16>,
        numberOfFrames: Int,
        decodedFrame:
            UnsafeMutablePointer<AVFrame>
    ) -> Bool {
        guard let numberOfElements =
                Self.sampleElementCount(
                    numberOfFrames: numberOfFrames,
                    channelCount: channelCount
                ),
              numberOfElements
                == inputSamples.count,
              let sampleByteCount =
                Self.sampleByteCount(
                    numberOfElements:
                        numberOfElements
                ),
              let inputBaseAddress =
                inputSamples.baseAddress else {
            return false
        }

        audioFrame.setSamplesLength(sampleByteCount)
        var scale:
            Float32 = 1.0 / Float32(Int16.max)
        guard audioFrame.activeSampleCount
                == numberOfElements,
              audioFrame.withMutableSamples({
                  samples in
                  guard let baseAddress =
                          samples.baseAddress else {
                      return false
                  }
                  vDSP_vflt16(
                      inputBaseAddress,
                      1,
                      baseAddress,
                      1,
                      vDSP_Length(numberOfElements)
                  )
                  vDSP_vsmul(
                      baseAddress,
                      1,
                      &scale,
                      baseAddress,
                      1,
                      vDSP_Length(numberOfElements)
                  )
                  return true
              }) else {
            return false
        }

        audioFrame.position = IRFFFrameTime.position(
            timestamp:
                decodedFrame
                    .pointee.best_effort_timestamp,
            timebase: timebase
        )
        let fallbackDuration = Self.fallbackDuration(
            sampleByteCount: sampleByteCount,
            channelCount: channelCount,
            samplingRate: samplingRate
        )
        audioFrame.duration =
            Self.decodedFrameDuration(
                ticks: decodedFrame.pointee.duration,
                timebase: timebase,
                fallbackDuration: fallbackDuration
            )
        return true
    }

    private func reloadAudioOutputInfo() {
        delegate?.audioDecoder(self, samplingRate: &samplingRate)
        delegate?.audioDecoder(self, channelCount: &channelCount)
    }

    deinit {
        IRPlayerLog("IRFFAudioDecoder release")
    }
}
