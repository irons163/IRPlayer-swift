import AVFoundation
import CoreVideo
import Foundation
import IRFFMpeg
import XCTest
@testable import IRPlayer_swift

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

    func testDictionaryOptionApplicationRequiresNonNegativeResult() {
        XCTAssertTrue(IRFFFormatContext.dictionaryOptionWasApplied(0))
        XCTAssertTrue(IRFFFormatContext.dictionaryOptionWasApplied(1))
        XCTAssertFalse(IRFFFormatContext.dictionaryOptionWasApplied(-1))
    }

    func testSelectedSetupErrorRequiresBothTrackErrors() {
        let streamNotFound = NSError(
            domain: "video",
            code: Int(IRFFDecoderErrorCode.streamNotFound.rawValue)
        )
        let audioOpen = NSError(
            domain: "audio",
            code: Int(IRFFDecoderErrorCode.codecOpen2.rawValue)
        )

        XCTAssertNil(IRFFFormatContext.selectedSetupError(videoError: nil, audioError: audioOpen))
        XCTAssertNil(IRFFFormatContext.selectedSetupError(videoError: streamNotFound, audioError: nil))
    }

    func testSelectedSetupErrorPrefersAudioWhenVideoStreamIsMissing() throws {
        let streamNotFound = NSError(
            domain: "video",
            code: Int(IRFFDecoderErrorCode.streamNotFound.rawValue)
        )
        let audioOpen = NSError(
            domain: "audio",
            code: Int(IRFFDecoderErrorCode.codecOpen2.rawValue)
        )

        let selected = try XCTUnwrap(IRFFFormatContext.selectedSetupError(videoError: streamNotFound, audioError: audioOpen))

        XCTAssertEqual(selected, audioOpen)
    }

    func testSelectedSetupErrorDefaultsToVideoError() throws {
        let videoOpen = NSError(
            domain: "video",
            code: Int(IRFFDecoderErrorCode.codecOpen2.rawValue)
        )
        let audioOpen = NSError(
            domain: "audio",
            code: Int(IRFFDecoderErrorCode.codecOpen2.rawValue)
        )

        let selected = try XCTUnwrap(IRFFFormatContext.selectedSetupError(videoError: videoOpen, audioError: audioOpen))

        XCTAssertEqual(selected, videoOpen)
    }

    func testVideoAspectUsesFiniteRatioAndFallsBackForInvalidDimensions() {
        XCTAssertEqual(IRFFFormatContext.videoAspect(width: 1920, height: 1080), 16.0 / 9.0, accuracy: 0.0001)
        XCTAssertEqual(IRFFFormatContext.videoAspect(width: 0, height: 1080), 0)
        XCTAssertEqual(IRFFFormatContext.videoAspect(width: 1920, height: 0), 0)
        XCTAssertEqual(IRFFFormatContext.videoAspect(width: -1, height: 1080), 0)
    }

    func testVideoPresentationSizeRejectsInvalidDimensions() {
        XCTAssertEqual(IRFFFormatContext.presentationSize(width: 1920, height: 1080), CGSize(width: 1920, height: 1080))
        XCTAssertEqual(IRFFFormatContext.presentationSize(width: 0, height: 1080), .zero)
        XCTAssertEqual(IRFFFormatContext.presentationSize(width: 1920, height: 0), .zero)
        XCTAssertEqual(IRFFFormatContext.presentationSize(width: -1, height: 1080), .zero)
    }

    func testAudioTrackSelectionActionOnlySelectsDifferentAvailableTracks() {
        XCTAssertEqual(
            IRFFFormatContext.audioTrackSelectionAction(requestedIndex: 2, currentIndex: 1, containsRequestedTrack: true),
            .select
        )
        XCTAssertEqual(
            IRFFFormatContext.audioTrackSelectionAction(requestedIndex: 2, currentIndex: nil, containsRequestedTrack: true),
            .select
        )
        XCTAssertEqual(
            IRFFFormatContext.audioTrackSelectionAction(requestedIndex: 1, currentIndex: 1, containsRequestedTrack: true),
            .noChange
        )
        XCTAssertEqual(
            IRFFFormatContext.audioTrackSelectionAction(requestedIndex: 2, currentIndex: 1, containsRequestedTrack: false),
            .noChange
        )
    }

    func testAudioTrackSelectionActionRejectsNegativeRequestedIndex() {
        XCTAssertEqual(
            IRFFFormatContext.audioTrackSelectionAction(requestedIndex: -1, currentIndex: 0, containsRequestedTrack: true),
            .noChange
        )
    }

    func testSeekTimestampConvertsSecondsToFFmpegTimebase() {
        XCTAssertEqual(IRFFFormatContext.seekTimestamp(for: 1.5), 1_500_000)
        XCTAssertEqual(IRFFFormatContext.seekTimestamp(for: 0), 0)
    }

    func testSeekTimestampRejectsInvalidOrOverflowingTimes() {
        XCTAssertNil(IRFFFormatContext.seekTimestamp(for: -0.1))
        XCTAssertNil(IRFFFormatContext.seekTimestamp(for: .nan))
        XCTAssertNil(IRFFFormatContext.seekTimestamp(for: .infinity))
        XCTAssertNil(IRFFFormatContext.seekTimestamp(for: Double(Int64.max)))
    }

    func testSeekFileIgnoresMissingFormatContext() {
        let context = IRFFFormatContext(contentURL: URL(fileURLWithPath: "/tmp/missing.mp4"), videoFormat: .mpeg4)

        context.seekFile(withFFTimebase: 1)
    }

    func testReadFrameReturnsFailureWhenFormatContextIsMissing() {
        let context = IRFFFormatContext(contentURL: URL(fileURLWithPath: "/tmp/missing.mp4"), videoFormat: .mpeg4)
        var packet = AVPacket()

        XCTAssertLessThan(context.readFrame(&packet), 0)
    }

    func testDerivedFormatValuesUseDefaultsBeforeStreamIsOpened() {
        let context = IRFFFormatContext(contentURL: URL(fileURLWithPath: "/tmp/missing.mp4"), videoFormat: .mpeg4)

        XCTAssertEqual(context.bitrate, 0)
        XCTAssertEqual(context.duration, 0)
    }

    func testSetupSyncOpensGeneratedVideoFileAndInitializesVideoTrack() throws {
        let url = try makeTinyVideoFile()
        addTeardownBlock {
            try? FileManager.default.removeItem(at: url)
        }
        let context = IRFFFormatContext(contentURL: url, videoFormat: .mpeg4)
        addTeardownBlock {
            context.destroy()
        }

        context.setupSync()

        XCTAssertNil(context.error)
        XCTAssertEqual(context.diagnostics.phase, .active)
        XCTAssertTrue(context.diagnostics.hasGeneration)
        XCTAssertTrue(context.diagnostics.hasFormatContext)
        XCTAssertTrue(context.diagnostics.hasVideoCodecContext)
        XCTAssertTrue(context.videoEnable)
        XCTAssertFalse(context.audioEnable)
        XCTAssertEqual(context.videoTrack?.type, .video)
        XCTAssertEqual(context.videoTracks.map(\.type), [.video])
        XCTAssertTrue(context.audioTracks.isEmpty)
        XCTAssertNotNil(context.videoCodecContext)
        XCTAssertNil(context.audioCodecContext)
        XCTAssertEqual(context.videoPresentationSize, CGSize(width: 16, height: 16))
        XCTAssertEqual(context.videoAspect, 1, accuracy: 0.0001)
        XCTAssertGreaterThan(context.videoTimebase, 0)
        XCTAssertGreaterThan(context.videoFPS, 0)
        XCTAssertGreaterThanOrEqual(context.duration, 0)

        var packet = AVPacket()
        XCTAssertGreaterThanOrEqual(context.readFrame(&packet), 0)
        IRFFFormatContext.releasePacket(&packet)

        context.seekFile(withFFTimebase: 0)

        let originalCodecContext = context.videoCodecContext
        context.setupSync()
        XCTAssertEqual(context.videoCodecContext, originalCodecContext)
        XCTAssertEqual(context.diagnostics.phase, .active)
    }

    func testContentURLStringUsesFilePathOrAbsoluteURL() {
        let fileContext = IRFFFormatContext(
            contentURL: URL(fileURLWithPath: "/tmp/sample movie.mp4"),
            videoFormat: .mpeg4
        )
        let remoteContext = IRFFFormatContext(
            contentURL: URL(string: "https://example.com/video.m3u8?token=abc")!,
            videoFormat: .mpeg4
        )

        XCTAssertEqual(fileContext.contentURLString, "/tmp/sample movie.mp4")
        XCTAssertEqual(remoteContext.contentURLString, "https://example.com/video.m3u8?token=abc")
    }

    func testSelectingMissingAudioTrackLeavesContextUnchanged() {
        let context = IRFFFormatContext(contentURL: URL(fileURLWithPath: "/tmp/missing.mp4"), videoFormat: .mpeg4)

        let result = context.selectAudioTrackIndexResult(0)

        XCTAssertNil(result.error)
        XCTAssertFalse(result.didChangeTrack)
        XCTAssertFalse(context.containAudioTrack(0))
        XCTAssertNil(context.selectAudioTrackIndex(0))
    }

    func testDurationSecondsPreservesNoPTSBehavior() {
        XCTAssertEqual(IRFFFormatContext.durationSeconds(from: Int64.min), TimeInterval(MAXFLOAT))
    }

    func testDurationSecondsUsesFractionalFFmpegTimebase() {
        XCTAssertEqual(IRFFFormatContext.durationSeconds(from: 1_500_000), 1.5, accuracy: 0.0001)
    }

    func testDurationSecondsRejectsNegativeDurations() {
        XCTAssertEqual(IRFFFormatContext.durationSeconds(from: -1), 0)
    }

    func testBitrateKbpsConvertsPositiveValues() {
        XCTAssertEqual(IRFFFormatContext.bitrateKbps(from: 1_500), 1.5, accuracy: 0.0001)
    }

    func testBitrateKbpsRejectsNegativeValues() {
        XCTAssertEqual(IRFFFormatContext.bitrateKbps(from: -1), 0)
    }

    func testInterruptCallbackIgnoresMissingContextAndUsesDelegateDecision() {
        XCTAssertEqual(ffmpeg_interrupt_callback(ctx: nil), 0)

        let context = IRFFFormatContext(contentURL: URL(fileURLWithPath: "/tmp/missing.mp4"), videoFormat: .mpeg4)
        let delegate = FormatContextInterruptDelegate(shouldInterrupt: true)
        let interruptState = IRFFFormatContextInterruptState()
        interruptState.bind(context: context)
        interruptState.setDelegate(delegate)
        let refCon = interruptState.makeRetainedCallbackReference()
        defer {
            IRFFFormatContextInterruptState
                .releaseRetainedCallbackReference(refCon)
        }

        XCTAssertEqual(ffmpeg_interrupt_callback(ctx: refCon), 1)

        delegate.shouldInterrupt = false
        XCTAssertEqual(ffmpeg_interrupt_callback(ctx: refCon), 0)
    }

    func testFailedSetupPublishesNoPartialGenerationAndIsNotRetried() {
        let context = IRFFFormatContext(
            contentURL: URL(
                fileURLWithPath:
                    "/tmp/irplayer-definitely-missing-\(UUID()).mp4"
            ),
            videoFormat: .mpeg4
        )

        context.setupSync()

        XCTAssertNotNil(context.error)
        XCTAssertEqual(context.diagnostics.phase, .failed)
        XCTAssertFalse(context.diagnostics.hasGeneration)
        XCTAssertFalse(context.diagnostics.hasFormatContext)
        XCTAssertNil(context.videoCodecContext)
        XCTAssertNil(context.audioCodecContext)

        let originalError = context.error
        context.setupSync()
        XCTAssertEqual(context.error, originalError)
        XCTAssertEqual(context.diagnostics.phase, .failed)
    }

    func testDestroyIsIdempotentTerminalAndClearsPublishedGeneration()
        throws
    {
        let url = try makeTinyVideoFile()
        addTeardownBlock {
            try? FileManager.default.removeItem(at: url)
        }
        let context = IRFFFormatContext(
            contentURL: url,
            videoFormat: .mpeg4
        )
        context.setupSync()
        XCTAssertEqual(context.diagnostics.phase, .active)

        context.destroy()
        context.destroy()
        context.setupSync()

        XCTAssertEqual(context.diagnostics.phase, .closed)
        XCTAssertFalse(context.diagnostics.hasGeneration)
        XCTAssertFalse(context.diagnostics.hasFormatContext)
        XCTAssertTrue(context.diagnostics.interruptCloseRequested)
        XCTAssertFalse(context.videoEnable)
        XCTAssertFalse(context.audioEnable)
        XCTAssertNil(context.videoCodecContext)
        XCTAssertNil(context.audioCodecContext)
        XCTAssertEqual(context.duration, 0)
        XCTAssertEqual(context.bitrate, 0)
        var packet = AVPacket()
        XCTAssertLessThan(context.readFrame(&packet), 0)
    }

    func testConcurrentReadGettersSeekAndDestroyRemainSafe() throws {
        let url = try makeTinyVideoFile()
        addTeardownBlock {
            try? FileManager.default.removeItem(at: url)
        }
        let context = IRFFFormatContext(
            contentURL: url,
            videoFormat: .mpeg4
        )
        context.setupSync()
        try XCTSkipIf(
            context.error != nil,
            "Generated fixture could not be opened."
        )

        DispatchQueue.concurrentPerform(iterations: 500) { index in
            switch index % 6 {
            case 0:
                var packet = AVPacket()
                _ = context.readFrame(&packet)
                IRFFFormatContext.releasePacket(&packet)
            case 1:
                _ = context.duration
            case 2:
                _ = context.videoTracks
            case 3:
                context.seekFile(withFFTimebase: 0)
            case 4:
                _ = context.diagnostics
            default:
                context.destroy()
            }
        }

        XCTAssertEqual(context.diagnostics.phase, .closed)
        XCTAssertFalse(context.diagnostics.hasGeneration)
    }

    func testReleaseDoesNotPrintDebugOutput() {
        var context: IRFFFormatContext? = IRFFFormatContext(
            contentURL: URL(fileURLWithPath: "/tmp/missing.mp4"),
            videoFormat: .mpeg4
        )
        XCTAssertNotNil(context)

        let output = captureStandardOutput {
            context = nil
        }

        XCTAssertEqual(output, "")
    }
}

