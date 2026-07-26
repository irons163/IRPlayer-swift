import CoreMedia
import CoreVideo
import Foundation
import IRFFMpeg
import IRPlayerObjc
import VideoToolbox
import XCTest
#if SWIFT_PACKAGE
@testable import IRPlayerSwift
#else
@testable import IRPlayer_swift
#endif

final class IRFFVideoToolBoxTests: XCTestCase {

    func testSetupValidationMapsCodecAndExtradataFailures() {
        XCTAssertEqual(
            IRFFVideoToolBox.setupValidationError(codecID: AV_CODEC_ID_AAC, extradata: nil, extradataSize: 0, firstExtradataByte: nil),
            .notH264
        )
        XCTAssertEqual(
            IRFFVideoToolBox.setupValidationError(codecID: AV_CODEC_ID_H264, extradata: nil, extradataSize: 7, firstExtradataByte: nil),
            .extradataSize
        )
        XCTAssertEqual(
            IRFFVideoToolBox.setupValidationError(codecID: AV_CODEC_ID_H264, extradata: UnsafeMutablePointer<UInt8>(bitPattern: 1), extradataSize: 6, firstExtradataByte: 1),
            .extradataSize
        )
        XCTAssertEqual(
            IRFFVideoToolBox.setupValidationError(codecID: AV_CODEC_ID_H264, extradata: UnsafeMutablePointer<UInt8>(bitPattern: 1), extradataSize: 7, firstExtradataByte: 0),
            .extradataData
        )
        XCTAssertNil(
            IRFFVideoToolBox.setupValidationError(codecID: AV_CODEC_ID_H264, extradata: UnsafeMutablePointer<UInt8>(bitPattern: 1), extradataSize: 7, firstExtradataByte: 1)
        )
    }

    func testDecodeFrameSucceededRequiresStatusCallbackAndOutput() {
        XCTAssertFalse(IRFFVideoToolBox.decodeFrameSucceeded(status: -1, callbackStatus: noErr, hasOutput: true))
        XCTAssertFalse(IRFFVideoToolBox.decodeFrameSucceeded(status: noErr, callbackStatus: -1, hasOutput: true))
        XCTAssertTrue(
            IRFFVideoToolBox.decodeFrameSucceeded(
                status: noErr,
                callbackStatus: noErr,
                hasOutput: false
            ),
            "A successful decode with no image is a consumed drop, not a software-fallback signal"
        )
    }

    func testNALLengthSizeDecisionNormalizesThreeByteMarker() {
        let threeByteDecision = IRFFVideoToolBox
            .nalLengthSizeDecision(for: 0xFE)
        XCTAssertEqual(threeByteDecision.normalizedMarker, 0xFF)
        XCTAssertTrue(
            threeByteDecision.shouldConvertThreeByteNALUnits
        )

        let fourByteDecision = IRFFVideoToolBox
            .nalLengthSizeDecision(for: 0xFF)
        XCTAssertEqual(fourByteDecision.normalizedMarker, 0xFF)
        XCTAssertFalse(
            fourByteDecision.shouldConvertThreeByteNALUnits
        )
    }

    func testThreeByteNALPayloadValidationRejectsTruncatedUnits() throws {
        try assertThreeByteNALPayload([0, 0, 1, 42], isValid: true)
        try assertThreeByteNALPayload([0, 0], isValid: false)
        try assertThreeByteNALPayload([0, 0, 5, 1, 2], isValid: false)
    }

    func testNALPayloadAdvanceValidationUsesRemainingByteCount() {
        XCTAssertTrue(IRFFVideoToolBox.nalPayloadCanAdvance(nalSize: 2, remainingByteCount: 2))
        XCTAssertFalse(IRFFVideoToolBox.nalPayloadCanAdvance(nalSize: 3, remainingByteCount: 2))
        XCTAssertFalse(IRFFVideoToolBox.nalPayloadCanAdvance(nalSize: 0, remainingByteCount: -1))
    }

