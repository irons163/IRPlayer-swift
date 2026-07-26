import CoreMedia
import Foundation
#if SWIFT_PACKAGE || DEBUG
internal import IRFFMpeg
internal import IRPlayerObjc
#else
@_implementationOnly import IRFFMpeg
@_implementationOnly import IRPlayerObjc
#endif
import VideoToolbox

extension IRFFVideoToolBox {
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

    struct NALLengthSizeDecision {
        let normalizedMarker: UInt8
        let shouldConvertThreeByteNALUnits: Bool
    }

    static func setupValidationError(
        codecID: AVCodecID,
        extradata: UnsafeMutablePointer<UInt8>?,
        extradataSize: Int32,
        firstExtradataByte: UInt8?
    ) -> IRFFVideoToolBoxErrorCode? {
        guard codecID == AV_CODEC_ID_H264 else { return .notH264 }
        guard extradata != nil, extradataSize >= 7 else {
            return .extradataSize
        }
        guard firstExtradataByte == 1 else { return .extradataData }
        return nil
    }

    static func packetPayload(for packet: AVPacket) -> PacketPayload? {
        guard let data = packet.data, packet.size > 0 else { return nil }
        return PacketPayload(data: data, size: packet.size)
    }

    static func makeOwnedBlockBuffer(
        from packetPayload: PacketPayload
    ) -> CMBlockBuffer? {
        let byteCount =
            Int(packetPayload.size)
        guard byteCount > 0,
              let ownedMemory =
                av_malloc(byteCount) else {
            return nil
        }
        memcpy(
            ownedMemory,
            packetPayload.data,
            byteCount
        )
        var customBlockSource =
            CMBlockBufferCustomBlockSource(
                version:
                    kCMBlockBufferCustomBlockSourceVersion,
                AllocateBlock: nil,
                FreeBlock: {
                    _,
                    memoryBlock,
                    _ in
                    av_free(memoryBlock)
                },
                refCon: nil
            )
        var blockBuffer: CMBlockBuffer?
        let status =
            CMBlockBufferCreateWithMemoryBlock(
                allocator: nil,
                memoryBlock: ownedMemory,
                blockLength: byteCount,
                blockAllocator:
                    kCFAllocatorNull,
                customBlockSource:
                    &customBlockSource,
                offsetToData: 0,
                dataLength: byteCount,
                flags: 0,
                blockBufferOut:
                    &blockBuffer
            )
        if status != noErr {
            av_free(ownedMemory)
        }
        return status == noErr
            ? blockBuffer
            : nil
    }

    static func convertedNALBlockPayload(
        memoryBlock: UnsafeMutablePointer<UInt8>?,
        demuxSize: Int32,
        packetSize: Int32
    ) -> ConvertedNALBlockPayload? {
        guard let memoryBlock,
              demuxSize > 0,
              packetSize > 0,
              packetSize <= demuxSize else {
            return nil
        }
        let customBlockSource = CMBlockBufferCustomBlockSource(
            version: kCMBlockBufferCustomBlockSourceVersion,
            AllocateBlock: nil,
            FreeBlock: { _, memoryBlock, _ in
                av_free(memoryBlock)
            },
            refCon: nil
        )
        return ConvertedNALBlockPayload(
            memoryBlock: memoryBlock,
            blockLength: Int(demuxSize),
            dataLength: Int(demuxSize),
            customBlockSource: customBlockSource
        )
    }

    static func requiredFormatDescription(
        _ formatDescription: CMFormatDescription?
    ) -> CMFormatDescription? {
        formatDescription
    }

    static func nalLengthSizeDecision(
        for marker: UInt8
    ) -> NALLengthSizeDecision {
        guard marker == 0xFE else {
            return NALLengthSizeDecision(
                normalizedMarker: marker,
                shouldConvertThreeByteNALUnits: false
            )
        }
        return NALLengthSizeDecision(
            normalizedMarker: 0xFF,
            shouldConvertThreeByteNALUnits: true
        )
    }

    static func decodeFramePayload(
        session: VTDecompressionSession?,
        sampleBuffer: CMSampleBuffer?
    ) -> DecodeFramePayload? {
        guard let session, let sampleBuffer else { return nil }
        return DecodeFramePayload(
            session: session,
            sampleBuffer: sampleBuffer
        )
    }

    static func decodeFrameSucceeded(
        status: OSStatus,
        callbackStatus: OSStatus,
        hasOutput _: Bool
    ) -> Bool {
        status == noErr &&
            callbackStatus == noErr
    }

