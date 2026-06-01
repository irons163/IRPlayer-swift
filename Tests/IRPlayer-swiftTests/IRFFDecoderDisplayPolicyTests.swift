import XCTest
@testable import IRPlayer_swift

final class IRFFDecoderDisplayPolicyTests: XCTestCase {

    func testAudioSyncedVideoSleepDurationWaitsForAudioClockAndAppliesMinimum() {
        XCTAssertEqual(
            IRFFDecoder.audioSyncedVideoSleepDuration(
                framePosition: 10,
                frameDuration: 0.04,
                audioTimeClock: 9,
                fps: 25
            ),
            0.02
        )
        XCTAssertEqual(
            IRFFDecoder.audioSyncedVideoSleepDuration(
                framePosition: 10,
                frameDuration: 0.02,
                audioTimeClock: 10.01,
                fps: 25
            ),
            0.015
        )
        XCTAssertNil(
            IRFFDecoder.audioSyncedVideoSleepDuration(
                framePosition: 10,
                frameDuration: 0.04,
                audioTimeClock: 11,
                fps: 25
            )
        )
    }

    func testStandaloneVideoSleepDurationUsesFrameDurationOrFPSFallback() {
        XCTAssertEqual(IRFFDecoder.standaloneVideoSleepDuration(frameDuration: 0.04, fps: 25), 0.04)
        XCTAssertEqual(IRFFDecoder.standaloneVideoSleepDuration(frameDuration: 0, fps: 25), 0.04)
    }

    func testVideoSleepDurationRejectsInvalidTimingFallbacks() {
        XCTAssertNil(
            IRFFDecoder.audioSyncedVideoSleepDuration(
                framePosition: 10,
                frameDuration: 0.04,
                audioTimeClock: 9,
                fps: 0
            )
        )
        XCTAssertNil(IRFFDecoder.standaloneVideoSleepDuration(frameDuration: 0, fps: 0))
        XCTAssertEqual(IRFFDecoder.standaloneVideoSleepDuration(frameDuration: .nan, fps: 25), 0.04)
        XCTAssertEqual(IRFFDecoder.standaloneVideoSleepDuration(frameDuration: .infinity, fps: 25), 0.04)
        XCTAssertEqual(IRFFDecoder.standaloneVideoSleepDuration(frameDuration: 0.04, fps: 0), 0.04)
    }

    func testShouldAcceptVideoFramePreservesForwardProgressOrdering() {
        XCTAssertTrue(IRFFDecoder.shouldAcceptVideoFrame(currentPosition: nil, nextPosition: nil))
        XCTAssertTrue(IRFFDecoder.shouldAcceptVideoFrame(currentPosition: nil, nextPosition: 0.5))
        XCTAssertTrue(IRFFDecoder.shouldAcceptVideoFrame(currentPosition: 1.0, nextPosition: 1.0))
        XCTAssertTrue(IRFFDecoder.shouldAcceptVideoFrame(currentPosition: 1.0, nextPosition: 1.5))
        XCTAssertFalse(IRFFDecoder.shouldAcceptVideoFrame(currentPosition: 1.0, nextPosition: 0.5))
    }

    func testShouldAcceptVideoFrameRecoversFromMalformedCurrentPosition() {
        XCTAssertTrue(IRFFDecoder.shouldAcceptVideoFrame(currentPosition: .nan, nextPosition: 1.0))
        XCTAssertTrue(IRFFDecoder.shouldAcceptVideoFrame(currentPosition: .infinity, nextPosition: 1.0))
        XCTAssertFalse(IRFFDecoder.shouldAcceptVideoFrame(currentPosition: 1.0, nextPosition: .nan))
        XCTAssertFalse(IRFFDecoder.shouldAcceptVideoFrame(currentPosition: 1.0, nextPosition: .infinity))
    }

    func testDisplayIdleSleepIntervalPrioritizesSeekingBufferingAndPausedReplay() {
        XCTAssertEqual(
            IRFFDecoder.displayIdleSleepInterval(
                seeking: true,
                buffering: false,
                paused: true,
                hasCurrentFrame: true
            ),
            0.01
        )
        XCTAssertEqual(
            IRFFDecoder.displayIdleSleepInterval(
                seeking: false,
                buffering: true,
                paused: false,
                hasCurrentFrame: false
            ),
            0.01
        )
        XCTAssertEqual(
            IRFFDecoder.displayIdleSleepInterval(
                seeking: false,
                buffering: false,
                paused: true,
                hasCurrentFrame: true
            ),
            0.03
        )
        XCTAssertNil(
            IRFFDecoder.displayIdleSleepInterval(
                seeking: false,
                buffering: false,
                paused: true,
                hasCurrentFrame: false
            )
        )
        XCTAssertNil(
            IRFFDecoder.displayIdleSleepInterval(
                seeking: false,
                buffering: false,
                paused: false,
                hasCurrentFrame: true
            )
        )
    }

    func testShouldFinishDisplayRequiresEndOfFileAndEmptyVideoQueue() {
        XCTAssertFalse(IRFFDecoder.shouldFinishDisplay(endOfFile: false, videoDecoderEmpty: true))
        XCTAssertFalse(IRFFDecoder.shouldFinishDisplay(endOfFile: true, videoDecoderEmpty: false))
        XCTAssertTrue(IRFFDecoder.shouldFinishDisplay(endOfFile: true, videoDecoderEmpty: true))
    }
}
