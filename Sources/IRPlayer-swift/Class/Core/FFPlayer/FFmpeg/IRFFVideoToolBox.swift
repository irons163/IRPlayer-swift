//
//  IRFFVideoToolBox.swift
//  IRPlayer-swift
//
//  Created by irons on 2024/7/25.
//

import CoreMedia
import CoreVideo
import Foundation
#if SWIFT_PACKAGE || DEBUG
internal import IRFFMpeg
#else
@_implementationOnly import IRFFMpeg
#endif
import VideoToolbox

enum IRFFVideoToolBoxErrorCode: Error, Equatable {
    case extradataSize
    case extradataData
    case createFormatDescription
    case createSession
    case notH264
    case sessionUnavailable
}

final class IRFFVideoToolBox {
    struct PacketTiming:
        Equatable,
        Sendable
    {
        let pts: Int64
        let dts: Int64
        let duration: Int64

        init(
            pts: Int64,
            dts: Int64,
            duration: Int64
        ) {
            self.pts = pts
            self.dts = dts
            self.duration = duration
        }

        init(packet: AVPacket) {
            self.init(
                pts: packet.pts,
                dts: packet.dts,
                duration: packet.duration
            )
        }
    }

    final class SubmissionContext:
        @unchecked Sendable
    {
        let packetTiming: PacketTiming

        init(packetTiming: PacketTiming) {
            self.packetTiming = packetTiming
        }
    }

    struct Output {
        let imageBuffer: CVImageBuffer
        let presentationTimeStamp: CMTime
        let presentationDuration: CMTime
        let packetTiming: PacketTiming?
    }

    enum DecodeResult {
        case notAvailable
        case accepted(outputs: [Output])
        case failed(status: OSStatus)
    }

    struct Generation {
        let session: VTDecompressionSession
        let formatDescription: CMFormatDescription
        let callbackState: IRFFVideoToolBoxCallbackState
        let callbackReference: UnsafeMutableRawPointer
        let convertsThreeByteNALUnits: Bool
    }

    typealias Diagnostics = IRFFVideoToolBoxSession<Generation>.Diagnostics

    static let decodeFrameFlags:
        VTDecodeFrameFlags =
            ._EnableTemporalProcessing

    private let codecContext: UnsafeMutablePointer<AVCodecContext>
    private let timebase: TimeInterval
    private let operationLock = NSLock()
    private let session = IRFFVideoToolBoxSession<Generation>()

    var diagnostics: Diagnostics {
        session.diagnostics
    }

    init(
        codecContext:
            UnsafeMutablePointer<AVCodecContext>,
        timebase: TimeInterval = 0
    ) {
        self.codecContext = codecContext
        self.timebase = timebase
    }

    static func videoToolBox(
        with codecContext:
            UnsafeMutablePointer<AVCodecContext>,
        timebase: TimeInterval = 0
    ) -> IRFFVideoToolBox {
        IRFFVideoToolBox(
            codecContext: codecContext,
            timebase: timebase
        )
    }

    func trySetupVTSession() -> Bool {
        withOperation {
            trySetupVTSessionLocked()
        }
    }

    func setupVTSession() throws {
        try withOperation {
            if session.diagnostics.phase == .active {
                return
            }
            try setupVTSessionLocked()
        }
    }

    func cleanVTSession() {
        withOperation {
            resetSessionLocked()
        }
    }

    func cleanDecodeInfo() {
        withOperation {
            session.withResource(default: ()) {
                $0.callbackState.clearSnapshot()
            }
        }
    }

    func sendPacket(
        _ packet: AVPacket
    ) -> DecodeResult {
        withOperation {
            guard trySetupVTSessionLocked(),
                  let packetPayload = Self.packetPayload(for: packet) else {
                return .notAvailable
            }

            return session.withResource(
                default: DecodeResult.notAvailable
            ) { generation in
                guard let blockBuffer = makeBlockBuffer(
                    from: packetPayload,
                    convertsThreeByteNALUnits:
                        generation.convertsThreeByteNALUnits
                ),
                let sampleBuffer = Self.makeSampleBuffer(
                    blockBuffer: blockBuffer,
                    formatDescription:
                        generation
                            .formatDescription,
                    timing:
                        Self.sampleTiming(
                            for: packet,
                            timebase: timebase
                        ),
                    sampleSize:
                        CMBlockBufferGetDataLength(
                            blockBuffer
                        )
                ) else {
                    return .notAvailable
                }

                let status = Self.submitFrame(
                    packetTiming:
                        PacketTiming(
                            packet: packet
                        )
                ) { sourceFrameRefCon in
                    VTDecompressionSessionDecodeFrame(
                        generation.session,
                        sampleBuffer: sampleBuffer,
                        flags:
                            Self.decodeFrameFlags,
                        frameRefcon:
                            sourceFrameRefCon,
                        infoFlagsOut: nil
                    )
                }
                return Self.classifyDecodeResult(
                    status: status,
                    events:
                        generation
                            .callbackState
                            .takeEvents()
                )
            }
        }
    }

