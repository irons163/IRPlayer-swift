//
//  IRFFCustomVideoDecoding.swift
//  IRPlayer-swift
//
//  Created by Codex on 2026/7/24.
//

import Foundation
import IRFFMpeg

public struct IRFFVideoCodecIdentifier:
    RawRepresentable,
    Hashable,
    Equatable,
    Sendable
{
    public let rawValue: Int32

    public init(rawValue: Int32) {
        self.rawValue = rawValue
    }

    public static let h264 = IRFFVideoCodecIdentifier(
        rawValue: Int32(
            truncatingIfNeeded: AV_CODEC_ID_H264.rawValue
        )
    )
    public static let hevc = IRFFVideoCodecIdentifier(
        rawValue: Int32(
            truncatingIfNeeded: AV_CODEC_ID_HEVC.rawValue
        )
    )
    public static let mpeg4 = IRFFVideoCodecIdentifier(
        rawValue: Int32(
            truncatingIfNeeded: AV_CODEC_ID_MPEG4.rawValue
        )
    )
    public static let mjpeg = IRFFVideoCodecIdentifier(
        rawValue: Int32(
            truncatingIfNeeded: AV_CODEC_ID_MJPEG.rawValue
        )
    )
}

public struct IRFFVideoPixelFormatIdentifier:
    RawRepresentable,
    Hashable,
    Equatable,
    Sendable
{
    public let rawValue: Int32

    public init(rawValue: Int32) {
        self.rawValue = rawValue
    }
}

public struct IRFFVideoPacketSideDataIdentifier:
    RawRepresentable,
    Hashable,
    Equatable,
    Sendable
{
    public let rawValue: Int32

    public init(rawValue: Int32) {
        self.rawValue = rawValue
    }
}

public struct IRFFVideoCodecDescriptor: Equatable, Sendable {
    public let identifier: IRFFVideoCodecIdentifier
    public let width: Int
    public let height: Int
    public let pixelFormat: IRFFVideoPixelFormatIdentifier
    public let profile: Int32
    public let level: Int32
    public let bitrate: Int64
    public let extraData: Data

    public init?(
        identifier: IRFFVideoCodecIdentifier,
        width: Int,
        height: Int,
        pixelFormat: IRFFVideoPixelFormatIdentifier,
        profile: Int32,
        level: Int32,
        bitrate: Int64,
        extraData: Data
    ) {
        guard width >= 0,
              height >= 0,
              (width == 0) == (height == 0) else {
            return nil
        }
        self.identifier = identifier
        self.width = width
        self.height = height
        self.pixelFormat = pixelFormat
        self.profile = profile
        self.level = level
        self.bitrate = bitrate
        self.extraData = extraData
    }

    init?(
        copying codecContext:
            UnsafePointer<AVCodecContext>
    ) {
        let extraDataSize = codecContext.pointee.extradata_size
        guard extraDataSize >= 0,
              let extraData = Self.copyBytes(
                codecContext.pointee.extradata,
                count: Int(extraDataSize)
              ) else {
            return nil
        }
        self.init(
            identifier: IRFFVideoCodecIdentifier(
                rawValue: Int32(
                    truncatingIfNeeded:
                        codecContext.pointee.codec_id.rawValue
                )
            ),
            width: Int(codecContext.pointee.width),
            height: Int(codecContext.pointee.height),
            pixelFormat: IRFFVideoPixelFormatIdentifier(
                rawValue: Int32(
                    truncatingIfNeeded:
                        codecContext.pointee.pix_fmt.rawValue
                )
            ),
            profile: codecContext.pointee.profile,
            level: codecContext.pointee.level,
            bitrate: codecContext.pointee.bit_rate,
            extraData: extraData
        )
    }

    private static func copyBytes(
        _ pointer: UnsafePointer<UInt8>?,
        count: Int
    ) -> Data? {
        guard count >= 0 else { return nil }
        guard count > 0 else { return Data() }
        guard let pointer else { return nil }
        return Data(bytes: pointer, count: count)
    }
}

public struct IRFFVideoPacketSideData: Equatable, Sendable {
    public let identifier: IRFFVideoPacketSideDataIdentifier
    public let data: Data

    public init(
        identifier: IRFFVideoPacketSideDataIdentifier,
        data: Data
    ) {
        self.identifier = identifier
        self.data = data
    }
}