    func testPacketPayloadRejectsMissingOrEmptyPacketData() {
        var packet = AVPacket()
        packet.size = 4
        XCTAssertNil(IRFFVideoToolBox.packetPayload(for: packet))

        var bytes = [UInt8](arrayLiteral: 1, 2, 3, 4)
        bytes.withUnsafeMutableBufferPointer { buffer in
            packet.data = buffer.baseAddress
            packet.size = 0
            XCTAssertNil(IRFFVideoToolBox.packetPayload(for: packet))

            packet.size = Int32(buffer.count)
            let payload = IRFFVideoToolBox.packetPayload(for: packet)
            XCTAssertEqual(payload?.data, buffer.baseAddress)
            XCTAssertEqual(payload?.size, Int32(buffer.count))
        }
    }

    func testOwnedPacketBlockBufferDoesNotBorrowPacketMemory() throws {
        var source: [UInt8] =
            [1, 2, 3, 4]
        let blockBuffer = try source
            .withUnsafeMutableBufferPointer {
                buffer -> CMBlockBuffer in
                let payload =
                    IRFFVideoToolBox
                    .PacketPayload(
                        data:
                            try XCTUnwrap(
                                buffer.baseAddress
                            ),
                        size:
                            Int32(buffer.count)
                )
                let block = try XCTUnwrap(
                    IRFFVideoToolBox
                        .makeOwnedBlockBuffer(
                            from: payload
                        )
                )
                buffer[0] = 99
                return block
            }
        var copied = [UInt8](
            repeating: 0,
            count: source.count
        )
        let copiedCount = copied.count
        let status = copied
            .withUnsafeMutableBytes {
                bytes in
                CMBlockBufferCopyDataBytes(
                    blockBuffer,
                    atOffset: 0,
                    dataLength:
                        copiedCount,
                    destination:
                        bytes.baseAddress!
                )
            }

        XCTAssertEqual(status, noErr)
        XCTAssertEqual(copied, [1, 2, 3, 4])
        XCTAssertEqual(source[0], 99)
    }

    func testPacketSampleTimingUsesPTSDecodeTimeAndDuration() {
        var packet = AVPacket()
        packet.pts = 9_000
        packet.dts = 8_000
        packet.duration = 3_000

        let timing =
            IRFFVideoToolBox.sampleTiming(
                for: packet,
                timebase: 1.0 / 90_000
            )

        XCTAssertEqual(
            CMTimeGetSeconds(
                timing
                    .presentationTimeStamp
            ),
            0.1,
            accuracy: 0.000001
        )
        XCTAssertEqual(
            CMTimeGetSeconds(
                timing.decodeTimeStamp
            ),
            8.0 / 90,
            accuracy: 0.000001
        )
        XCTAssertEqual(
            CMTimeGetSeconds(
                timing.duration
            ),
            1.0 / 30,
            accuracy: 0.000001
        )
    }

    func testPacketSampleTimingFallsBackToDTSAndRejectsInvalidValues() {
        var packet = AVPacket()
        packet.pts = IR_AV_NOPTS_VALUE
        packet.dts = 45
        packet.duration = 0

        var timing =
            IRFFVideoToolBox.sampleTiming(
                for: packet,
                timebase: 0.001
            )
        XCTAssertEqual(
            CMTimeGetSeconds(
                timing
                    .presentationTimeStamp
            ),
            0.045,
            accuracy: 0.000001
        )
        XCTAssertFalse(timing.duration.isValid)

        packet.dts = IR_AV_NOPTS_VALUE
        timing =
            IRFFVideoToolBox.sampleTiming(
                for: packet,
                timebase: .nan
            )
        XCTAssertFalse(
            timing
                .presentationTimeStamp
                .isValid
        )
        XCTAssertFalse(
            timing.decodeTimeStamp.isValid
        )
    }

