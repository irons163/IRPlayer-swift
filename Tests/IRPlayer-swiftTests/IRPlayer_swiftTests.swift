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

final class IRPlayerDecoderTests: XCTestCase {

    func testVideoFormatResolverClassifiesNilAsError() {
        XCTAssertEqual(IRVideoFormatResolver.format(for: nil), .error)
    }

    func testVideoFormatResolverClassifiesSchemesAndExtensionsCaseInsensitively() {
        XCTAssertEqual(IRVideoFormatResolver.format(for: NSURL(string: "RTMP://example.com/live")), .rtmp)
        XCTAssertEqual(IRVideoFormatResolver.format(for: NSURL(string: "rtsp://example.com/live")), .rtsp)
        XCTAssertEqual(IRVideoFormatResolver.format(for: NSURL(string: "https://example.com/movie.MP4?token=1")), .mpeg4)
        XCTAssertEqual(IRVideoFormatResolver.format(for: NSURL(string: "https://example.com/live.M3U8")), .m3u8)
        XCTAssertEqual(IRVideoFormatResolver.format(for: NSURL(fileURLWithPath: "/tmp/clip.flv")), .flv)
    }

    func testDecoderTypeUsesConfiguredPolicyForResolvedFormat() {
        let decoder = IRPlayerDecoder.FFmpegDecoder()
        decoder.mpeg4Format = .avPlayer

        XCTAssertEqual(decoder.decoderTypeForContentURL(contentURL: NSURL(string: "https://example.com/video.mp4")), .avPlayer)
        XCTAssertEqual(decoder.decoderTypeForContentURL(contentURL: NSURL(string: "https://example.com/video.unknown")), .ffmpeg)
        XCTAssertEqual(decoder.decoderTypeForContentURL(contentURL: nil), .error)
    }
}

final class IRModelPayloadTests: XCTestCase {

    func testDefaultIRErrorUsesValidNSError() {
        let error = IRError()

        XCTAssertEqual(error.error.domain, "IRPlayer error")
        XCTAssertEqual(error.error.code, -1)
    }

    func testStatePayloadRoundTripsThroughModelParser() {
        let payload = IRPlayerNotificationPayload.state(previous: .buffering, current: .playing)
        let state = IRModel.state(fromUserInfo: payload)

        XCTAssertEqual(state.previous, .buffering)
        XCTAssertEqual(state.current, .playing)
    }

    func testStateParserAcceptsRawNumericPayloads() {
        let state = IRModel.state(fromUserInfo: [
            IRPlayerStatePreviousKey: NSNumber(value: IRPlayerState.readyToPlay.rawValue),
            IRPlayerStateCurrentKey: IRPlayerState.failed.rawValue
        ])

        XCTAssertEqual(state.previous, .readyToPlay)
        XCTAssertEqual(state.current, .failed)
    }

    func testProgressParserAcceptsNumericPayloadsAndDefaultsMissingValues() {
        let progress = IRModel.progress(fromUserInfo: [
            IRPlayerProgressPercentKey: NSNumber(value: 0.5),
            IRPlayerProgressCurrentKey: 3,
            IRPlayerProgressTotalKey: Double(6)
        ])

        XCTAssertEqual(progress.percent, 0.5, accuracy: 0.0001)
        XCTAssertEqual(progress.current, 3, accuracy: 0.0001)
        XCTAssertEqual(progress.total, 6, accuracy: 0.0001)

        let emptyProgress = IRModel.progress(fromUserInfo: [:])
        XCTAssertEqual(emptyProgress.percent, 0)
        XCTAssertEqual(emptyProgress.current, 0)
        XCTAssertEqual(emptyProgress.total, 0)
    }

    func testPlayablePayloadUsesZeroDefaultsForNilValues() {
        let payload = IRPlayerNotificationPayload.playable(percent: nil, current: NSNumber(value: 4), total: nil)
        let playable = IRModel.playable(fromUserInfo: payload)

        XCTAssertEqual(playable.percent, 0)
        XCTAssertEqual(playable.current, 4, accuracy: 0.0001)
        XCTAssertEqual(playable.total, 0)
    }