    static func nalPayloadCanAdvance(
        nalSize: UInt32,
        remainingByteCount: Int
    ) -> Bool {
        guard remainingByteCount >= 0 else { return false }
        return UInt64(nalSize) <= UInt64(remainingByteCount)
    }

    static func threeByteNALUnitsAreBounded(
        in payload: PacketPayload
    ) -> Bool {
        var cursor = payload.data
        let end = payload.end

        while cursor < end {
            let nalSizeEnd = cursor.advanced(by: 3)
            guard nalSizeEnd <= end else { return false }

            let nalSize = (UInt32(cursor[0]) << 16)
                | (UInt32(cursor[1]) << 8)
                | UInt32(cursor[2])
            cursor = nalSizeEnd
            guard nalPayloadCanAdvance(
                nalSize: nalSize,
                remainingByteCount: cursor.distance(to: end)
            ) else {
                return false
            }
            cursor = cursor.advanced(by: Int(nalSize))
        }
        return true
    }

    static func makeFormatDescriptionExtensions(
        extradata: UnsafePointer<UInt8>,
        extradataSize: Int32
    ) -> CFDictionary {
        let safeExtradataSize = max(0, CFIndex(extradataSize))
        let pixelAspectRatio: [String: Any] = [
            "HorizontalSpacing": 0,
            "VerticalSpacing": 0
        ]
        let atoms: [String: Any] = [
            "avcC": CFDataCreate(
                nil,
                extradata,
                safeExtradataSize
            ) as Data
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

    static func createFormatDescription(
        codecType: CMVideoCodecType,
        width: Int32,
        height: Int32,
        extradata: UnsafePointer<UInt8>,
        extradataSize: Int32
    ) -> CMFormatDescription? {
        var formatDescription: CMFormatDescription?
        let status = CMVideoFormatDescriptionCreate(
            allocator: nil,
            codecType: codecType,
            width: width,
            height: height,
            extensions: makeFormatDescriptionExtensions(
                extradata: extradata,
                extradataSize: extradataSize
            ),
            formatDescriptionOut: &formatDescription
        )
        return status == noErr ? formatDescription : nil
    }

    static func makeSampleBuffer(
        blockBuffer: CMBlockBuffer,
        formatDescription: CMFormatDescription,
        timing: CMSampleTimingInfo,
        sampleSize: Int
    ) -> CMSampleBuffer? {
        guard sampleSize > 0 else {
            return nil
        }
        var sampleBuffer: CMSampleBuffer?
        var timing = timing
        var sampleSize = sampleSize
        let status = CMSampleBufferCreate(
            allocator: nil,
            dataBuffer: blockBuffer,
            dataReady: true,
            makeDataReadyCallback: nil,
            refcon: nil,
            formatDescription: formatDescription,
            sampleCount: 1,
            sampleTimingEntryCount: 1,
            sampleTimingArray: &timing,
            sampleSizeEntryCount: 1,
            sampleSizeArray: &sampleSize,
            sampleBufferOut: &sampleBuffer
        )
        return status == noErr ? sampleBuffer : nil
    }

    static func sampleTiming(
        for packet: AVPacket,
        timebase: TimeInterval
    ) -> CMSampleTimingInfo {
        let presentationTimestamp =
            packet.pts != IR_AV_NOPTS_VALUE
            ? packet.pts
            : packet.dts
        return CMSampleTimingInfo(
            duration:
                mediaTime(
                    ticks: packet.duration,
                    timebase: timebase,
                    requiresPositiveTicks:
                        true
                ),
            presentationTimeStamp:
                mediaTime(
                    ticks:
                        presentationTimestamp,
                    timebase: timebase,
                    requiresPositiveTicks:
                        false
                ),
            decodeTimeStamp:
                mediaTime(
                    ticks: packet.dts,
                    timebase: timebase,
                    requiresPositiveTicks:
                        false
                )
        )
    }

    static func mediaTime(
        ticks: Int64,
        timebase: TimeInterval,
        requiresPositiveTicks: Bool
    ) -> CMTime {
        guard ticks != IR_AV_NOPTS_VALUE,
              (!requiresPositiveTicks ||
                  ticks > 0),
              timebase.isFinite,
              timebase > 0 else {
            return .invalid
        }
        let seconds =
            Double(ticks) * timebase
        let timescale: Int32 = 1_000_000
        let scaled =
            seconds * Double(timescale)
        guard seconds.isFinite,
              scaled.isFinite,
              scaled >= Double(Int64.min),
              scaled < Double(Int64.max) else {
            return .invalid
        }
        return CMTime(
            value: Int64(
                scaled.rounded()
            ),
            timescale: timescale
        )
    }
}
