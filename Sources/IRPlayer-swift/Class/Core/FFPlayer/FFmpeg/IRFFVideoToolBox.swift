//
//  IRFFVideoToolBox.swift
//  IRPlayer-swift
//
//  Created by irons on 2024/7/25.
//

import Foundation
import VideoToolbox
import IRFFMpeg

enum IRFFVideoToolBoxErrorCode: Error, Equatable {
    case extradataSize
    case extradataData
    case createFormatDescription
    case createSession
    case notH264
}

class IRFFVideoToolBox {
    struct PacketPayload {
        let data: UnsafeMutablePointer<UInt8>
        let size: Int32

        var end: UnsafeMutablePointer<UInt8> {
            data.advanced(by: Int(size))
        }
    }

    struct ConvertedNALBlockPayload {
        let memoryBlock: UnsafeMutablePointer<UInt8>
        let blockLength: Int
        let dataLength: Int
        let customBlockSource: CMBlockBufferCustomBlockSource
    }

    struct DecodeFramePayload {
        let session: VTDecompressionSession
        let sampleBuffer: CMSampleBuffer
    }

    struct NALLengthSizePolicy {
        let normalizedMarker: UInt8
        let shouldConvertThreeByteNALUnits: Bool
    }

    private var codecContext: UnsafeMutablePointer<AVCodecContext>
    private var vtSession: VTDecompressionSession?
    private var formatDescription: CMFormatDescription?
    var decodeStatus: OSStatus = noErr
    var decodeOutput: CVImageBuffer?

    var vtSessionToken: Bool = false
    var needConvertNALSize3To4: Bool = false

    init(codecContext: UnsafeMutablePointer<AVCodecContext>) {
        self.codecContext = codecContext
    }

    static func videoToolBox(with codecContext: UnsafeMutablePointer<AVCodecContext>) -> IRFFVideoToolBox {
        return IRFFVideoToolBox(codecContext: codecContext)
    }

    static func setupValidationError(codecID: AVCodecID,
                                     extradata: UnsafeMutablePointer<UInt8>?,
                                     extradataSize: Int32,
                                     firstExtradataByte: UInt8?) -> IRFFVideoToolBoxErrorCode? {
        return IRFFVideoToolBoxPolicy.setupValidationError(
            codecID: codecID,
            extradata: extradata,
            extradataSize: extradataSize,
            firstExtradataByte: firstExtradataByte
        )
    }

    func trySetupVTSession() -> Bool {
        if !self.vtSessionToken {
            do {
                try self.setupVTSession()
                self.vtSessionToken = true
            } catch {
                return false
            }
        }
        return self.vtSessionToken
    }

    func setupVTSession() throws {
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

        let nalPolicy = Self.nalLengthSizePolicy(for: extradata[4])
        extradata[4] = nalPolicy.normalizedMarker
        self.needConvertNALSize3To4 = nalPolicy.shouldConvertThreeByteNALUnits
        self.formatDescription = createFormatDescription(codecType: kCMVideoCodecType_H264, width: codecContext.pointee.width, height: codecContext.pointee.height, extradata: extradata, extradataSize: extradataSize)
        if self.formatDescription == nil {
            throw IRFFVideoToolBoxErrorCode.createFormatDescription
        }
        guard let formatDescription = Self.requiredFormatDescription(self.formatDescription) else {
            throw IRFFVideoToolBoxErrorCode.createFormatDescription
        }

        let destinationPixelBufferAttributes: [CFString: Any] = [
            kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
            kCVPixelBufferWidthKey: codecContext.pointee.width,
            kCVPixelBufferHeightKey: codecContext.pointee.height,
            kCVPixelBufferMetalCompatibilityKey: true,
            kCVPixelBufferIOSurfacePropertiesKey: [:]
        ]

        var outputCallbackRecord = VTDecompressionOutputCallbackRecord()
        outputCallbackRecord.decompressionOutputCallback = IRFFVideoToolBox.outputCallback
        outputCallbackRecord.decompressionOutputRefCon = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())