    func testProgressParserDefaultsNonFiniteNumericPayloads() {
        let progress = IRModel.progress(fromUserInfo: [
            IRPlayerProgressPercentKey: NSNumber(value: Double.nan),
            IRPlayerProgressCurrentKey: NSNumber(value: Double.infinity),
            IRPlayerProgressTotalKey: NSNumber(value: -Double.infinity)
        ])

        XCTAssertEqual(progress.percent, 0)
        XCTAssertEqual(progress.current, 0)
        XCTAssertEqual(progress.total, 0)
    }

    func testProgressPayloadDefaultsNonFiniteNumbers() {
        let payload = IRPlayerNotificationPayload.progress(
            percent: NSNumber(value: Double.nan),
            current: NSNumber(value: Double.infinity),
            total: NSNumber(value: -Double.infinity)
        )
        let progress = IRModel.progress(fromUserInfo: payload)

        XCTAssertEqual(progress.percent, 0)
        XCTAssertEqual(progress.current, 0)
        XCTAssertEqual(progress.total, 0)
    }

    func testErrorParserReturnsExistingIRErrorAndWrapsNSError() {
        let existingError = IRError()
        existingError.error = NSError(domain: "existing", code: 7)
        XCTAssertTrue(IRModel.error(fromUserInfo: IRPlayerNotificationPayload.error(existingError)) === existingError)

        let nsError = NSError(domain: "wrapped", code: 8)
        let wrappedError = IRModel.error(fromUserInfo: [IRPlayerErrorKey: nsError])
        XCTAssertEqual(wrappedError.error.domain, "wrapped")
        XCTAssertEqual(wrappedError.error.code, 8)
    }
}

final class IRPlayerNotificationTests: XCTestCase {

    func testPostNotificationPostsAsynchronouslyOnMainQueue() {
        let name = Notification.Name("IRPlayerNotificationTests.\(UUID().uuidString)")
        let expectation = expectation(description: "notification posted")
        let observer = NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { notification in
            XCTAssertTrue(Thread.isMainThread)
            XCTAssertEqual(notification.userInfo?[IRPlayerProgressCurrentKey] as? NSNumber, NSNumber(value: 2))
            expectation.fulfill()
        }

        IRPlayerNotification.postNotification(name: name.rawValue, object: nil, userInfo: [
            IRPlayerProgressCurrentKey: NSNumber(value: 2)
        ])

        wait(for: [expectation], timeout: 1.0)
        NotificationCenter.default.removeObserver(observer)
    }
}

final class IRFFFormatContextTests: XCTestCase {

    func testStreamLookupRejectsMissingContextStreamsAndOutOfRangeIndex() {
        XCTAssertNil(IRFFFormatContext.stream(at: 0, in: nil))

        var formatContext = AVFormatContext()
        formatContext.nb_streams = 1
        formatContext.streams = nil

        withUnsafeMutablePointer(to: &formatContext) { contextPointer in
            XCTAssertNil(IRFFFormatContext.stream(at: -1, in: contextPointer))
            XCTAssertNil(IRFFFormatContext.stream(at: 0, in: contextPointer))
            XCTAssertNil(IRFFFormatContext.stream(at: 1, in: contextPointer))
        }
    }

    func testStreamLookupReturnsExistingStream() {
        var formatContext = AVFormatContext()
        var stream = AVStream()

        withUnsafeMutablePointer(to: &stream) { streamPointer in
            var streams: [UnsafeMutablePointer<AVStream>?] = [streamPointer]

            streams.withUnsafeMutableBufferPointer { streamBuffer in
                formatContext.nb_streams = 1
                formatContext.streams = streamBuffer.baseAddress

                withUnsafeMutablePointer(to: &formatContext) { contextPointer in
                    XCTAssertEqual(IRFFFormatContext.stream(at: 0, in: contextPointer), streamPointer)
                }
            }
        }
    }

