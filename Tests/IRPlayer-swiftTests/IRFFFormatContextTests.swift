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
        context.delegate = delegate
        let refCon = IRFFFormatContext.interruptOpaquePointer(for: context)

        XCTAssertEqual(ffmpeg_interrupt_callback(ctx: refCon), 1)

        delegate.shouldInterrupt = false
        XCTAssertEqual(ffmpeg_interrupt_callback(ctx: refCon), 0)
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