    func testSampleBufferPublishesTimingAndSampleSize() throws {
        var bytes: [UInt8] =
            [0, 0, 0, 1]
        let blockBuffer = try bytes
            .withUnsafeMutableBufferPointer {
                buffer in
                try XCTUnwrap(
                    IRFFVideoToolBox
                        .makeOwnedBlockBuffer(
                            from: .init(
                                data:
                                    XCTUnwrap(
                                        buffer
                                            .baseAddress
                                    ),
                                size:
                                    Int32(
                                        buffer.count
                                    )
                            )
                        )
                )
            }
        var formatDescription:
            CMFormatDescription?
        XCTAssertEqual(
            CMVideoFormatDescriptionCreate(
                allocator: nil,
                codecType:
                    kCMVideoCodecType_H264,
                width: 16,
                height: 16,
                extensions: nil,
                formatDescriptionOut:
                    &formatDescription
            ),
            noErr
        )
        let timing = CMSampleTimingInfo(
            duration:
                CMTime(
                    value: 1,
                    timescale: 30
                ),
            presentationTimeStamp:
                CMTime(
                    value: 3,
                    timescale: 30
                ),
            decodeTimeStamp:
                CMTime(
                    value: 2,
                    timescale: 30
                )
        )
        let sampleBuffer = try XCTUnwrap(
            IRFFVideoToolBox
                .makeSampleBuffer(
                    blockBuffer: blockBuffer,
                    formatDescription:
                        XCTUnwrap(
                            formatDescription
                        ),
                    timing: timing,
                    sampleSize: bytes.count
                )
        )

        XCTAssertEqual(
            CMSampleBufferGetNumSamples(
                sampleBuffer
            ),
            1
        )
        XCTAssertEqual(
            CMSampleBufferGetSampleSize(
                sampleBuffer,
                at: 0
            ),
            bytes.count
        )
        XCTAssertEqual(
            CMTimeGetSeconds(
                CMSampleBufferGetPresentationTimeStamp(
                    sampleBuffer
                )
            ),
            0.1,
            accuracy: 0.000001
        )
    }

    func testConvertedNALBlockPayloadRejectsMissingOrInvalidBuffer() {
        XCTAssertNil(IRFFVideoToolBox.convertedNALBlockPayload(memoryBlock: nil, demuxSize: 4, packetSize: 4))

        var bytes = [UInt8](arrayLiteral: 1, 2, 3, 4)
        bytes.withUnsafeMutableBufferPointer { buffer in
            let pointer = buffer.baseAddress

            XCTAssertNil(IRFFVideoToolBox.convertedNALBlockPayload(memoryBlock: pointer, demuxSize: 0, packetSize: 4))
            XCTAssertNil(IRFFVideoToolBox.convertedNALBlockPayload(memoryBlock: pointer, demuxSize: 4, packetSize: 0))
            XCTAssertNil(IRFFVideoToolBox.convertedNALBlockPayload(memoryBlock: pointer, demuxSize: 4, packetSize: 5))

            let payload = IRFFVideoToolBox.convertedNALBlockPayload(memoryBlock: pointer, demuxSize: 5, packetSize: 4)
            XCTAssertEqual(payload?.memoryBlock, pointer)
            XCTAssertEqual(payload?.blockLength, 5)
            XCTAssertEqual(payload?.dataLength, 5)
        }
    }

    func testConvertedNALBlockPayloadOwnsDemuxBufferRelease() {
        var bytes = [UInt8](arrayLiteral: 1, 2, 3, 4)
        bytes.withUnsafeMutableBufferPointer { buffer in
            let payload = IRFFVideoToolBox.convertedNALBlockPayload(
                memoryBlock: buffer.baseAddress,
                demuxSize: 4,
                packetSize: 4
            )

            XCTAssertNotNil(payload?.customBlockSource.FreeBlock)
        }
    }

    func testConvertedNALBlockPayloadFreeBlockReleasesAllocatedDemuxBuffer() throws {
        guard let rawMemoryBlock = malloc(4) else {
            throw XCTSkip("Allocator unavailable")
        }
        var didReleaseMemoryBlock = false
        defer {
            if !didReleaseMemoryBlock {
                free(rawMemoryBlock)
            }
        }

        let memoryBlock = rawMemoryBlock.assumingMemoryBound(to: UInt8.self)
        let payload = try XCTUnwrap(IRFFVideoToolBox.convertedNALBlockPayload(
            memoryBlock: memoryBlock,
            demuxSize: 4,
            packetSize: 4
        ))
        let freeBlock = try XCTUnwrap(payload.customBlockSource.FreeBlock)

        freeBlock(payload.customBlockSource.refCon, rawMemoryBlock, payload.blockLength)
        didReleaseMemoryBlock = true
    }