    func testDecoderLookupRejectsMissingAndInvalidCodecContext() {
        XCTAssertNil(IRFFFormatContext.decoder(for: nil))

        var codecContext = AVCodecContext()
        codecContext.codec_id = AV_CODEC_ID_NONE

        withUnsafeMutablePointer(to: &codecContext) { contextPointer in
            XCTAssertNil(IRFFFormatContext.decoder(for: contextPointer))
        }
    }

    func testInterruptCallbackIgnoresMissingContextAndUsesDelegateDecision() {
        XCTAssertEqual(ffmpeg_interrupt_callback(ctx: nil), 0)

        let context = IRFFFormatContext(contentURL: URL(fileURLWithPath: "/tmp/missing.mp4"), videoFormat: .mpeg4)
        let delegate = FormatContextInterruptDelegate(shouldInterrupt: true)
        context.delegate = delegate
        let refCon = UnsafeMutableRawPointer(Unmanaged.passUnretained(context).toOpaque())

        XCTAssertEqual(ffmpeg_interrupt_callback(ctx: refCon), 1)

        delegate.shouldInterrupt = false
        XCTAssertEqual(ffmpeg_interrupt_callback(ctx: refCon), 0)
    }
}

private final class FormatContextInterruptDelegate: IRFFFormatContextDelegate {
    var shouldInterrupt: Bool

    init(shouldInterrupt: Bool) {
        self.shouldInterrupt = shouldInterrupt
    }

    func formatContextNeedInterrupt(_ formatContext: IRFFFormatContext) -> Bool {
        shouldInterrupt
    }
}

final class IRAVPlayerTests: XCTestCase {

    func testTrackNameFallsBackWhenLanguageCodeIsMissingOrEmpty() {
        XCTAssertEqual(IRAVPlayer.trackName(languageCode: nil, trackID: 7), "Track 7")
        XCTAssertEqual(IRAVPlayer.trackName(languageCode: "", trackID: 8), "Track 8")
        XCTAssertEqual(IRAVPlayer.trackName(languageCode: "  ", trackID: 9), "Track 9")
        XCTAssertEqual(IRAVPlayer.trackName(languageCode: "en", trackID: 10), "en")
    }

    func testSetupAVPlayerItemIgnoresMissingAsset() {
        let abstractPlayer = IRPlayerImp.player()
        let avPlayer = IRAVPlayer(abstractPlayer: abstractPlayer)

        avPlayer.avAsset = nil
        avPlayer.setupAVPlayerItem(autoLoadedAsset: false)

        XCTAssertNil(avPlayer.avPlayerItem)
        withExtendedLifetime(abstractPlayer) {}
    }

    func testPlayIgnoresMissingPlayerInstance() {
        let abstractPlayer = IRPlayerImp.player()
        let avPlayer = IRAVPlayer(abstractPlayer: abstractPlayer)

        avPlayer.avPlayer = nil
        avPlayer.play()

        XCTAssertEqual(avPlayer.state, .none)
        withExtendedLifetime(abstractPlayer) {}
    }

    func testPauseIgnoresMissingPlayerInstance() {
        let abstractPlayer = IRPlayerImp.player()
        let avPlayer = IRAVPlayer(abstractPlayer: abstractPlayer)

        avPlayer.avPlayer = nil
        avPlayer.pause()

        XCTAssertEqual(avPlayer.state, .none)
        withExtendedLifetime(abstractPlayer) {}
    }

    func testSetPlayIfNeededIgnoresMissingPlayerInstance() {
        let abstractPlayer = IRPlayerImp.player()
        let avPlayer = IRAVPlayer(abstractPlayer: abstractPlayer)

        avPlayer.state = .playing
        avPlayer.avPlayer = nil
        avPlayer.setPlayIfNeeded()

        XCTAssertEqual(avPlayer.state, .playing)
        XCTAssertFalse(avPlayer.needPlay)
        withExtendedLifetime(abstractPlayer) {}
    }

