import Foundation
import IRFFMpeg
import IRPlayerObjc
import XCTest
#if SWIFT_PACKAGE
@testable import IRPlayerSwift
#else
@testable import IRPlayer_swift
#endif

final class IRFFVideoInputTests: XCTestCase {
    func testInitializerDefaultsToDisplayViewOutputWithoutVideoOutput() {
        let input = IRFFVideoInput()

        XCTAssertNil(input.videoOutput)
        XCTAssertEqual(input.outputType, .displayView)
    }

    func testInitializerStoresVideoOutputAndOutputType() {
        let output = RecordingFFDecoderVideoOutput()
        let input = IRFFVideoInput(
            videoOutput: output,
            outputType: .decoder
        )

        XCTAssertTrue(input.videoOutput === output)
        XCTAssertEqual(input.outputType, .decoder)
    }

    func testVideoOutputBindingIsNonOwning() {
        let input = IRFFVideoInput()
        weak var weakOutput: RecordingFFDecoderVideoOutput?

        autoreleasepool {
            var output: RecordingFFDecoderVideoOutput? =
                RecordingFFDecoderVideoOutput()
            weakOutput = output
            input.videoOutput = output

            XCTAssertTrue(input.videoOutput === output)
            output = nil
        }

        XCTAssertNil(weakOutput)
        XCTAssertNil(input.videoOutput)
    }

    func testVideoOutputBindingSupportsConcurrentReadAndReplacement() {
        let input = IRFFVideoInput()
        let outputs = (0..<8).map { _ in
            RecordingFFDecoderVideoOutput()
        }

        DispatchQueue.concurrentPerform(iterations: 1_000) {
            index in
            if index.isMultiple(of: 2) {
                input.videoOutput =
                    outputs[index % outputs.count]
            } else {
                _ = input.videoOutput
            }
        }

        input.videoOutput = outputs[0]
        XCTAssertTrue(input.videoOutput === outputs[0])
    }

    func testBoundedForwardingPrefersTrySendAndDoesNotDoubleReclaim() {
        let output =
            BoundedFFDecoderVideoOutput(
                accepts: false
            )
        let input = IRFFVideoInput(
            videoOutput: output,
            outputType: .decoder
        )
        let frame = IRFFVideoFrame()
        let probe =
            VideoInputFrameLifecycleProbe()
        frame.delegate = probe

        XCTAssertFalse(
            input.trySend(
                videoFrame: frame
            )
        )
        XCTAssertEqual(output.callCount, 1)
        XCTAssertEqual(probe.cancelCount, 1)
    }

    func testBoundedForwardingFallsBackToLegacySend() {
        let output =
            RecordingFFDecoderVideoOutput()
        let input = IRFFVideoInput(
            videoOutput: output,
            outputType: .decoder
        )
        let frame = IRFFVideoFrame()

        XCTAssertTrue(
            input.send(
                videoFrame: frame
            )
        )
        XCTAssertTrue(
            output.receivedFrames
                .first === frame
        )
    }

    func testBoundedForwardingReclaimsFrameWithoutCallableTarget() {
        let input = IRFFVideoInput()
        let frame = IRFFVideoFrame()
        let probe =
            VideoInputFrameLifecycleProbe()
        frame.delegate = probe

        XCTAssertFalse(
            input.trySend(
                videoFrame: frame
            )
        )
        XCTAssertEqual(probe.cancelCount, 1)
    }