func makeTinyVideoFile() throws -> URL {
    let url = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("irff-format-context-\(UUID().uuidString).mp4")
    try? FileManager.default.removeItem(at: url)

    let writer: AVAssetWriter
    do {
        writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
    } catch {
        throw XCTSkip("AVAssetWriter unavailable: \(error)")
    }

    let input = AVAssetWriterInput(
        mediaType: .video,
        outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: 16,
            AVVideoHeightKey: 16
        ]
    )
    input.expectsMediaDataInRealTime = false

    let adaptor = AVAssetWriterInputPixelBufferAdaptor(
        assetWriterInput: input,
        sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: 16,
            kCVPixelBufferHeightKey as String: 16
        ]
    )

    guard writer.canAdd(input) else {
        throw XCTSkip("Cannot add video input to AVAssetWriter.")
    }
    writer.add(input)

    guard writer.startWriting() else {
        throw writer.error ?? NSError(domain: "IRFFFormatContextTests", code: 1)
    }
    writer.startSession(atSourceTime: .zero)

    guard let pool = adaptor.pixelBufferPool else {
        throw XCTSkip("AVAssetWriter did not provide a pixel buffer pool.")
    }

    for frameIndex in 0..<2 {
        guard input.isReadyForMoreMediaData else {
            throw XCTSkip("AVAssetWriter input was not ready for pixel buffers.")
        }

        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferPoolCreatePixelBuffer(nil, pool, &pixelBuffer)
        guard status == kCVReturnSuccess, let pixelBuffer else {
            throw XCTSkip("Could not create pixel buffer: \(status).")
        }

        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        if let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) {
            memset(baseAddress, 0, CVPixelBufferGetBytesPerRow(pixelBuffer) * CVPixelBufferGetHeight(pixelBuffer))
        }
        CVPixelBufferUnlockBaseAddress(pixelBuffer, [])

        let presentationTime = CMTime(value: CMTimeValue(frameIndex), timescale: 30)
        guard adaptor.append(pixelBuffer, withPresentationTime: presentationTime) else {
            throw writer.error ?? NSError(domain: "IRFFFormatContextTests", code: 2)
        }
    }

    input.markAsFinished()

    let semaphore = DispatchSemaphore(value: 0)
    writer.finishWriting {
        semaphore.signal()
    }
    guard semaphore.wait(timeout: .now() + 5) == .success else {
        throw XCTSkip("Timed out while writing tiny video fixture.")
    }
    guard writer.status == .completed else {
        throw writer.error ?? NSError(domain: "IRFFFormatContextTests", code: 3)
    }

    return url
}