    func testPlayIfNeededIgnoresMissingPlayerInstance() {
        let abstractPlayer = IRPlayerImp.player()
        let avPlayer = IRAVPlayer(abstractPlayer: abstractPlayer)

        avPlayer.state = .buffering
        avPlayer.needPlay = true
        avPlayer.avPlayer = nil
        avPlayer.playIfNeeded()

        XCTAssertEqual(avPlayer.state, .buffering)
        XCTAssertTrue(avPlayer.needPlay)
        withExtendedLifetime(abstractPlayer) {}
    }

    func testSeekIgnoresMissingPlayerItem() {
        let abstractPlayer = IRPlayerImp.player()
        let avPlayer = IRAVPlayer(abstractPlayer: abstractPlayer)
        var completionCalled = false

        avPlayer.avPlayerItem = nil
        avPlayer.seek(to: 1) { _ in
            completionCalled = true
        }

        XCTAssertFalse(avPlayer.seeking)
        XCTAssertFalse(completionCalled)
        withExtendedLifetime(abstractPlayer) {}
    }

    func testProgressReturnsZeroWhenPlayerItemIsMissing() {
        let abstractPlayer = IRPlayerImp.player()
        let avPlayer = IRAVPlayer(abstractPlayer: abstractPlayer)

        avPlayer.avPlayerItem = nil

        XCTAssertEqual(avPlayer.progress, 0)
        withExtendedLifetime(abstractPlayer) {}
    }

    func testDurationReturnsZeroWhenPlayerItemIsMissing() {
        let abstractPlayer = IRPlayerImp.player()
        let avPlayer = IRAVPlayer(abstractPlayer: abstractPlayer)

        avPlayer.avPlayerItem = nil

        XCTAssertEqual(avPlayer.duration, 0)
        withExtendedLifetime(abstractPlayer) {}
    }

    func testReloadVolumeIgnoresMissingPlayerInstance() {
        let abstractPlayer = IRPlayerImp.player()
        let avPlayer = IRAVPlayer(abstractPlayer: abstractPlayer)

        avPlayer.avPlayer = nil
        avPlayer.reloadVolume()

        XCTAssertNil(avPlayer.avPlayer)
        withExtendedLifetime(abstractPlayer) {}
    }

    func testPixelBufferAtCurrentTimeReturnsNilWhenPlayerItemIsMissing() {
        let abstractPlayer = IRPlayerImp.player()
        let avPlayer = IRAVPlayer(abstractPlayer: abstractPlayer)

        avPlayer.avPlayerItem = nil
        avPlayer.avOutput = AVPlayerItemVideoOutput(pixelBufferAttributes: [:])

        XCTAssertNil(avPlayer.pixelBufferAtCurrentTime())
        withExtendedLifetime(abstractPlayer) {}
    }

    func testSnapshotAtCurrentTimeReturnsNilWhenPlayerItemIsMissing() {
        let abstractPlayer = IRPlayerImp.player()
        let avPlayer = IRAVPlayer(abstractPlayer: abstractPlayer)

        avPlayer.avAsset = AVURLAsset(url: URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("missing.mp4"))
        avPlayer.avPlayerItem = nil

        XCTAssertNil(avPlayer.snapshotAtCurrentTime())
        withExtendedLifetime(abstractPlayer) {}
    }
}

final class IRFFPlayerTests: XCTestCase {

    func testFactoryCreatesPlayerWhenAudioManagerIsMissing() {
        let abstractPlayer = IRPlayerImp.player()
        abstractPlayer.manager = nil

        let ffPlayer = IRFFPlayer.player(with: abstractPlayer)

        XCTAssertNil(ffPlayer.audioManager)
        XCTAssertEqual(ffPlayer.duration, 0)
        withExtendedLifetime(abstractPlayer) {}
    }

    func testPlayableBufferIntervalReloadsFFmpegDecoderBufferDuration() throws {
        let player = IRPlayerImp.player()
        player.decoder = IRPlayerDecoder.FFmpegDecoder()
        player.manager = nil
        player.replaceVideoWithURL(contentURL: NSURL(fileURLWithPath: "/tmp/missing.flv"))

        let ffPlayer = try XCTUnwrap(mirroredFFPlayer(from: player))
        addTeardownBlock {
            ffPlayer.stop()
        }
        let decoder = try XCTUnwrap(ffPlayer.decoder)
        XCTAssertEqual(decoder.minBufferedDuration, 2)

        player.playableBufferInterval = 7

        XCTAssertEqual(decoder.minBufferedDuration, 7)
        withExtendedLifetime(player) {}
    }