    func testDefaultDataSourceDeclinesDescriptorForBuiltInFallback()
        throws {
        let input = IRFFVideoInput()
        let codec = try makeCodecDescriptor()
        let info = IRFFVideoDecoderInfo(
            codec: codec,
            isHardwareDecodingEnabled: false,
            maximumDecodeDuration: 2,
            timebase: 0.25,
            framesPerSecond: 30
        )
        let packet = IRFFCompressedVideoPacket(
            data: Data([1, 2, 3]),
            presentationTimestamp: 4,
            decodeTimestamp: 3,
            durationTicks: 1,
            streamIndex: 0,
            flags: 0,
            sourcePosition: 8
        )
        let descriptor = try XCTUnwrap(
            IRFFVideoPacketDescriptor(
                payloadByteCount: packet.data.count,
                sideDataCount: packet.sideData.count,
                presentationTimestamp:
                    packet.presentationTimestamp,
                decodeTimestamp: packet.decodeTimestamp,
                durationTicks: packet.durationTicks,
                streamIndex: packet.streamIndex,
                flags: packet.flags,
                sourcePosition: packet.sourcePosition
            )
        )

        XCTAssertFalse(
            input.shouldHandle(
                info,
                packet: descriptor
            )
        )
        let completion =
            IRFFCustomVideoDecodeCompletion {
                _ in true
            }
        guard case .dropped =
                input.videoDecoder(
                    info,
                    decodeFrame: packet,
                    completion: completion
                ) else {
            return XCTFail(
                "Base input must explicitly drop only after opt-in"
            )
        }
    }

    func testCustomCompletionIsExactlyOnceAndReclaimsDistinctDuplicateFrame() {
        var handledCount = 0
        let completion =
            IRFFCustomVideoDecodeCompletion {
                _ in
                handledCount += 1
                return true
            }
        let firstFrame = IRFFVideoFrame()
        let duplicateFrame = IRFFVideoFrame()
        let probe =
            VideoInputFrameLifecycleProbe()
        duplicateFrame.delegate = probe

        XCTAssertTrue(
            completion.send(
                videoFrame: firstFrame
            )
        )
        XCTAssertFalse(
            completion.send(
                videoFrame: duplicateFrame
            )
        )
        XCTAssertEqual(handledCount, 1)
        XCTAssertEqual(probe.cancelCount, 1)
    }

    func testCustomCompletionDeinitAutoDropsUnresolvedReservation() {
        var droppedCount = 0
        autoreleasepool {
            var completion:
                IRFFCustomVideoDecodeCompletion? =
                IRFFCustomVideoDecodeCompletion {
                    result in
                    if case .dropped = result {
                        droppedCount += 1
                    }
                    return true
                }
            XCTAssertNotNil(completion)
            completion = nil
        }

        XCTAssertEqual(droppedCount, 1)
    }

    func testInvalidatedCustomCompletionRejectsAndReclaimsLateFrame() {
        let completion =
            IRFFCustomVideoDecodeCompletion {
                _ in
                XCTFail(
                    "Invalidated completion must not call its handler"
                )
                return true
            }
        completion.invalidate()
        let frame = IRFFVideoFrame()
        let probe =
            VideoInputFrameLifecycleProbe()
        frame.delegate = probe

        XCTAssertFalse(
            completion.send(
                videoFrame: frame
            )
        )
        XCTAssertEqual(probe.cancelCount, 1)
    }

    func testCodecIdentifiersPreserveKnownAndUnknownRawValues() {
        XCTAssertEqual(
            IRFFVideoCodecIdentifier.h264.rawValue,
            Int32(
                truncatingIfNeeded:
                    AV_CODEC_ID_H264.rawValue
            )
        )
        XCTAssertEqual(
            IRFFVideoCodecIdentifier.hevc.rawValue,
            Int32(
                truncatingIfNeeded:
                    AV_CODEC_ID_HEVC.rawValue
            )
        )
        XCTAssertEqual(
            IRFFVideoCodecIdentifier.mpeg4.rawValue,
            Int32(
                truncatingIfNeeded:
                    AV_CODEC_ID_MPEG4.rawValue
            )
        )
        XCTAssertEqual(
            IRFFVideoCodecIdentifier.mjpeg.rawValue,
            Int32(
                truncatingIfNeeded:
                    AV_CODEC_ID_MJPEG.rawValue
            )
        )
        XCTAssertEqual(
            IRFFVideoCodecIdentifier(rawValue: 91_337).rawValue,
            91_337
        )
    }