        let status = VTDecompressionSessionCreate(
            allocator: kCFAllocatorDefault,
            formatDescription: formatDescription,
            decoderSpecification: nil,
            imageBufferAttributes: destinationPixelBufferAttributes as CFDictionary,
            outputCallback: &outputCallbackRecord,
            decompressionSessionOut: &self.vtSession
        )

        if status != noErr {
            throw IRFFVideoToolBoxErrorCode.createSession
        }
    }

    func cleanVTSession() {
        self.formatDescription = nil
        if let vtSession = self.vtSession {
            VTDecompressionSessionWaitForAsynchronousFrames(vtSession)
            VTDecompressionSessionInvalidate(vtSession)
            self.vtSession = nil
        }
        self.needConvertNALSize3To4 = false
        self.vtSessionToken = false
    }

    func cleanDecodeInfo() {
        self.decodeStatus = noErr
        self.decodeOutput = nil
    }

    func sendPacket(_ packet: AVPacket) -> Bool {
        guard self.trySetupVTSession() else { return false }
        guard let packetPayload = Self.packetPayload(for: packet) else { return false }
        self.cleanDecodeInfo()

        var result = false
        var blockBuffer: CMBlockBuffer?
        var status: OSStatus = noErr

        if self.needConvertNALSize3To4 {
            guard Self.threeByteNALUnitsAreBounded(in: packetPayload) else { return false }

            var ioContext: UnsafeMutablePointer<AVIOContext>?
            if avio_open_dyn_buf(&ioContext) < 0 {
                status = -1900
            } else {
                var nalSize: UInt32 = 0
                let end = packetPayload.end
                var nalStart = packetPayload.data
                while nalStart < end {
                    nalSize = (UInt32(nalStart[0]) << 16) | (UInt32(nalStart[1]) << 8) | UInt32(nalStart[2])
                    avio_wb32(ioContext, nalSize)
                    nalStart += 3
                    avio_write(ioContext, nalStart, Int32(nalSize))
                    nalStart += UnsafeMutablePointer<UInt8>.Stride(nalSize)
                }
                var demuxBuffer: UnsafeMutablePointer<UInt8>?
                let demuxSize = avio_close_dyn_buf(ioContext, &demuxBuffer)
                guard let convertedPayload = Self.convertedNALBlockPayload(memoryBlock: demuxBuffer, demuxSize: demuxSize, packetSize: packetPayload.size) else { return false }
                var customBlockSource = convertedPayload.customBlockSource
                status = CMBlockBufferCreateWithMemoryBlock(
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
            }
        } else {
            status = CMBlockBufferCreateWithMemoryBlock(
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
        }

        if status == noErr {
            guard let formatDescription = Self.requiredFormatDescription(self.formatDescription) else { return false }
            var sampleBuffer: CMSampleBuffer?
            status = CMSampleBufferCreate(
                allocator: nil,
                dataBuffer: blockBuffer,
                dataReady: true,
                makeDataReadyCallback: nil,
                refcon: nil,
                formatDescription: formatDescription,
                sampleCount: 1,
                sampleTimingEntryCount: 0,
                sampleTimingArray: nil,
                sampleSizeEntryCount: 0,
                sampleSizeArray: nil,
                sampleBufferOut: &sampleBuffer
            )

            if status == noErr {
                guard let decodePayload = Self.decodeFramePayload(session: self.vtSession, sampleBuffer: sampleBuffer) else { return false }
                status = VTDecompressionSessionDecodeFrame(
                    decodePayload.session,
                    sampleBuffer: decodePayload.sampleBuffer,
                    flags: [],
                    frameRefcon: nil,
                    infoFlagsOut: nil
                )

                if Self.decodeFrameSucceeded(status: status, callbackStatus: self.decodeStatus, hasOutput: self.decodeOutput != nil) {
                    result = true
                }
            }
        }
        return result
    }

    static func packetPayload(for packet: AVPacket) -> PacketPayload? {
        return IRFFVideoToolBoxPolicy.packetPayload(for: packet)
    }

    static func convertedNALBlockPayload(memoryBlock: UnsafeMutablePointer<UInt8>?, demuxSize: Int32, packetSize: Int32) -> ConvertedNALBlockPayload? {
        return IRFFVideoToolBoxPolicy.convertedNALBlockPayload(
            memoryBlock: memoryBlock,
            demuxSize: demuxSize,
            packetSize: packetSize
        )
    }

    static func requiredFormatDescription(_ formatDescription: CMFormatDescription?) -> CMFormatDescription? {
        return IRFFVideoToolBoxPolicy.requiredFormatDescription(formatDescription)
    }

    static func nalLengthSizePolicy(for marker: UInt8) -> NALLengthSizePolicy {
        return IRFFVideoToolBoxPolicy.nalLengthSizePolicy(for: marker)
    }

    static func decodeFramePayload(session: VTDecompressionSession?, sampleBuffer: CMSampleBuffer?) -> DecodeFramePayload? {
        return IRFFVideoToolBoxPolicy.decodeFramePayload(session: session, sampleBuffer: sampleBuffer)
    }

    static func decodeFrameSucceeded(status: OSStatus, callbackStatus: OSStatus, hasOutput: Bool) -> Bool {
        return IRFFVideoToolBoxPolicy.decodeFrameSucceeded(
            status: status,
            callbackStatus: callbackStatus,
            hasOutput: hasOutput
        )
    }

    static func nalPayloadCanAdvance(nalSize: UInt32, remainingByteCount: Int) -> Bool {
        return IRFFVideoToolBoxPolicy.nalPayloadCanAdvance(
            nalSize: nalSize,
            remainingByteCount: remainingByteCount
        )
    }

    static func threeByteNALUnitsAreBounded(in payload: PacketPayload) -> Bool {
        return IRFFVideoToolBoxPolicy.threeByteNALUnitsAreBounded(in: payload)
    }

    func imageBuffer() -> CVImageBuffer? {
        if self.decodeStatus == noErr, let decodeOutput = self.decodeOutput {
            return decodeOutput
        }
        return nil
    }

    func flush() {
        self.cleanVTSession()
        self.cleanDecodeInfo()
    }

    deinit {
        self.flush()
    }

    static func handleOutputCallback(refCon: UnsafeMutableRawPointer?, status: OSStatus, imageBuffer: CVImageBuffer?) {
        guard let refCon else { return }
        let videoToolBox = Unmanaged<IRFFVideoToolBox>.fromOpaque(refCon).takeUnretainedValue()
        videoToolBox.decodeStatus = status
        videoToolBox.decodeOutput = imageBuffer
    }

    static func makeFormatDescriptionExtensions(extradata: UnsafePointer<UInt8>, extradataSize: Int32) -> CFDictionary {
        return IRFFVideoToolBoxPolicy.makeFormatDescriptionExtensions(
            extradata: extradata,
            extradataSize: extradataSize
        )
    }

    private static let outputCallback: VTDecompressionOutputCallback = { (
        decompressionOutputRefCon: UnsafeMutableRawPointer?,
        sourceFrameRefCon: UnsafeMutableRawPointer?,
        status: OSStatus,
        infoFlags: VTDecodeInfoFlags,
        imageBuffer: CVImageBuffer?,
        presentationTimeStamp: CMTime,
        presentationDuration: CMTime
    ) in
            IRFFVideoToolBox.handleOutputCallback(refCon: decompressionOutputRefCon, status: status, imageBuffer: imageBuffer)
    }

    private func createFormatDescription(codecType: CMVideoCodecType, width: Int32, height: Int32, extradata: UnsafePointer<UInt8>, extradataSize: Int32) -> CMFormatDescription? {
        var formatDescription: CMFormatDescription?
        var status: OSStatus

        let extensions = Self.makeFormatDescriptionExtensions(extradata: extradata, extradataSize: extradataSize)

        status = CMVideoFormatDescriptionCreate(
            allocator: nil,
            codecType: codecType,
            width: width,
            height: height,
            extensions: extensions,
            formatDescriptionOut: &formatDescription
        )

        return status == noErr ? formatDescription : nil
    }
}