    func finishDelayedFrames() -> DecodeResult {
        withOperation {
            session.withResource(
                default: DecodeResult.notAvailable
            ) { generation in
                Self.drainDelayedFrames(
                    callbackState:
                        generation.callbackState
                ) {
                    VTDecompressionSessionWaitForAsynchronousFrames(
                        generation.session
                    )
                }
            }
        }
    }

    static func drainDelayedFrames(
        callbackState:
            IRFFVideoToolBoxCallbackState,
        waitForFrames: () -> OSStatus
    ) -> DecodeResult {
        let status = waitForFrames()
        return classifyDecodeResult(
            status: status,
            events: callbackState.takeEvents()
        )
    }

    static func submitFrame(
        packetTiming: PacketTiming,
        decode:
            (UnsafeMutableRawPointer)
                -> OSStatus
    ) -> OSStatus {
        let reference =
            Unmanaged.passRetained(
                SubmissionContext(
                    packetTiming:
                        packetTiming
                )
            )
            .toOpaque()
        let status = decode(reference)
        if status != noErr {
            releaseSubmissionReference(
                reference
            )
        }
        return status
    }

    private static func consumeSubmissionTiming(
        _ reference:
            UnsafeMutableRawPointer?
    ) -> PacketTiming? {
        guard let reference else {
            return nil
        }
        return Unmanaged<SubmissionContext>
            .fromOpaque(reference)
            .takeRetainedValue()
            .packetTiming
    }

    private static func releaseSubmissionReference(
        _ reference:
            UnsafeMutableRawPointer
    ) {
        Unmanaged<SubmissionContext>
            .fromOpaque(reference)
            .release()
    }

    static func classifyDecodeResult(
        status: OSStatus,
        events:
            [IRFFVideoToolBoxCallbackState.Event]
    ) -> DecodeResult {
        guard status == noErr else {
            return .failed(status: status)
        }
        if let failedEvent =
                events.first(
                    where: {
                        $0.status != noErr
                    }
                ) {
            return .failed(
                status: failedEvent.status
            )
        }
        return .accepted(
            outputs:
                events.compactMap { event in
                    guard !event.infoFlags
                            .contains(
                                .frameInterrupted
                            ),
                          !event.infoFlags
                            .contains(
                                .frameDropped
                            ),
                          let imageBuffer =
                            event.imageBuffer else {
                        return nil
                    }
                    return Output(
                        imageBuffer: imageBuffer,
                        presentationTimeStamp:
                            event
                                .presentationTimeStamp,
                        presentationDuration:
                            event
                                .presentationDuration,
                        packetTiming:
                            event.packetTiming
                    )
                }
        )
    }

    func imageBuffer() -> CVImageBuffer? {
        session.withResource(
            default: Optional<CVImageBuffer>.none
        ) { generation in
            let callback = generation.callbackState.snapshot
            guard callback.status == noErr,
                  !callback.infoFlags
                    .contains(
                        .frameInterrupted
                    ),
                  !callback.infoFlags
                    .contains(
                        .frameDropped
                    ) else {
                return nil
            }
            return callback.imageBuffer
        }
    }

    func flush() {
        withOperation {
            resetSessionLocked()
        }
    }

    func close() {
        withOperation {
            closeSessionLocked()
        }
    }

