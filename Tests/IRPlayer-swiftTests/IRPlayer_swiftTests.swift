//
//  IRPlayer_swiftTests.swift
//  IRPlayer-swiftTests
//
//  Created by Phil Chang on 2022/4/11.
//  Copyright © 2022 Phil. All rights reserved.
//

import AVFoundation
import CoreGraphics
import IRFFMpeg
import simd
import XCTest
@testable import IRPlayer_swift

final class IRPlayerImpLazyPlayerTests: XCTestCase {

    func testLazyPlayerFactoriesReturnExistingPlayersOrCreateNewOnes() {
        let abstractPlayer = IRPlayerImp.player()

        let existingAVPlayer = IRAVPlayer(abstractPlayer: abstractPlayer)
        XCTAssertTrue(IRPlayerImp.makeAVPlayerIfNeeded(existingAVPlayer, abstractPlayer: abstractPlayer) === existingAVPlayer)

        let createdAVPlayer = IRPlayerImp.makeAVPlayerIfNeeded(nil, abstractPlayer: abstractPlayer)
        XCTAssertTrue(createdAVPlayer.abstractPlayer === abstractPlayer)

        let existingFFPlayer = IRFFPlayer.player(with: abstractPlayer)
        XCTAssertTrue(IRPlayerImp.makeFFPlayerIfNeeded(existingFFPlayer, abstractPlayer: abstractPlayer) === existingFFPlayer)

        let createdFFPlayer = IRPlayerImp.makeFFPlayerIfNeeded(nil, abstractPlayer: abstractPlayer)
        XCTAssertTrue(createdFFPlayer.abstractPlayer === abstractPlayer)

        withExtendedLifetime((existingAVPlayer, createdAVPlayer, existingFFPlayer, createdFFPlayer, abstractPlayer)) {}
    }
}

final class IRFFFramePoolTests: XCTestCase {

    func testDefaultPoolsCreateExpectedFrameTypesWithoutModuleNameLookup() {
        let videoFrame = IRFFFramePool.videoPool().getUnuseFrame()
        let audioFrame = IRFFFramePool.audioPool().getUnuseFrame()

        XCTAssertTrue(videoFrame is IRFFAVYUVVideoFrame)
        XCTAssertTrue(audioFrame is IRFFAudioFrame)
    }

    func testFramePoolMovesFramesThroughUsedPlayingAndUnuseBuckets() throws {
        let pool = IRFFFramePool.pool(withCapacity: 2, frameClassName: IRFFFrame.self)
        let frame = try XCTUnwrap(pool.getUnuseFrame())

        XCTAssertEqual(pool.usedCount, 1)
        XCTAssertEqual(pool.unuseCount, 0)

        frame.startPlaying()
        XCTAssertEqual(pool.usedCount, 0)
        XCTAssertEqual(pool.unuseCount, 0)
        XCTAssertTrue(pool.playingFrame === frame)

        frame.stopPlaying()
        XCTAssertNil(pool.playingFrame)
        XCTAssertEqual(pool.usedCount, 0)
        XCTAssertEqual(pool.unuseCount, 1)
    }
}

final class IRFFAVYUVVideoFrameTests: XCTestCase {

    func testImageReturnsNilWhenFrameDataIsMissing() {
        let frame = IRFFAVYUVVideoFrame()

        let image: IRPLFImage? = frame.image()

        XCTAssertNil(image)
    }

    func testSetFrameDataIgnoresMissingPlaneData() {
        var avFrame = AVFrame()
        avFrame.format = 0
        let frame = IRFFAVYUVVideoFrame()

        withUnsafePointer(to: &avFrame) { pointer in
            frame.setFrameData(pointer, width: 4, height: 4)
        }

        XCTAssertNil(frame.image())
    }
}

final class IRFFVideoToolBoxTests: XCTestCase {

