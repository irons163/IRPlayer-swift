import CoreMedia
import Foundation
import IRFFMpeg
import VideoToolbox

enum IRFFVideoToolBoxPolicy {

    static func setupValidationError(codecID: AVCodecID,
                                     extradata: UnsafeMutablePointer<UInt8>?,
                                     extradataSize: Int32,
                                     firstExtradataByte: UInt8?) -> IRFFVideoToolBoxErrorCode? {
        guard codecID == AV_CODEC_ID_H264 else { return .notH264 }
        guard extradata != nil, extradataSize >= 7 else { return .extradataSize }
        guard firstExtradataByte == 1 else { return .extradataData }
        return nil
    }

    static func packetPayload(for packet: AVPacket) -> IRFFVideoToolBox.PacketPayload? {
        guard let data = packet.data, packet.size > 0 else { return nil }
        return IRFFVideoToolBox.PacketPayload(data: data, size: packet.size)
    }

    static func convertedNALBlockPayload(memoryBlock: UnsafeMutablePointer<UInt8>?,
                                         demuxSize: Int32,
                                         packetSize: Int32) -> IRFFVideoToolBox.ConvertedNALBlockPayload? {
        guard let memoryBlock,
              demuxSize > 0,
              packetSize > 0,
              packetSize <= demuxSize else { return nil }
        let customBlockSource = CMBlockBufferCustomBlockSource(
            version: kCMBlockBufferCustomBlockSourceVersion,
            AllocateBlock: nil,
            FreeBlock: { _, memoryBlock, _ in
                av_free(memoryBlock)
            },
            refCon: nil
        )
        return IRFFVideoToolBox.ConvertedNALBlockPayload(
            memoryBlock: memoryBlock,
            blockLength: Int(demuxSize),
            dataLength: Int(demuxSize),
            customBlockSource: customBlockSource
        )
    }

    static func requiredFormatDescription(_ formatDescription: CMFormatDescription?) -> CMFormatDescription? {
        guard let formatDescription else { return nil }
        return formatDescription
    }

    static func nalLengthSizePolicy(for marker: UInt8) -> IRFFVideoToolBox.NALLengthSizePolicy {
        guard marker == 0xFE else {
            return IRFFVideoToolBox.NALLengthSizePolicy(
                normalizedMarker: marker,
                shouldConvertThreeByteNALUnits: false
            )
        }
        return IRFFVideoToolBox.NALLengthSizePolicy(
            normalizedMarker: 0xFF,
            shouldConvertThreeByteNALUnits: true
        )
    }

    static func decodeFramePayload(session: VTDecompressionSession?,
                                   sampleBuffer: CMSampleBuffer?) -> IRFFVideoToolBox.DecodeFramePayload? {
        guard let session, let sampleBuffer else { return nil }
        return IRFFVideoToolBox.DecodeFramePayload(session: session, sampleBuffer: sampleBuffer)
    }

    static func decodeFrameSucceeded(status: OSStatus, callbackStatus: OSStatus, hasOutput: Bool) -> Bool {
        status == noErr && callbackStatus == noErr && hasOutput
    }

    static func nalPayloadCanAdvance(nalSize: UInt32, remainingByteCount: Int) -> Bool {
        guard remainingByteCount >= 0 else { return false }
        return UInt64(nalSize) <= UInt64(remainingByteCount)
    }

    static func threeByteNALUnitsAreBounded(in payload: IRFFVideoToolBox.PacketPayload) -> Bool {
        var cursor = payload.data
        let end = payload.end

        while cursor < end {
            let nalSizeEnd = cursor.advanced(by: 3)
            guard nalSizeEnd <= end else { return false }

            let nalSize = (UInt32(cursor[0]) << 16) | (UInt32(cursor[1]) << 8) | UInt32(cursor[2])
            cursor = nalSizeEnd

            guard nalPayloadCanAdvance(nalSize: nalSize, remainingByteCount: cursor.distance(to: end)) else {
                return false
            }
            let nalEnd = cursor.advanced(by: Int(nalSize))
            cursor = nalEnd
        }

        return true
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
}