    static func handleOutputCallback(
        refCon: UnsafeMutableRawPointer?,
        sourceFrameRefCon:
            UnsafeMutableRawPointer? = nil,
        status: OSStatus,
        infoFlags: VTDecodeInfoFlags = [],
        imageBuffer: CVImageBuffer?,
        presentationTimeStamp: CMTime =
            .invalid,
        presentationDuration: CMTime =
            .invalid
    ) {
        let packetTiming =
            consumeSubmissionTiming(
                sourceFrameRefCon
            )
        guard let refCon else { return }
        let callbackState = Unmanaged<IRFFVideoToolBoxCallbackState>
            .fromOpaque(refCon)
            .takeUnretainedValue()
        callbackState.publish(
            status: status,
            infoFlags: infoFlags,
            imageBuffer: imageBuffer,
            packetTiming: packetTiming,
            presentationTimeStamp:
                presentationTimeStamp,
            presentationDuration:
                presentationDuration
        )
    }

    private func trySetupVTSessionLocked() -> Bool {
        if session.diagnostics.phase == .active {
            return true
        }
        do {
            try setupVTSessionLocked()
            return session.diagnostics.phase == .active
        } catch {
            return false
        }
    }

    private func setupVTSessionLocked() throws {
        guard let ticket = session.beginSetup() else {
            throw IRFFVideoToolBoxErrorCode.sessionUnavailable
        }

        do {
            let generation = try makeGeneration()
            guard session.install(generation, for: ticket) else {
                Self.tearDown(generation)
                throw IRFFVideoToolBoxErrorCode.sessionUnavailable
            }
        } catch {
            session.cancelSetup(ticket)
            throw error
        }
    }

    private func makeGeneration() throws -> Generation {
        let codecID = codecContext.pointee.codec_id
        let extradata = codecContext.pointee.extradata
        let extradataSize = codecContext.pointee.extradata_size
        if let validationError = Self.setupValidationError(
            codecID: codecID,
            extradata: extradata,
            extradataSize: extradataSize,
            firstExtradataByte: extradata?[0]
        ) {
            throw validationError
        }
        guard let extradata else {
            throw IRFFVideoToolBoxErrorCode.extradataSize
        }

        let nalLength = Self.nalLengthSizeDecision(for: extradata[4])
        var normalizedExtradata = Array(
            UnsafeBufferPointer(
                start: UnsafePointer(extradata),
                count: Int(extradataSize)
            )
        )
        normalizedExtradata[4] = nalLength.normalizedMarker
        let formatDescription =
            normalizedExtradata.withUnsafeBufferPointer {
                buffer -> CMFormatDescription? in
                guard let baseAddress =
                        buffer.baseAddress else {
                    return nil
                }
                return Self.createFormatDescription(
                    codecType: kCMVideoCodecType_H264,
                    width: codecContext.pointee.width,
                    height: codecContext.pointee.height,
                    extradata: baseAddress,
                    extradataSize: Int32(buffer.count)
                )
            }
        guard let formatDescription else {
            throw IRFFVideoToolBoxErrorCode.createFormatDescription
        }

        let callbackState = IRFFVideoToolBoxCallbackState()
        let callbackReference = UnsafeMutableRawPointer(
            Unmanaged.passRetained(callbackState).toOpaque()
        )
        var callbackRecord = VTDecompressionOutputCallbackRecord(
            decompressionOutputCallback: Self.outputCallback,
            decompressionOutputRefCon: callbackReference
        )
        var decompressionSession: VTDecompressionSession?
        let status = VTDecompressionSessionCreate(
            allocator: kCFAllocatorDefault,
            formatDescription: formatDescription,
            decoderSpecification: nil,
            imageBufferAttributes: destinationPixelBufferAttributes,
            outputCallback: &callbackRecord,
            decompressionSessionOut: &decompressionSession
        )

        guard status == noErr, let decompressionSession else {
            if let decompressionSession {
                VTDecompressionSessionInvalidate(decompressionSession)
            }
            Unmanaged<IRFFVideoToolBoxCallbackState>
                .fromOpaque(callbackReference)
                .release()
            throw IRFFVideoToolBoxErrorCode.createSession
        }

        return Generation(
            session: decompressionSession,
            formatDescription: formatDescription,
            callbackState: callbackState,
            callbackReference: callbackReference,
            convertsThreeByteNALUnits:
                nalLength.shouldConvertThreeByteNALUnits
        )
    }

    private var destinationPixelBufferAttributes: CFDictionary {
        [
            kCVPixelBufferPixelFormatTypeKey:
                kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
            kCVPixelBufferWidthKey: codecContext.pointee.width,
            kCVPixelBufferHeightKey: codecContext.pointee.height,
            kCVPixelBufferMetalCompatibilityKey: true,
            kCVPixelBufferIOSurfacePropertiesKey: [:]
        ] as CFDictionary
    }