    private func assertThreeByteNALPayload(_ bytes: [UInt8], isValid: Bool, file: StaticString = #filePath, line: UInt = #line) throws {
        var packet = AVPacket()
        var bytes = bytes

        let isBounded = try bytes.withUnsafeMutableBufferPointer { buffer in
            let data = try XCTUnwrap(buffer.baseAddress)
            packet.data = data
            packet.size = Int32(buffer.count)
            let payload = try XCTUnwrap(IRFFVideoToolBox.packetPayload(for: packet))
            return IRFFVideoToolBox.threeByteNALUnitsAreBounded(in: payload)
        }

        XCTAssertEqual(isBounded, isValid, file: file, line: line)
    }

    func testOutputCallbackIgnoresMissingRefConAndUpdatesRetainedContext() {
        IRFFVideoToolBox.handleOutputCallback(refCon: nil, status: -1, imageBuffer: nil)

        let callbackState = IRFFVideoToolBoxCallbackState()
        let refCon = UnsafeMutableRawPointer(
            Unmanaged.passRetained(callbackState).toOpaque()
        )
        defer {
            Unmanaged<IRFFVideoToolBoxCallbackState>
                .fromOpaque(refCon)
                .release()
        }

        IRFFVideoToolBox.handleOutputCallback(
            refCon: refCon,
            status: -2,
            imageBuffer: nil
        )

        XCTAssertEqual(callbackState.snapshot.status, -2)
        XCTAssertNil(callbackState.snapshot.imageBuffer)
    }

    func testTrySetupVTSessionReturnsFalseAndReturnsToIdleForInvalidContext() {
        var codecContext = AVCodecContext()
        codecContext.codec_id = AV_CODEC_ID_AAC

        withUnsafeMutablePointer(to: &codecContext) { context in
            let videoToolBox = IRFFVideoToolBox.videoToolBox(with: context)

            XCTAssertFalse(videoToolBox.trySetupVTSession())
            XCTAssertEqual(videoToolBox.diagnostics.phase, .idle)
            XCTAssertFalse(videoToolBox.diagnostics.hasResource)
            XCTAssertFalse(videoToolBox.trySetupVTSession())
            XCTAssertEqual(videoToolBox.diagnostics.phase, .idle)
        }
    }

    func testRepeatedSetupNeverMutatesThreeByteNALCodecExtradata() {
        var codecContext = AVCodecContext()
        codecContext.codec_id = AV_CODEC_ID_H264
        codecContext.width = 0
        codecContext.height = 0

        var extradata = [UInt8](arrayLiteral: 1, 0, 0, 0, 0xFE, 0, 0)
        extradata.withUnsafeMutableBufferPointer { buffer in
            codecContext.extradata = buffer.baseAddress
            codecContext.extradata_size = Int32(buffer.count)

            withUnsafeMutablePointer(to: &codecContext) { context in
                let videoToolBox = IRFFVideoToolBox.videoToolBox(with: context)

                do {
                    try videoToolBox.setupVTSession()
                } catch {
                    XCTAssertTrue(
                        [.createFormatDescription, .createSession]
                            .contains(error as? IRFFVideoToolBoxErrorCode)
                    )
                }
                XCTAssertEqual(buffer[4], 0xFE)
                do {
                    try videoToolBox.setupVTSession()
                } catch {
                    XCTAssertTrue(
                        [.createFormatDescription, .createSession]
                            .contains(error as? IRFFVideoToolBoxErrorCode)
                    )
                }
                XCTAssertEqual(buffer[4], 0xFE)
                XCTAssertNil(videoToolBox.imageBuffer())

                videoToolBox.cleanVTSession()
                XCTAssertEqual(videoToolBox.diagnostics.phase, .idle)
                XCTAssertFalse(videoToolBox.diagnostics.hasResource)
            }
        }
    }

