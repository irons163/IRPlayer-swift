import IRFFMpeg
import XCTest
@testable import IRPlayer_swift

final class IRFFVideoDecoderTests: XCTestCase {

    func testStaticPolicyWrappersRemainSourceCompatible() {
        XCTAssertEqual(
            IRFFVideoDecoder.frameDuration(ticks: 4, repeatPicture: 2, timebase: 0.25, fps: 30),
            IRFFVideoDecoderPolicy.frameDuration(ticks: 4, repeatPicture: 2, timebase: 0.25, fps: 30)
        )
        XCTAssertEqual(
            IRFFVideoDecoder.decodeBackpressureSleepInterval(frameDuration: 2.0, maxDecodeDuration: 2.0, paused: true),
            IRFFVideoDecoderPolicy.decodeBackpressureSleepInterval(frameDuration: 2.0, maxDecodeDuration: 2.0, paused: true)
        )
        XCTAssertEqual(
            IRFFVideoDecoder.packetDecodeResultIsFailure(-1),
            IRFFVideoDecoderPolicy.packetDecodeResultIsFailure(-1)
        )
        XCTAssertEqual(
            IRFFVideoDecoder.shouldFinishDecode(endOfFile: true, packetEmpty: true),
            IRFFVideoDecoderPolicy.shouldFinishDecode(endOfFile: true, packetEmpty: true)
        )
        XCTAssertEqual(
            IRFFVideoDecoder.decodeIdleSleepInterval(paused: true),
            IRFFVideoDecoderPolicy.decodeIdleSleepInterval(paused: true)
        )
        XCTAssertEqual(
            IRFFVideoDecoder.shouldCreateYUVFrame(hasFrame: true, hasLuma: true, hasChromaB: true, hasChromaR: true),
            IRFFVideoDecoderPolicy.shouldCreateYUVFrame(hasFrame: true, hasLuma: true, hasChromaB: true, hasChromaR: true)
        )
    }

    func testFrameDurationUsesTicksAndRepeatPictureWhenAvailable() {
        let duration = IRFFVideoDecoder.frameDuration(ticks: 4, repeatPicture: 2, timebase: 0.25, fps: 30)

        XCTAssertEqual(duration, 1.25, accuracy: 0.0001)
    }

    func testFrameDurationUsesFPSFallbackWhenTicksAreMissing() {
        let duration = IRFFVideoDecoder.frameDuration(ticks: 0, repeatPicture: 0, timebase: 0.25, fps: 25)

        XCTAssertEqual(duration, 0.04, accuracy: 0.0001)
    }

    func testFrameDurationRejectsInvalidTimingInputs() {
        XCTAssertEqual(IRFFVideoDecoder.frameDuration(ticks: 4, repeatPicture: 0, timebase: .infinity, fps: 30), 0)
        XCTAssertEqual(IRFFVideoDecoder.frameDuration(ticks: 4, repeatPicture: 0, timebase: -1, fps: 30), 0)
        XCTAssertEqual(IRFFVideoDecoder.frameDuration(ticks: 0, repeatPicture: 0, timebase: 0.25, fps: 0), 0)
        XCTAssertEqual(IRFFVideoDecoder.frameDuration(ticks: 0, repeatPicture: 0, timebase: 0.25, fps: .nan), 0)
    }

    func testDecodeBackpressureSleepIntervalUsesConfiguredThresholdAndPauseState() {
        XCTAssertNil(
            IRFFVideoDecoder.decodeBackpressureSleepInterval(
                frameDuration: 1.99,
                maxDecodeDuration: 2.0,
                paused: false
            )
        )
        XCTAssertEqual(
            IRFFVideoDecoder.decodeBackpressureSleepInterval(
                frameDuration: 2.0,
                maxDecodeDuration: 2.0,
                paused: false
            ),
            0.1
        )
        XCTAssertEqual(
            IRFFVideoDecoder.decodeBackpressureSleepInterval(
                frameDuration: 3.0,
                maxDecodeDuration: 2.0,
                paused: true
            ),
            0.5
        )
    }