    func testPacketDescriptorValidatesCountsAndDerivesKeyFrame() throws {
        XCTAssertNil(
            IRFFVideoPacketDescriptor(
                payloadByteCount: -1,
                sideDataCount: 0,
                presentationTimestamp: nil,
                decodeTimestamp: nil,
                durationTicks: 0,
                streamIndex: 0,
                flags: 0,
                sourcePosition: 0
            )
        )
        let descriptor = try XCTUnwrap(
            IRFFVideoPacketDescriptor(
                payloadByteCount: 128,
                sideDataCount: 2,
                presentationTimestamp: 4,
                decodeTimestamp: 3,
                durationTicks: 1,
                streamIndex: 0,
                flags: 1,
                sourcePosition: 8
            )
        )
        XCTAssertEqual(descriptor.payloadByteCount, 128)
        XCTAssertEqual(descriptor.sideDataCount, 2)
        XCTAssertTrue(descriptor.isKeyFrame)
    }

    func testCodecDescriptorRejectsInvalidGeometry() throws {
        let identifier = IRFFVideoCodecIdentifier.h264
        let pixelFormat = IRFFVideoPixelFormatIdentifier(
            rawValue: 0
        )

        XCTAssertNil(
            IRFFVideoCodecDescriptor(
                identifier: identifier,
                width: -1,
                height: 1,
                pixelFormat: pixelFormat,
                profile: 0,
                level: 0,
                bitrate: 0,
                extraData: Data()
            )
        )
        XCTAssertNil(
            IRFFVideoCodecDescriptor(
                identifier: identifier,
                width: 1,
                height: 0,
                pixelFormat: pixelFormat,
                profile: 0,
                level: 0,
                bitrate: 0,
                extraData: Data()
            )
        )
        XCTAssertNotNil(
            IRFFVideoCodecDescriptor(
                identifier: identifier,
                width: 0,
                height: 0,
                pixelFormat: pixelFormat,
                profile: 0,
                level: 0,
                bitrate: 0,
                extraData: Data()
            )
        )
    }

    func testCodecDescriptorCopiesOneCompleteContextGeneration()
        throws {
        var extraData = [UInt8]([1, 2, 3, 4])
        let descriptor = try extraData.withUnsafeMutableBufferPointer {
            buffer -> IRFFVideoCodecDescriptor in
            var context = AVCodecContext()
            context.codec_id = AV_CODEC_ID_H264
            context.width = 1_920
            context.height = 1_080
            context.pix_fmt = AV_PIX_FMT_YUV420P
            context.profile = 100
            context.level = 42
            context.bit_rate = 8_000_000
            context.extradata = buffer.baseAddress
            context.extradata_size = Int32(buffer.count)
            return try withUnsafePointer(to: &context) {
                try XCTUnwrap(
                    IRFFVideoCodecDescriptor(copying: $0)
                )
            }
        }

        extraData[0] = 99

        XCTAssertEqual(descriptor.identifier, .h264)
        XCTAssertEqual(descriptor.width, 1_920)
        XCTAssertEqual(descriptor.height, 1_080)
        XCTAssertEqual(
            descriptor.pixelFormat.rawValue,
            Int32(
                truncatingIfNeeded:
                    AV_PIX_FMT_YUV420P.rawValue
            )
        )
        XCTAssertEqual(descriptor.profile, 100)
        XCTAssertEqual(descriptor.level, 42)
        XCTAssertEqual(descriptor.bitrate, 8_000_000)
        XCTAssertEqual(
            descriptor.extraData,
            Data([1, 2, 3, 4])
        )
    }

    func testCodecDescriptorRejectsMalformedContextStorage() {
        var context = AVCodecContext()
        context.width = 1
        context.height = 1
        context.extradata_size = 1
        context.extradata = nil

        withUnsafePointer(to: &context) {
            XCTAssertNil(
                IRFFVideoCodecDescriptor(copying: $0)
            )
        }

        context.extradata_size = -1
        withUnsafePointer(to: &context) {
            XCTAssertNil(
                IRFFVideoCodecDescriptor(copying: $0)
            )
        }

        context.extradata_size = 0
        context.width = 1
        context.height = 0
        withUnsafePointer(to: &context) {
            XCTAssertNil(
                IRFFVideoCodecDescriptor(copying: $0)
            )
        }
    }