public struct IRFFCompressedVideoPacket: Equatable, Sendable {
    private static let keyFrameFlag: Int32 = 1

    public let data: Data
    public let presentationTimestamp: Int64?
    public let decodeTimestamp: Int64?
    public let durationTicks: Int64
    public let streamIndex: Int32
    public let flags: Int32
    public let isKeyFrame: Bool
    public let sourcePosition: Int64
    public let sideData: [IRFFVideoPacketSideData]

    public init(
        data: Data,
        presentationTimestamp: Int64?,
        decodeTimestamp: Int64?,
        durationTicks: Int64,
        streamIndex: Int32,
        flags: Int32,
        sourcePosition: Int64,
        sideData: [IRFFVideoPacketSideData] = []
    ) {
        self.data = data
        self.presentationTimestamp = presentationTimestamp
        self.decodeTimestamp = decodeTimestamp
        self.durationTicks = durationTicks
        self.streamIndex = streamIndex
        self.flags = flags
        self.isKeyFrame =
            flags & Self.keyFrameFlag != 0
        self.sourcePosition = sourcePosition
        self.sideData = sideData
    }

    init?(copying packet: AVPacket) {
        guard packet.size >= 0,
              let data = Self.copyBytes(
                packet.data,
                count: Int(packet.size)
              ),
              let sideData = Self.copySideData(
                packet.side_data,
                count: packet.side_data_elems
              ) else {
            return nil
        }
        self.init(
            data: data,
            presentationTimestamp: Self.timestamp(packet.pts),
            decodeTimestamp: Self.timestamp(packet.dts),
            durationTicks: packet.duration,
            streamIndex: packet.stream_index,
            flags: packet.flags,
            sourcePosition: packet.pos,
            sideData: sideData
        )
    }

    private static func timestamp(_ value: Int64) -> Int64? {
        value == IR_AV_NOPTS_VALUE ? nil : value
    }

    private static func copyBytes(
        _ pointer: UnsafePointer<UInt8>?,
        count: Int
    ) -> Data? {
        guard count >= 0 else { return nil }
        guard count > 0 else { return Data() }
        guard let pointer else { return nil }
        return Data(bytes: pointer, count: count)
    }

    private static func copySideData(
        _ pointer: UnsafePointer<AVPacketSideData>?,
        count: Int32
    ) -> [IRFFVideoPacketSideData]? {
        guard count >= 0 else { return nil }
        guard count > 0 else { return [] }
        guard let pointer else { return nil }

        var result: [IRFFVideoPacketSideData] = []
        result.reserveCapacity(Int(count))
        for index in 0..<Int(count) {
            let entry = pointer[index]
            guard let byteCount = Int(exactly: entry.size),
                  let data = copyBytes(
                    entry.data,
                    count: byteCount
                  ) else {
                return nil
            }
            result.append(
                IRFFVideoPacketSideData(
                    identifier:
                        IRFFVideoPacketSideDataIdentifier(
                            rawValue: Int32(
                                truncatingIfNeeded:
                                    entry.type.rawValue
                            )
                        ),
                    data: data
                )
            )
        }
        return result
    }
}

public struct IRFFVideoDecoderInfo: Equatable, Sendable {
    public let codec: IRFFVideoCodecDescriptor
    public let isHardwareDecodingEnabled: Bool
    public let maximumDecodeDuration: TimeInterval
    public let timebase: TimeInterval
    public let framesPerSecond: TimeInterval

    public init(
        codec: IRFFVideoCodecDescriptor,
        isHardwareDecodingEnabled: Bool,
        maximumDecodeDuration: TimeInterval,
        timebase: TimeInterval,
        framesPerSecond: TimeInterval
    ) {
        self.codec = codec
        self.isHardwareDecodingEnabled =
            isHardwareDecodingEnabled
        self.maximumDecodeDuration = maximumDecodeDuration
        self.timebase = timebase
        self.framesPerSecond = framesPerSecond
    }
}

public protocol IRFFVideoDecoderDataSource: AnyObject {
    func shouldHandle(
        _ videoDecoder: IRFFVideoDecoderInfo,
        decodeFrame packet: IRFFCompressedVideoPacket
    ) -> Bool

    func videoDecoder(
        _ videoDecoder: IRFFVideoDecoderInfo,
        decodeFrame packet: IRFFCompressedVideoPacket
    ) -> IRFFVideoFrame?
}
