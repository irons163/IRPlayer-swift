//
//  IRFFVideoToolBox.swift
//  IRPlayer-swift
//
//  Created by irons on 2024/7/25.
//

import CoreMedia
import CoreVideo
import Foundation
import IRFFMpeg
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
    struct Generation {
        let session: VTDecompressionSession
        let formatDescription: CMFormatDescription
        let callbackState: IRFFVideoToolBoxCallbackState
        let callbackReference: UnsafeMutableRawPointer
        let convertsThreeByteNALUnits: Bool
    }

    typealias Diagnostics = IRFFVideoToolBoxSession<Generation>.Diagnostics

    private let codecContext: UnsafeMutablePointer<AVCodecContext>
    private let operationLock = NSLock()
    private let session = IRFFVideoToolBoxSession<Generation>()

    var diagnostics: Diagnostics {
        session.diagnostics
    }

    init(codecContext: UnsafeMutablePointer<AVCodecContext>) {
        self.codecContext = codecContext
    }

    static func videoToolBox(
        with codecContext: UnsafeMutablePointer<AVCodecContext>
    ) -> IRFFVideoToolBox {
        IRFFVideoToolBox(codecContext: codecContext)
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
                $0.callbackState.reset()
            }
        }
    }

    func sendPacket(_ packet: AVPacket) -> Bool {
        withOperation {
            guard trySetupVTSessionLocked(),
                  let packetPayload = Self.packetPayload(for: packet) else {
                return false
            }

            return session.withResource(default: false) { generation in
                generation.callbackState.reset()
                guard let blockBuffer = makeBlockBuffer(
                    from: packetPayload,
                    convertsThreeByteNALUnits:
                        generation.convertsThreeByteNALUnits
                ),
                let sampleBuffer = Self.makeSampleBuffer(
                    blockBuffer: blockBuffer,
                    formatDescription: generation.formatDescription
                ) else {
                    return false
                }

                let status = VTDecompressionSessionDecodeFrame(
                    generation.session,
                    sampleBuffer: sampleBuffer,
                    flags: [],
                    frameRefcon: nil,
                    infoFlagsOut: nil
                )
                let callback = generation.callbackState.snapshot
                return Self.decodeFrameSucceeded(
                    status: status,
                    callbackStatus: callback.status,
                    hasOutput: callback.imageBuffer != nil
                )
            }
        }
    }

    func imageBuffer() -> CVImageBuffer? {
        session.withResource(
            default: Optional<CVImageBuffer>.none
        ) { generation in
            let callback = generation.callbackState.snapshot
            guard callback.status == noErr else { return nil }
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
        status: OSStatus,
        imageBuffer: CVImageBuffer?
    ) {
        guard let refCon else { return }
        let callbackState = Unmanaged<IRFFVideoToolBoxCallbackState>
            .fromOpaque(refCon)
            .takeUnretainedValue()
        callbackState.publish(status: status, imageBuffer: imageBuffer)
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
        extradata[4] = nalLength.normalizedMarker
        guard let formatDescription = Self.createFormatDescription(
            codecType: kCMVideoCodecType_H264,
            width: codecContext.pointee.width,
            height: codecContext.pointee.height,
            extradata: extradata,
            extradataSize: extradataSize
        ) else {
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

        var blockBuffer: CMBlockBuffer?
        let status = CMBlockBufferCreateWithMemoryBlock(
            allocator: nil,
            memoryBlock: packetPayload.data,
            blockLength: Int(packetPayload.size),
            blockAllocator: kCFAllocatorNull,
            customBlockSource: nil,
            offsetToData: 0,
            dataLength: Int(packetPayload.size),
            flags: 0,
            blockBufferOut: &blockBuffer
        )
        return status == noErr ? blockBuffer : nil
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
        VTDecompressionSessionWaitForAsynchronousFrames(generation.session)
        VTDecompressionSessionInvalidate(generation.session)
        generation.callbackState.reset()
        Unmanaged<IRFFVideoToolBoxCallbackState>
            .fromOpaque(generation.callbackReference)
            .release()
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
        _,
        status,
        _,
        imageBuffer,
        _,
        _ in
        handleOutputCallback(
            refCon: decompressionOutputRefCon,
            status: status,
            imageBuffer: imageBuffer
        )
    }

    deinit {
        closeSessionLocked()
    }
}