    private func mirroredFFPlayer(from player: IRPlayerImp) -> IRFFPlayer? {
        let childValue = Mirror(reflecting: player)
            .children
            .first { $0.label == "_ffPlayer" }?
            .value
        guard let childValue = childValue else { return nil }

        let optionalMirror = Mirror(reflecting: childValue)
        if optionalMirror.displayStyle == .optional {
            return optionalMirror.children.first?.value as? IRFFPlayer
        }
        return childValue as? IRFFPlayer
    }
}

final class IRFFFrameQueueTests: XCTestCase {

    func testFrameQueueTracksCountDurationAndSizeWhenPuttingAndFetchingFrames() {
        let queue = IRFFFrameQueue.frameQueue()
        let first = makeFrame(position: 0, duration: 0.25, size: 10)
        let second = makeFrame(position: 1, duration: 0.5, size: 20)

        queue.putFrame(first)
        queue.putFrame(second)

        XCTAssertEqual(queue.count, 2)
        XCTAssertEqual(queue.duration, 0.75, accuracy: 0.0001)
        XCTAssertEqual(queue.size, 30)

        XCTAssertTrue(queue.getFrameAsync() === first)
        XCTAssertEqual(queue.count, 1)
        XCTAssertEqual(queue.duration, 0.5, accuracy: 0.0001)
        XCTAssertEqual(queue.size, 20)
    }

    func testPutSortFrameReturnsFramesInAscendingPositionOrder() {
        let queue = IRFFFrameQueue.frameQueue()
        let later = makeFrame(position: 3, duration: 0.1, size: 1)
        let earlier = makeFrame(position: 1, duration: 0.1, size: 1)
        let middle = makeFrame(position: 2, duration: 0.1, size: 1)

        queue.putSortFrame(later)
        queue.putSortFrame(earlier)
        queue.putSortFrame(middle)

        XCTAssertTrue(queue.getFrameAsync() === earlier)
        XCTAssertTrue(queue.getFrameAsync() === middle)
        XCTAssertTrue(queue.getFrameAsync() === later)
    }

    private func makeFrame(position: TimeInterval, duration: TimeInterval, size: Int) -> IRFFFrame {
        let frame = IRFFFrame()
        frame.position = position
        frame.duration = duration
        frame.size = size
        return frame
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
}

final class IRFFAudioDecoderTests: XCTestCase {

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

final class IRGLRenderModeFactoryTests: XCTestCase {

    func testNormalModesContainOnly2DModeWithParameter() {
        let parameter = IRMediaParameter(width: 100, height: 50)
        let modes = IRGLRenderModeFactory.createNormalModes(with: parameter)

        XCTAssertEqual(modes.count, 1)
        XCTAssertTrue(modes[0] is IRGLRenderMode2D)
        XCTAssertTrue(modes[0].parameter === parameter)
    }

    func testFisheyeModesHaveExpectedOrderNamesAndDefaults() {
        let modes = IRGLRenderModeFactory.createFisheyeModes(with: nil)

        XCTAssertEqual(modes.map(\.name), ["Panorama", "Onelen", "Fourlens", "Rawdata"])
        XCTAssertTrue(modes[0] is IRGLRenderMode2DFisheye2Pano)
        XCTAssertTrue(modes[1] is IRGLRenderMode3DFisheye)
        XCTAssertTrue(modes[2] is IRGLRenderModeMulti4P)
        XCTAssertTrue(modes[3] is IRGLRenderMode2D)
        XCTAssertEqual(modes[0].contentMode, .scaleAspectFill)
        XCTAssertEqual(modes[0].wideDegreeX, 360)
        XCTAssertEqual(modes[0].wideDegreeY, 20)
        XCTAssertFalse(modes[3].shiftController.enabled)
    }