    func testSendPacketShortCircuitsForInvalidSetupAndPackets() {
        var codecContext = AVCodecContext()
        codecContext.codec_id = AV_CODEC_ID_AAC

        withUnsafeMutablePointer(to: &codecContext) { context in
            let videoToolBox = IRFFVideoToolBox.videoToolBox(with: context)

            assertNotAvailable(
                videoToolBox.sendPacket(
                    AVPacket()
                )
            )

            var bytes = [UInt8](arrayLiteral: 0, 0, 0, 1)
            bytes.withUnsafeMutableBufferPointer { buffer in
                let packet = makePacket(data: buffer.baseAddress, size: buffer.count)

                assertNotAvailable(
                    videoToolBox.sendPacket(
                        packet
                    )
                )
            }
            XCTAssertNil(videoToolBox.imageBuffer())
            XCTAssertEqual(videoToolBox.diagnostics.phase, .idle)
        }
    }

    func testFlushIsRepeatableAndCloseIsTerminal() {
        var codecContext = AVCodecContext()
        codecContext.codec_id = AV_CODEC_ID_AAC

        withUnsafeMutablePointer(to: &codecContext) { context in
            let videoToolBox = IRFFVideoToolBox.videoToolBox(with: context)

            videoToolBox.flush()
            videoToolBox.flush()
            XCTAssertEqual(videoToolBox.diagnostics.phase, .idle)

            videoToolBox.close()
            videoToolBox.close()
            videoToolBox.flush()
            XCTAssertEqual(videoToolBox.diagnostics.phase, .closed)
            XCTAssertFalse(videoToolBox.trySetupVTSession())
        }
    }

    func testConcurrentInvalidSetupFlushAndImageAccessRemainSafe() {
        var codecContext = AVCodecContext()
        codecContext.codec_id = AV_CODEC_ID_AAC

        withUnsafeMutablePointer(to: &codecContext) { context in
            let videoToolBox = IRFFVideoToolBox.videoToolBox(with: context)

            DispatchQueue.concurrentPerform(iterations: 1_000) {
                index in
                switch index % 3 {
                case 0:
                    XCTAssertFalse(
                        videoToolBox.trySetupVTSession()
                    )
                case 1:
                    videoToolBox.flush()
                default:
                    XCTAssertNil(videoToolBox.imageBuffer())
                }
            }
            XCTAssertEqual(videoToolBox.diagnostics.phase, .idle)
        }
    }

    func testReleaseDoesNotPrintDebugOutput() {
        var codecContext = AVCodecContext()

        let output = withUnsafeMutablePointer(to: &codecContext) { context in
            var videoToolBox: IRFFVideoToolBox? = IRFFVideoToolBox.videoToolBox(with: context)
            XCTAssertNotNil(videoToolBox)

            return captureStandardOutput {
                videoToolBox = nil
            }
        }

        XCTAssertEqual(output, "")
    }

    func testFormatDescriptionExtensionsIncludeExpectedAVCCAtom() throws {
        let extradata = [UInt8](arrayLiteral: 1, 2, 3, 4)

        let extensions: NSDictionary = try extradata.withUnsafeBufferPointer { buffer in
            let pointer = try XCTUnwrap(buffer.baseAddress)
            return IRFFVideoToolBox.makeFormatDescriptionExtensions(extradata: pointer, extradataSize: Int32(buffer.count)) as NSDictionary
        }

        let atoms = try XCTUnwrap(extensions["SampleDescriptionExtensionAtoms"] as? NSDictionary)
        let avcC = try XCTUnwrap(atoms["avcC"] as? Data)
        XCTAssertEqual(Array(avcC), extradata)
        XCTAssertEqual(extensions["CVImageBufferChromaLocationBottomField"] as? String, "left")
        XCTAssertEqual(extensions["CVImageBufferChromaLocationTopField"] as? String, "left")
        XCTAssertEqual(extensions["FullRangeVideo"] as? Bool, false)
    }

    func testFormatDescriptionExtensionsClampInvalidExtradataSize() throws {
        let extradata = [UInt8](arrayLiteral: 1)

        let extensions: NSDictionary = try extradata.withUnsafeBufferPointer { buffer in
            let pointer = try XCTUnwrap(buffer.baseAddress)
            return IRFFVideoToolBox.makeFormatDescriptionExtensions(extradata: pointer, extradataSize: -1) as NSDictionary
        }

        let atoms = try XCTUnwrap(extensions["SampleDescriptionExtensionAtoms"] as? NSDictionary)
        let avcC = try XCTUnwrap(atoms["avcC"] as? Data)
        XCTAssertEqual(avcC.count, 0)
    }

