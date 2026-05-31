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
    }

    struct DecodeFramePayload {
        let session: VTDecompressionSession
        let sampleBuffer: CMSampleBuffer
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
        guard codecID == AV_CODEC_ID_H264 else { return .notH264 }
        guard extradata != nil, extradataSize >= 7 else { return .extradataSize }
        guard firstExtradataByte == 1 else { return .extradataData }
        return nil
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

        if extradata[4] == 0xFE {
            extradata[4] = 0xFF
            self.needConvertNALSize3To4 = true
        }
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
                status = CMBlockBufferCreateWithMemoryBlock(
                    allocator: nil,
                    memoryBlock: convertedPayload.memoryBlock,
                    blockLength: convertedPayload.blockLength,
                    blockAllocator: kCFAllocatorNull,
                    customBlockSource: nil,
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

                if status == noErr, self.decodeStatus == noErr, self.decodeOutput != nil {
                    result = true
                }
            }
        }
        return result
    }

    static func packetPayload(for packet: AVPacket) -> PacketPayload? {
        guard let data = packet.data, packet.size > 0 else { return nil }
        return PacketPayload(data: data, size: packet.size)
    }

    static func convertedNALBlockPayload(memoryBlock: UnsafeMutablePointer<UInt8>?, demuxSize: Int32, packetSize: Int32) -> ConvertedNALBlockPayload? {
        guard let memoryBlock,
              demuxSize > 0,
              packetSize > 0,
              packetSize <= demuxSize else { return nil }
        return ConvertedNALBlockPayload(memoryBlock: memoryBlock, blockLength: Int(demuxSize), dataLength: Int(packetSize))
    }

    static func requiredFormatDescription(_ formatDescription: CMFormatDescription?) -> CMFormatDescription? {
        guard let formatDescription else { return nil }
        return formatDescription
    }

    static func decodeFramePayload(session: VTDecompressionSession?, sampleBuffer: CMSampleBuffer?) -> DecodeFramePayload? {
        guard let session, let sampleBuffer else { return nil }
        return DecodeFramePayload(session: session, sampleBuffer: sampleBuffer)
    }

    static func nalPayloadCanAdvance(nalSize: UInt32, remainingByteCount: Int) -> Bool {
        guard remainingByteCount >= 0 else { return false }
        return UInt64(nalSize) <= UInt64(remainingByteCount)
    }

    static func threeByteNALUnitsAreBounded(in payload: PacketPayload) -> Bool {
        var cursor = payload.data
        let end = payload.end

        while cursor < end {
            let nalSizeEnd = cursor.advanced(by: 3)
            guard nalSizeEnd <= end else { return false }

            let nalSize = (UInt32(cursor[0]) << 16) | (UInt32(cursor[1]) << 8) | UInt32(cursor[2])
            cursor = nalSizeEnd

            guard Self.nalPayloadCanAdvance(nalSize: nalSize, remainingByteCount: cursor.distance(to: end)) else {
                return false
            }
            let nalEnd = cursor.advanced(by: Int(nalSize))
            cursor = nalEnd
        }

        return true
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
        let pixelAspectRatio: [String: Any] = [
            "HorizontalSpacing": 0,
            "VerticalSpacing": 0
        ]

        let atoms: [String: Any] = [
            "avcC": CFDataCreate(nil, extradata, CFIndex(extradataSize)) as Any
        ]

        let extensions: [String: Any] = [
            "CVImageBufferChromaLocationBottomField": "left" as CFString,
            "CVImageBufferChromaLocationTopField": "left" as CFString,
            "FullRangeVideo": false,
            "CVPixelAspectRatio": pixelAspectRatio,
            "SampleDescriptionExtensionAtoms": atoms
        ]

        return extensions as CFDictionary
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