    func testPanoramaModeUsesScaleAspectFillAndWideDegrees() {
        let mode = IRGLRenderModeFactory.createPanoramaMode(with: nil)

        XCTAssertTrue(mode is IRGLRenderMode2DFisheye2Pano)
        XCTAssertEqual(mode.contentMode, .scaleAspectFill)
        XCTAssertEqual(mode.wideDegreeX, 360)
        XCTAssertEqual(mode.wideDegreeY, 20)
    }

    func testFisheyeRenderModesIgnoreIncompatibleProgramParameters() {
        let invalidParameter = IRMediaParameter(width: 100, height: 50)

        let fisheyeMode = IRGLRenderMode3DFisheye()
        fisheyeMode.buildIRGLProgram(pixelFormat: .YUV_IRPixelFormat,
                                     viewprotRange: CGRect(x: 0, y: 0, width: 320, height: 240),
                                     parameter: invalidParameter)

        let fourPanelMode = IRGLRenderModeMulti4P()
        fourPanelMode.buildIRGLProgram(pixelFormat: .YUV_IRPixelFormat,
                                       viewprotRange: CGRect(x: 0, y: 0, width: 320, height: 240),
                                       parameter: invalidParameter)

        XCTAssertNil(fisheyeMode.program)
        XCTAssertNil(fourPanelMode.program)
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
}

final class IRGLViewSnapshotTests: XCTestCase {

    func testCreateImageFromFramebufferReturnsImageForZeroSizedView() {
        let view = IRGLView(frame: .zero)

        let image = view.createImageFromFramebuffer()

        XCTAssertEqual(image.size, .zero)
    }
}

final class IRMatrix4Tests: XCTestCase {

    func testTranslationMatrixStoresTranslationInLastColumn() {
        let matrix = IRMatrix4.makeTranslation(1, 2, 3)

        XCTAssertEqual(matrix.columns.3.x, 1, accuracy: 0.0001)
        XCTAssertEqual(matrix.columns.3.y, 2, accuracy: 0.0001)
        XCTAssertEqual(matrix.columns.3.z, 3, accuracy: 0.0001)
        XCTAssertEqual(matrix.columns.3.w, 1, accuracy: 0.0001)
    }

    func testScaleMatrixStoresScaleOnDiagonal() {
        let matrix = IRMatrix4.makeScale(2, 3, 4)

        XCTAssertEqual(matrix.columns.0.x, 2, accuracy: 0.0001)
        XCTAssertEqual(matrix.columns.1.y, 3, accuracy: 0.0001)
        XCTAssertEqual(matrix.columns.2.z, 4, accuracy: 0.0001)
        XCTAssertEqual(matrix.columns.3.w, 1, accuracy: 0.0001)
    }

    func testMultiplyReturnsSimdProduct() {
        let translation = IRMatrix4.makeTranslation(1, 2, 3)
        let scale = IRMatrix4.makeScale(2, 2, 2)

        XCTAssertEqual(IRMatrix4.multiply(translation, scale), simd_mul(translation, scale))
    }
}

final class IRAudioManagerNotificationTests: XCTestCase {

    func testMalformedAudioSessionNotificationsAreIgnored() {
        let manager = IRAudioManager()
        let target = NSObject()
        var interruptionCalled = false
        var routeChangeCalled = false
        manager.setHandlerTarget(target, interruption: { _, _, _, _ in
            interruptionCalled = true
        }, routeChange: { _, _, _ in
            routeChangeCalled = true
        })

        NotificationCenter.default.post(name: AVAudioSession.interruptionNotification, object: nil, userInfo: [:])
        NotificationCenter.default.post(name: AVAudioSession.routeChangeNotification, object: nil, userInfo: [:])

        XCTAssertFalse(interruptionCalled)
        XCTAssertFalse(routeChangeCalled)
    }
}

final class IRAudioManagerRenderTests: XCTestCase {

    func testRenderFramesIgnoresMissingAudioBufferList() {
        let manager = IRAudioManager()

        XCTAssertEqual(manager.renderFrames(16, ioData: nil), noErr)
    }
}