    func testRequiredFormatDescriptionRejectsMissingDescription() throws {
        XCTAssertNil(IRFFVideoToolBox.requiredFormatDescription(nil))

        var formatDescription: CMFormatDescription?
        let status = CMVideoFormatDescriptionCreate(
            allocator: nil,
            codecType: kCMVideoCodecType_H264,
            width: 16,
            height: 8,
            extensions: nil,
            formatDescriptionOut: &formatDescription
        )

        XCTAssertEqual(status, noErr)
        let payload = try XCTUnwrap(IRFFVideoToolBox.requiredFormatDescription(formatDescription))
        let dimensions = CMVideoFormatDescriptionGetDimensions(payload)
        XCTAssertEqual(dimensions.width, 16)
        XCTAssertEqual(dimensions.height, 8)
    }

    func testDecodeFramePayloadRejectsMissingInputs() {
        XCTAssertNil(IRFFVideoToolBox.decodeFramePayload(session: nil, sampleBuffer: nil))
    }

    func testDecodeFramePayloadWrapsValidInputs() throws {
        var createdFormatDescription: CMFormatDescription?
        let formatStatus = CMVideoFormatDescriptionCreate(
            allocator: nil,
            codecType: kCMVideoCodecType_H264,
            width: 16,
            height: 8,
            extensions: nil,
            formatDescriptionOut: &createdFormatDescription
        )
        XCTAssertEqual(formatStatus, noErr)
        let formatDescription = try XCTUnwrap(createdFormatDescription)

        let pixelBufferAttributes: [CFString: Any] = [
            kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
            kCVPixelBufferWidthKey: 16,
            kCVPixelBufferHeightKey: 8,
            kCVPixelBufferIOSurfacePropertiesKey: [:]
        ]

        var session: VTDecompressionSession?
        var callbackRecord = VTDecompressionOutputCallbackRecord()
        let sessionStatus = VTDecompressionSessionCreate(
            allocator: nil,
            formatDescription: formatDescription,
            decoderSpecification: nil,
            imageBufferAttributes: pixelBufferAttributes as CFDictionary,
            outputCallback: &callbackRecord,
            decompressionSessionOut: &session
        )
        guard sessionStatus == noErr, let session else {
            throw XCTSkip("VideoToolbox decompression session unavailable")
        }
        defer { VTDecompressionSessionInvalidate(session) }

        var sampleBuffer: CMSampleBuffer?
        let sampleStatus = CMSampleBufferCreate(
            allocator: nil,
            dataBuffer: nil,
            dataReady: true,
            makeDataReadyCallback: nil,
            refcon: nil,
            formatDescription: formatDescription,
            sampleCount: 0,
            sampleTimingEntryCount: 0,
            sampleTimingArray: nil,
            sampleSizeEntryCount: 0,
            sampleSizeArray: nil,
            sampleBufferOut: &sampleBuffer
        )
        XCTAssertEqual(sampleStatus, noErr)

        let payload = try XCTUnwrap(IRFFVideoToolBox.decodeFramePayload(session: session, sampleBuffer: sampleBuffer))
        XCTAssertTrue(VTDecompressionSessionCanAcceptFormatDescription(payload.session, formatDescription: formatDescription))
        XCTAssertEqual(CFGetTypeID(payload.sampleBuffer), CMSampleBufferGetTypeID())
    }

    func testDecodeFrameSuccessRequiresAllStatusesAndOutput() {
        XCTAssertTrue(IRFFVideoToolBox.decodeFrameSucceeded(status: noErr, callbackStatus: noErr, hasOutput: true))
        XCTAssertFalse(IRFFVideoToolBox.decodeFrameSucceeded(status: -1, callbackStatus: noErr, hasOutput: true))
        XCTAssertFalse(IRFFVideoToolBox.decodeFrameSucceeded(status: noErr, callbackStatus: -1, hasOutput: true))
        XCTAssertTrue(IRFFVideoToolBox.decodeFrameSucceeded(status: noErr, callbackStatus: noErr, hasOutput: false))
    }