    func testPacketCopiesPayloadTimingFlagsAndPosition() throws {
        var payload = [UInt8]([10, 20, 30, 40])
        let packetValue = try payload.withUnsafeMutableBufferPointer {
            buffer -> IRFFCompressedVideoPacket in
            var packet = AVPacket()
            packet.data = buffer.baseAddress
            packet.size = Int32(buffer.count)
            packet.pts = 90
            packet.dts = 80
            packet.duration = 3
            packet.stream_index = 2
            packet.flags = 1
            packet.pos = 1_024
            return try XCTUnwrap(
                IRFFCompressedVideoPacket(copying: packet)
            )
        }

        payload[0] = 99

        XCTAssertEqual(
            packetValue.data,
            Data([10, 20, 30, 40])
        )
        XCTAssertEqual(packetValue.presentationTimestamp, 90)
        XCTAssertEqual(packetValue.decodeTimestamp, 80)
        XCTAssertEqual(packetValue.durationTicks, 3)
        XCTAssertEqual(packetValue.streamIndex, 2)
        XCTAssertEqual(packetValue.flags, 1)
        XCTAssertTrue(packetValue.isKeyFrame)
        XCTAssertEqual(packetValue.sourcePosition, 1_024)
        XCTAssertTrue(packetValue.sideData.isEmpty)
    }

    func testPacketMapsMissingTimestampsAndAllowsEmptyPayload()
        throws {
        var packet = AVPacket()
        packet.pts = IR_AV_NOPTS_VALUE
        packet.dts = IR_AV_NOPTS_VALUE
        packet.size = 0
        packet.data = nil

        let packetValue = try XCTUnwrap(
            IRFFCompressedVideoPacket(copying: packet)
        )

        XCTAssertTrue(packetValue.data.isEmpty)
        XCTAssertNil(packetValue.presentationTimestamp)
        XCTAssertNil(packetValue.decodeTimestamp)
        XCTAssertFalse(packetValue.isKeyFrame)
    }

    func testPacketCopiesOrderedSideDataAndSurvivesMutation()
        throws {
        var firstBytes = [UInt8]([1, 2])
        var secondBytes = [UInt8]([3, 4, 5])
        let packetValue = try firstBytes
            .withUnsafeMutableBufferPointer { firstBuffer in
                try secondBytes.withUnsafeMutableBufferPointer {
                    secondBuffer in
                    var entries = [
                        AVPacketSideData(),
                        AVPacketSideData()
                    ]
                    entries[0].data = firstBuffer.baseAddress
                    entries[0].size = firstBuffer.count
                    entries[0].type =
                        AV_PKT_DATA_NEW_EXTRADATA
                    entries[1].data = secondBuffer.baseAddress
                    entries[1].size = secondBuffer.count
                    entries[1].type =
                        AV_PKT_DATA_DISPLAYMATRIX

                    return try entries
                        .withUnsafeMutableBufferPointer {
                            entryBuffer in
                            var packet = AVPacket()
                            packet.side_data =
                                entryBuffer.baseAddress
                            packet.side_data_elems =
                                Int32(entryBuffer.count)
                            return try XCTUnwrap(
                                IRFFCompressedVideoPacket(
                                    copying: packet
                                )
                            )
                        }
                }
            }

        firstBytes[0] = 99
        secondBytes[0] = 98

        XCTAssertEqual(packetValue.sideData.count, 2)
        XCTAssertEqual(
            packetValue.sideData.map(\.identifier.rawValue),
            [
                Int32(
                    truncatingIfNeeded:
                        AV_PKT_DATA_NEW_EXTRADATA.rawValue
                ),
                Int32(
                    truncatingIfNeeded:
                        AV_PKT_DATA_DISPLAYMATRIX.rawValue
                )
            ]
        )
        XCTAssertEqual(
            packetValue.sideData.map(\.data),
            [Data([1, 2]), Data([3, 4, 5])]
        )
    }