    private func makeBlockBuffer(
        from packetPayload: PacketPayload,
        convertsThreeByteNALUnits: Bool
    ) -> CMBlockBuffer? {
        if convertsThreeByteNALUnits {
            return makeConvertedBlockBuffer(from: packetPayload)
        }

        return Self.makeOwnedBlockBuffer(
            from: packetPayload
        )
    }

    private func makeConvertedBlockBuffer(
        from packetPayload: PacketPayload
    ) -> CMBlockBuffer? {
        guard Self.threeByteNALUnitsAreBounded(in: packetPayload) else {
            return nil
        }

        var ioContext: UnsafeMutablePointer<AVIOContext>?
        guard avio_open_dyn_buf(&ioContext) >= 0, let ioContext else {
            return nil
        }

        let end = packetPayload.end
        var nalStart = packetPayload.data
        while nalStart < end {
            let nalSize = (UInt32(nalStart[0]) << 16)
                | (UInt32(nalStart[1]) << 8)
                | UInt32(nalStart[2])
            avio_wb32(ioContext, nalSize)
            nalStart += 3
            avio_write(ioContext, nalStart, Int32(nalSize))
            nalStart += UnsafeMutablePointer<UInt8>.Stride(nalSize)
        }

        var demuxBuffer: UnsafeMutablePointer<UInt8>?
        let demuxSize = avio_close_dyn_buf(ioContext, &demuxBuffer)
        guard let convertedPayload = Self.convertedNALBlockPayload(
            memoryBlock: demuxBuffer,
            demuxSize: demuxSize,
            packetSize: packetPayload.size
        ) else {
            av_free(demuxBuffer)
            return nil
        }

        var customBlockSource = convertedPayload.customBlockSource
        var blockBuffer: CMBlockBuffer?
        let status = CMBlockBufferCreateWithMemoryBlock(
            allocator: nil,
            memoryBlock: convertedPayload.memoryBlock,
            blockLength: convertedPayload.blockLength,
            blockAllocator: kCFAllocatorNull,
            customBlockSource: &customBlockSource,
            offsetToData: 0,
            dataLength: convertedPayload.dataLength,
            flags: 0,
            blockBufferOut: &blockBuffer
        )
        if status != noErr {
            av_free(convertedPayload.memoryBlock)
            return nil
        }
        return blockBuffer
    }

    private func resetSessionLocked() {
        session.reset(Self.tearDown)
    }

    private func closeSessionLocked() {
        session.close(Self.tearDown)
    }

    private static func tearDown(_ generation: Generation) {
        tearDownGeneration(
            waitForFrames: {
                _ =
                    VTDecompressionSessionWaitForAsynchronousFrames(
                        generation.session
                    )
            },
            invalidateSession: {
                VTDecompressionSessionInvalidate(
                    generation.session
                )
            },
            discardCallbacks: {
                generation.callbackState.reset()
            },
            releaseCallbackReference: {
                Unmanaged<IRFFVideoToolBoxCallbackState>
                    .fromOpaque(
                        generation.callbackReference
                    )
                    .release()
            }
        )
    }

    static func tearDownGeneration(
        waitForFrames: () -> Void,
        invalidateSession: () -> Void,
        discardCallbacks: () -> Void,
        releaseCallbackReference: () -> Void
    ) {
        waitForFrames()
        invalidateSession()
        discardCallbacks()
        releaseCallbackReference()
    }

    private func withOperation<Result>(_ body: () throws -> Result) rethrows
        -> Result
    {
        operationLock.lock()
        defer { operationLock.unlock() }
        return try body()
    }

    private static let outputCallback: VTDecompressionOutputCallback = {
        decompressionOutputRefCon,
        sourceFrameRefCon,
        status,
        infoFlags,
        imageBuffer,
        presentationTimeStamp,
        presentationDuration in
        handleOutputCallback(
            refCon: decompressionOutputRefCon,
            sourceFrameRefCon:
                sourceFrameRefCon,
            status: status,
            infoFlags: infoFlags,
            imageBuffer: imageBuffer,
            presentationTimeStamp:
                presentationTimeStamp,
            presentationDuration:
                presentationDuration
        )
    }

    deinit {
        closeSessionLocked()
    }
}