    func testTypedDecodeResultTreatsNilOutputAsConsumedDrop() {
        let result =
            IRFFVideoToolBox
                .classifyDecodeResult(
                    status: noErr,
                    events: [
                        .init(
                            status: noErr,
                            imageBuffer: nil,
                            presentationTimeStamp:
                                .zero,
                            presentationDuration:
                                .zero
                        )
                    ]
                )

        guard case let .accepted(outputs) =
                result else {
            return XCTFail(
                "Expected a consumed VideoToolbox result"
            )
        }
        XCTAssertTrue(outputs.isEmpty)
    }

    func testTypedDecodeResultPreservesEveryCallbackOutput() throws {
        let first = try makePixelBuffer()
        let second = try makePixelBuffer()
        let third = try makePixelBuffer()
        let result =
            IRFFVideoToolBox
                .classifyDecodeResult(
                    status: noErr,
                    events: [
                        .init(
                            status: noErr,
                            imageBuffer: first,
                            presentationTimeStamp:
                                CMTime(
                                    seconds: 1,
                                    preferredTimescale: 600
                                ),
                            presentationDuration:
                                CMTime(
                                    value: 1,
                                    timescale: 30
                                )
                        ),
                        .init(
                            status: noErr,
                            imageBuffer: second,
                            presentationTimeStamp:
                                CMTime(
                                    seconds: 2,
                                    preferredTimescale: 600
                                ),
                            presentationDuration:
                                CMTime(
                                    value: 1,
                                    timescale: 30
                                )
                        ),
                        .init(
                            status: noErr,
                            imageBuffer: third,
                            presentationTimeStamp:
                                CMTime(
                                    seconds: 3,
                                    preferredTimescale: 600
                                ),
                            presentationDuration:
                                CMTime(
                                    value: 1,
                                    timescale: 30
                                )
                        )
                    ]
                )

        guard case let .accepted(outputs) =
                result else {
            return XCTFail(
                "Expected all callback outputs"
            )
        }
        XCTAssertEqual(outputs.count, 3)
        XCTAssertTrue(
            outputs[0].imageBuffer === first
        )
        XCTAssertTrue(
            outputs[1].imageBuffer === second
        )
        XCTAssertTrue(
            outputs[2].imageBuffer === third
        )
        XCTAssertEqual(
            outputs.map {
                CMTimeGetSeconds(
                    $0.presentationTimeStamp
                )
            },
            [1, 2, 3]
        )
    }

    func testTypedDecodeResultFencesDecodeAndCallbackFailures() {
        if case let .failed(status) =
                IRFFVideoToolBox
                    .classifyDecodeResult(
                        status: -7,
                        events: []
                    ) {
            XCTAssertEqual(status, -7)
        } else {
            XCTFail("Expected decode failure")
        }

        if case let .failed(status) =
                IRFFVideoToolBox
                    .classifyDecodeResult(
                        status: noErr,
                        events: [
                            .init(
                                status: -9,
                                imageBuffer: nil,
                                presentationTimeStamp:
                                    .invalid,
                                presentationDuration:
                                    .invalid
                            )
                        ]
                    ) {
            XCTAssertEqual(status, -9)
        } else {
            XCTFail("Expected callback failure")
        }
    }

    private func assertNotAvailable(
        _ result:
            IRFFVideoToolBox.DecodeResult,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard case .notAvailable = result else {
            return XCTFail(
                "Expected VideoToolbox to be unavailable",
                file: file,
                line: line
            )
        }
    }

    private func makePixelBuffer()
        throws -> CVPixelBuffer
    {
        var pixelBuffer: CVPixelBuffer?
        XCTAssertEqual(
            CVPixelBufferCreate(
                nil,
                2,
                2,
                kCVPixelFormatType_32BGRA,
                nil,
                &pixelBuffer
            ),
            kCVReturnSuccess
        )
        return try XCTUnwrap(pixelBuffer)
    }

    private func makePacket(data: UnsafeMutablePointer<UInt8>?, size: Int) -> AVPacket {
        var packet = AVPacket()
        packet.data = data
        packet.size = Int32(size)
        return packet
    }
}