    func testPacketRejectsMalformedPayloadAndSideData() {
        var packet = AVPacket()
        packet.size = -1
        XCTAssertNil(IRFFCompressedVideoPacket(copying: packet))

        packet.size = 1
        packet.data = nil
        XCTAssertNil(IRFFCompressedVideoPacket(copying: packet))

        packet.size = 0
        packet.side_data_elems = -1
        XCTAssertNil(IRFFCompressedVideoPacket(copying: packet))

        packet.side_data_elems = 1
        packet.side_data = nil
        XCTAssertNil(IRFFCompressedVideoPacket(copying: packet))

        var entry = AVPacketSideData()
        entry.size = 1
        entry.data = nil
        withUnsafeMutablePointer(to: &entry) {
            packet.side_data = $0
            XCTAssertNil(
                IRFFCompressedVideoPacket(copying: packet)
            )
        }
    }

    func testPublicValuesHaveValueSemanticsAndAreSendable()
        throws {
        var codecBytes = Data([1, 2, 3])
        var packetBytes = Data([4, 5, 6])
        let codec = try XCTUnwrap(
            IRFFVideoCodecDescriptor(
                identifier: .h264,
                width: 2,
                height: 2,
                pixelFormat:
                    IRFFVideoPixelFormatIdentifier(rawValue: 0),
                profile: 100,
                level: 40,
                bitrate: 1_000,
                extraData: codecBytes
            )
        )
        let packet = IRFFCompressedVideoPacket(
            data: packetBytes,
            presentationTimestamp: nil,
            decodeTimestamp: nil,
            durationTicks: 1,
            streamIndex: 0,
            flags: 0,
            sourcePosition: -1
        )
        let info = IRFFVideoDecoderInfo(
            codec: codec,
            isHardwareDecodingEnabled: true,
            maximumDecodeDuration: 2,
            timebase: 0.001,
            framesPerSecond: 30
        )

        codecBytes[0] = 9
        packetBytes[0] = 8

        requireSendable(codec)
        requireSendable(packet)
        requireSendable(info)
        XCTAssertEqual(codec.extraData, Data([1, 2, 3]))
        XCTAssertEqual(packet.data, Data([4, 5, 6]))
        XCTAssertEqual(info.codec, codec)
    }

    private func makeCodecDescriptor()
        throws -> IRFFVideoCodecDescriptor {
        try XCTUnwrap(
            IRFFVideoCodecDescriptor(
                identifier: .h264,
                width: 2,
                height: 2,
                pixelFormat:
                    IRFFVideoPixelFormatIdentifier(rawValue: 0),
                profile: 100,
                level: 40,
                bitrate: 1_000,
                extraData: Data([1, 2, 3])
            )
        )
    }

    private func requireSendable<T: Sendable>(_ value: T) {
        _ = value
    }
}

private final class RecordingFFDecoderVideoOutput:
    NSObject,
    IRFFDecoderVideoOutput
{
    private(set) var receivedFrames: [IRFFVideoFrame] = []

    func send(videoFrame frame: IRFFVideoFrame) {
        receivedFrames.append(frame)
    }
}

private final class BoundedFFDecoderVideoOutput:
    NSObject,
    IRFFDecoderVideoOutput
{
    private let accepts: Bool
    private(set) var callCount = 0

    init(accepts: Bool) {
        self.accepts = accepts
    }

    func trySend(
        videoFrame frame: IRFFVideoFrame
    ) -> Bool {
        callCount += 1
        if !accepts {
            frame.cancel()
        }
        return accepts
    }
}

private final class VideoInputFrameLifecycleProbe:
    NSObject,
    IRFFFrameDelegate
{
    private(set) var cancelCount = 0

    func frameDidStartPlaying(
        _ frame: IRFFFrame
    ) {}

    func frameDidStopPlaying(
        _ frame: IRFFFrame
    ) {}

    func frameDidCancel(
        _ frame: IRFFFrame
    ) {
        cancelCount += 1
    }
}