    func testThreeByteNALPayloadValidationRejectsTruncatedUnits() throws {
        try assertThreeByteNALPayload([0, 0, 1, 42], isValid: true)
        try assertThreeByteNALPayload([0, 0], isValid: false)
        try assertThreeByteNALPayload([0, 0, 5, 1, 2], isValid: false)
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

    func testConvertedNALBlockPayloadRejectsMissingOrInvalidBuffer() {
        XCTAssertNil(IRFFVideoToolBox.convertedNALBlockPayload(memoryBlock: nil, demuxSize: 4, packetSize: 4))

        var bytes = [UInt8](arrayLiteral: 1, 2, 3, 4)
        bytes.withUnsafeMutableBufferPointer { buffer in
            let pointer = buffer.baseAddress

            XCTAssertNil(IRFFVideoToolBox.convertedNALBlockPayload(memoryBlock: pointer, demuxSize: 0, packetSize: 4))
            XCTAssertNil(IRFFVideoToolBox.convertedNALBlockPayload(memoryBlock: pointer, demuxSize: 4, packetSize: 0))

            let payload = IRFFVideoToolBox.convertedNALBlockPayload(memoryBlock: pointer, demuxSize: 5, packetSize: 4)
            XCTAssertEqual(payload?.memoryBlock, pointer)
            XCTAssertEqual(payload?.blockLength, 5)
            XCTAssertEqual(payload?.dataLength, 4)
        }
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

    func testOutputCallbackIgnoresMissingRefConAndUpdatesDecoderState() {
        IRFFVideoToolBox.handleOutputCallback(refCon: nil, status: -1, imageBuffer: nil)

        var codecContext = AVCodecContext()
        withUnsafeMutablePointer(to: &codecContext) { context in
            let videoToolBox = IRFFVideoToolBox.videoToolBox(with: context)
            let refCon = UnsafeMutableRawPointer(Unmanaged.passUnretained(videoToolBox).toOpaque())

            IRFFVideoToolBox.handleOutputCallback(refCon: refCon, status: -2, imageBuffer: nil)

            XCTAssertEqual(videoToolBox.decodeStatus, -2)
            XCTAssertNil(videoToolBox.decodeOutput)
        }
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
}

final class IRFFDecoderOperationTests: XCTestCase {

    func testCodecContextHelpersRejectMissingOrDisabledFormatContext() {
        let formatContext = IRFFFormatContext(contentURL: URL(fileURLWithPath: "/tmp/missing.mp4"), videoFormat: .mpeg4)

        XCTAssertNil(IRFFDecoder.videoCodecContext(from: nil))
        XCTAssertNil(IRFFDecoder.audioCodecContext(from: nil))
        XCTAssertNil(IRFFDecoder.videoCodecContext(from: formatContext))
        XCTAssertNil(IRFFDecoder.audioCodecContext(from: formatContext))
    }

    func testOperationSchedulingTreatsMissingOrFinishedOperationsAsSchedulable() {
        XCTAssertTrue(IRFFDecoder.needsScheduling(nil))

        let operation = BlockOperation {}
        XCTAssertFalse(IRFFDecoder.needsScheduling(operation))

        operation.start()
        XCTAssertTrue(operation.isFinished)
        XCTAssertTrue(IRFFDecoder.needsScheduling(operation))
    }

    func testOperationHelpersIgnoreMissingInputsAndWireDependencies() {
        let queue = OperationQueue()
        queue.isSuspended = true

        let operation = BlockOperation {}
        let dependency = BlockOperation {}

        XCTAssertFalse(IRFFDecoder.addDependency(dependency, to: nil))
        XCTAssertFalse(IRFFDecoder.addDependency(nil, to: operation))
        XCTAssertTrue(IRFFDecoder.addDependency(dependency, to: operation))
        XCTAssertTrue(operation.dependencies.contains { $0 === dependency })

        XCTAssertFalse(IRFFDecoder.enqueue(nil, on: queue))
        XCTAssertFalse(IRFFDecoder.enqueue(operation, on: nil))
        XCTAssertTrue(IRFFDecoder.enqueue(operation, on: queue))
        XCTAssertTrue(queue.operations.contains { $0 === operation })

        queue.cancelAllOperations()
        queue.isSuspended = false
    }

    func testAudioPacketErrorUsesPacketResult() throws {
        XCTAssertNil(IRFFDecoder.audioPacketError(fromPacketResult: 0))

        let error = try XCTUnwrap(IRFFDecoder.audioPacketError(fromPacketResult: -1))
        XCTAssertEqual(error.code, IRFFDecoderErrorCode.codecAudioSendPacket.rawValue)
        XCTAssertTrue(error.domain.contains("ffmpeg code: -1"))
    }
}

final class IRFFAudioDecoderTests: XCTestCase {

    func testAudioDataBufferRejectsMissingDecodedData() {
        XCTAssertNil(IRFFAudioDecoder.audioDataBuffer(fromDecodedData: nil))

        var byte: UInt8 = 0
        withUnsafeMutablePointer(to: &byte) { pointer in
            let rawPointer = UnsafeMutableRawPointer(pointer)
            XCTAssertEqual(IRFFAudioDecoder.audioDataBuffer(fromDecodedData: pointer), rawPointer)
        }
    }

    func testAudioDataBufferRejectsMissingSwrBuffer() {
        XCTAssertNil(IRFFAudioDecoder.audioDataBuffer(fromSwrBuffer: nil))

        var byte: UInt8 = 0
        withUnsafeMutablePointer(to: &byte) { pointer in
            let rawPointer = UnsafeMutableRawPointer(pointer)
            XCTAssertEqual(IRFFAudioDecoder.audioDataBuffer(fromSwrBuffer: rawPointer), rawPointer)
        }
    }

    func testInputChannelCapacityRejectsMissingOrInvalidCodecContext() {
        XCTAssertNil(IRFFAudioDecoder.inputChannelCapacity(from: nil))

        var codecContext = AVCodecContext()
        codecContext.channels = 0

        withUnsafeMutablePointer(to: &codecContext) { contextPointer in
            XCTAssertNil(IRFFAudioDecoder.inputChannelCapacity(from: contextPointer))

            contextPointer.pointee.channels = 2
            XCTAssertEqual(IRFFAudioDecoder.inputChannelCapacity(from: contextPointer), 2)
        }
    }

    func testSampleElementCountRejectsEmptyInputs() {
        XCTAssertNil(IRFFAudioDecoder.sampleElementCount(numberOfFrames: 0, channelCount: 2))
        XCTAssertNil(IRFFAudioDecoder.sampleElementCount(numberOfFrames: 4, channelCount: 0))
        XCTAssertNil(IRFFAudioDecoder.sampleElementCount(numberOfFrames: -1, channelCount: 2))
        XCTAssertEqual(IRFFAudioDecoder.sampleElementCount(numberOfFrames: 3, channelCount: 2), 6)
    }
}

final class IRFFToolsTests: XCTestCase {

    func testFFLogIgnoresInvalidUTF8FormatString() throws {
        let invalidFormat: [CChar] = [-1, 0]

        try invalidFormat.withUnsafeBufferPointer { formatBuffer in
            let format = try XCTUnwrap(formatBuffer.baseAddress)
            withVaList([]) { args in
                IRFFLog(context: nil, level: 0, format: format, args: args)
            }
        }
    }

    func testStreamTimebaseFallsBackToFiniteValueForInvalidStreamAndDefault() {
        var stream = AVStream()
        stream.time_base = AVRational(num: 0, den: 0)

        let timebase = withUnsafePointer(to: &stream) { streamPointer in
            IRFFStreamGetTimebase(streamPointer, defaultTimebase: 0)
        }

        XCTAssertEqual(timebase, 1)
        XCTAssertTrue(timebase.isFinite)
    }

    func testStreamFPSFallsBackToFiniteValueForInvalidRatesAndTimebase() {
        var stream = AVStream()
        stream.avg_frame_rate = AVRational(num: 0, den: 0)
        stream.r_frame_rate = AVRational(num: 0, den: 0)

        let fps = withUnsafePointer(to: &stream) { streamPointer in
            IRFFStreamGetFPS(streamPointer, timebase: 0)
        }

        XCTAssertEqual(fps, 1)
        XCTAssertTrue(fps.isFinite)
    }
}

final class IRGLProgram2DFisheye2PanoTests: XCTestCase {

    func testTextureSizeRejectsMissingParamsAndReturnsExistingDimensions() {
        XCTAssertNil(IRGLProgram2DFisheye2Pano.textureSize(from: nil))

        let params = IRGLFish2PanoShaderParams()
        params.textureWidth = 1920
        params.textureHeight = 960

        let size = IRGLProgram2DFisheye2Pano.textureSize(from: params)
        XCTAssertEqual(size?.width, 1920)
        XCTAssertEqual(size?.height, 960)
    }
}

final class IRGLGestureControllerTests: XCTestCase {

    func testClearingCurrentModeClearsSmoothScrollMode() {
        let view = IRGLView(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        let smoothScroll = IRSmoothScrollController(targetView: view)
        let gestureController = IRGLGestureController()

        gestureController.smoothScroll = smoothScroll
        gestureController.currentMode = IRGLRenderMode2D()

        gestureController.currentMode = nil

        XCTAssertNil(smoothScroll.currentMode)
        withExtendedLifetime(smoothScroll) {}
    }

    func testAddGestureReplacesExistingRotationGestureRecognizer() {
        let view = IRGLView(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        let gestureController = IRGLGestureController()

        gestureController.addGesture(to: view)
        gestureController.addGesture(to: view)

        let rotationRecognizers = view.gestureRecognizers?.filter { $0 is UIRotationGestureRecognizer } ?? []
        XCTAssertEqual(rotationRecognizers.count, 1)
    }

    func testRemoveGestureRemovesRotationGestureRecognizer() {
        let view = IRGLView(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        let gestureController = IRGLGestureController()

        gestureController.addGesture(to: view)
        gestureController.removeGesture(to: view)

        let rotationRecognizers = view.gestureRecognizers?.filter { $0 is UIRotationGestureRecognizer } ?? []
        XCTAssertTrue(rotationRecognizers.isEmpty)
    }
}

final class IRGLViewSnapshotTests: XCTestCase {

    func testCreateImageFromFramebufferReturnsImageForZeroSizedView() {
        let view = IRGLView(frame: .zero)

        let image = view.createImageFromFramebuffer()

        XCTAssertEqual(image.size, .zero)
    }
}