    func testDecodeBackpressureSleepIntervalRejectsInvalidTimingInputs() {
        XCTAssertNil(
            IRFFVideoDecoder.decodeBackpressureSleepInterval(
                frameDuration: .nan,
                maxDecodeDuration: 2.0,
                paused: false
            )
        )
        XCTAssertNil(
            IRFFVideoDecoder.decodeBackpressureSleepInterval(
                frameDuration: 2.0,
                maxDecodeDuration: 0,
                paused: false
            )
        )
        XCTAssertNil(
            IRFFVideoDecoder.decodeBackpressureSleepInterval(
                frameDuration: 2.0,
                maxDecodeDuration: -1,
                paused: false
            )
        )
        XCTAssertNil(
            IRFFVideoDecoder.decodeBackpressureSleepInterval(
                frameDuration: 2.0,
                maxDecodeDuration: .infinity,
                paused: false
            )
        )
    }

    func testPacketDecodeResultPolicyTreatsRecoverableFFmpegResultsAsNonFailures() {
        XCTAssertFalse(IRFFVideoDecoder.packetDecodeResultIsFailure(0))
        XCTAssertFalse(IRFFVideoDecoder.packetDecodeResultIsFailure(AVERROR(EAGAIN)))
        XCTAssertTrue(IRFFVideoDecoder.packetDecodeResultIsFailure(-1))
    }

    func testShouldFinishDecodeRequiresEndOfFileAndEmptyPacketQueue() {
        XCTAssertFalse(IRFFVideoDecoder.shouldFinishDecode(endOfFile: false, packetEmpty: true))
        XCTAssertFalse(IRFFVideoDecoder.shouldFinishDecode(endOfFile: true, packetEmpty: false))
        XCTAssertTrue(IRFFVideoDecoder.shouldFinishDecode(endOfFile: true, packetEmpty: true))
    }

    func testDecodeIdleSleepIntervalOnlyAppliesWhenPaused() {
        XCTAssertEqual(IRFFVideoDecoder.decodeIdleSleepInterval(paused: true), 0.01)
        XCTAssertNil(IRFFVideoDecoder.decodeIdleSleepInterval(paused: false))
    }

    func testShouldCreateYUVFrameRequiresFrameAndAllPlanes() {
        XCTAssertFalse(
            IRFFVideoDecoder.shouldCreateYUVFrame(
                hasFrame: false,
                hasLuma: true,
                hasChromaB: true,
                hasChromaR: true
            )
        )
        XCTAssertFalse(
            IRFFVideoDecoder.shouldCreateYUVFrame(
                hasFrame: true,
                hasLuma: false,
                hasChromaB: true,
                hasChromaR: true
            )
        )
        XCTAssertFalse(
            IRFFVideoDecoder.shouldCreateYUVFrame(
                hasFrame: true,
                hasLuma: true,
                hasChromaB: false,
                hasChromaR: true
            )
        )
        XCTAssertFalse(
            IRFFVideoDecoder.shouldCreateYUVFrame(
                hasFrame: true,
                hasLuma: true,
                hasChromaB: true,
                hasChromaR: false
            )
        )
        XCTAssertTrue(
            IRFFVideoDecoder.shouldCreateYUVFrame(
                hasFrame: true,
                hasLuma: true,
                hasChromaB: true,
                hasChromaR: true
            )
        )
    }

    func testReleaseDoesNotPrintDebugOutput() {
        var codecContext = AVCodecContext()

        let output = withUnsafeMutablePointer(to: &codecContext) { codecContextPointer in
            var decoder: IRFFVideoDecoder? = IRFFVideoDecoder(
                codecContext: codecContextPointer,
                timebase: 0.25,
                fps: 30,
                delegate: nil
            )
            XCTAssertNotNil(decoder)

            return captureStandardOutput {
                decoder = nil
            }
        }

        XCTAssertEqual(output, "")
    }
}
