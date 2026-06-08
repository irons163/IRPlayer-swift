import XCTest
@testable import IRPlayer_swift

final class IRFFDecoderDisplayPolicyTests: XCTestCase {

    func testAudioSyncedVideoSleepDurationWaitsForAudioClockAndAppliesMinimum() {
        XCTAssertEqual(
            IRFFDecoderDisplayPolicy.audioSyncedVideoSleepDuration(
                framePosition: 10,
                frameDuration: 0.04,
                audioTimeClock: 9,
                fps: 25
            ),
            0.02
        )
        XCTAssertEqual(
            IRFFDecoderDisplayPolicy.audioSyncedVideoSleepDuration(
                framePosition: 10,
                frameDuration: 0.02,
                audioTimeClock: 10.01,
                fps: 25
            ),
            0.015
        )
        XCTAssertNil(
            IRFFDecoderDisplayPolicy.audioSyncedVideoSleepDuration(
                framePosition: 10,
                frameDuration: 0.04,
                audioTimeClock: 11,
                fps: 25
            )
        )
    }

    func testStandaloneVideoSleepDurationUsesFrameDurationOrFPSFallback() {
        XCTAssertEqual(IRFFDecoderDisplayPolicy.standaloneVideoSleepDuration(frameDuration: 0.04, fps: 25), 0.04)
        XCTAssertEqual(IRFFDecoderDisplayPolicy.standaloneVideoSleepDuration(frameDuration: 0, fps: 25), 0.04)
    }

    func testVideoSleepDurationRejectsInvalidTimingFallbacks() {
        XCTAssertNil(
            IRFFDecoderDisplayPolicy.audioSyncedVideoSleepDuration(
                framePosition: 10,
                frameDuration: 0.04,
                audioTimeClock: 9,
                fps: 0
            )
        )
        XCTAssertNil(IRFFDecoderDisplayPolicy.standaloneVideoSleepDuration(frameDuration: 0, fps: 0))
        XCTAssertEqual(IRFFDecoderDisplayPolicy.standaloneVideoSleepDuration(frameDuration: .nan, fps: 25), 0.04)
        XCTAssertEqual(IRFFDecoderDisplayPolicy.standaloneVideoSleepDuration(frameDuration: .infinity, fps: 25), 0.04)
        XCTAssertEqual(IRFFDecoderDisplayPolicy.standaloneVideoSleepDuration(frameDuration: 0.04, fps: 0), 0.04)
    }

    func testShouldAcceptVideoFramePreservesForwardProgressOrdering() {
        XCTAssertTrue(IRFFDecoderDisplayPolicy.shouldAcceptVideoFrame(currentPosition: nil, nextPosition: nil))
        XCTAssertTrue(IRFFDecoderDisplayPolicy.shouldAcceptVideoFrame(currentPosition: nil, nextPosition: 0.5))
        XCTAssertTrue(IRFFDecoderDisplayPolicy.shouldAcceptVideoFrame(currentPosition: 1.0, nextPosition: 1.0))
        XCTAssertTrue(IRFFDecoderDisplayPolicy.shouldAcceptVideoFrame(currentPosition: 1.0, nextPosition: 1.5))
        XCTAssertFalse(IRFFDecoderDisplayPolicy.shouldAcceptVideoFrame(currentPosition: 1.0, nextPosition: 0.5))
    }

    func testShouldAcceptVideoFrameRecoversFromMalformedCurrentPosition() {
        XCTAssertTrue(IRFFDecoderDisplayPolicy.shouldAcceptVideoFrame(currentPosition: .nan, nextPosition: 1.0))
        XCTAssertTrue(IRFFDecoderDisplayPolicy.shouldAcceptVideoFrame(currentPosition: .infinity, nextPosition: 1.0))
        XCTAssertFalse(IRFFDecoderDisplayPolicy.shouldAcceptVideoFrame(currentPosition: 1.0, nextPosition: .nan))
        XCTAssertFalse(IRFFDecoderDisplayPolicy.shouldAcceptVideoFrame(currentPosition: 1.0, nextPosition: .infinity))
    }

    func testDisplayIdleSleepIntervalPrioritizesSeekingBufferingAndPausedReplay() {
        XCTAssertEqual(
            IRFFDecoderDisplayPolicy.displayIdleSleepInterval(
                seeking: true,
                buffering: false,
                paused: true,
                hasCurrentFrame: true
            ),
            0.01
        )
        XCTAssertEqual(
            IRFFDecoderDisplayPolicy.displayIdleSleepInterval(
                seeking: false,
                buffering: true,
                paused: false,
                hasCurrentFrame: false
            ),
            0.01
        )
        XCTAssertEqual(
            IRFFDecoderDisplayPolicy.displayIdleSleepInterval(
                seeking: false,
                buffering: false,
                paused: true,
                hasCurrentFrame: true
            ),
            0.03
        )
        XCTAssertNil(
            IRFFDecoderDisplayPolicy.displayIdleSleepInterval(
                seeking: false,
                buffering: false,
                paused: true,
                hasCurrentFrame: false
            )
        )
        XCTAssertNil(
            IRFFDecoderDisplayPolicy.displayIdleSleepInterval(
                seeking: false,
                buffering: false,
                paused: false,
                hasCurrentFrame: true
            )
        )
    }

    func testShouldFinishDisplayRequiresEndOfFileAndEmptyVideoQueue() {
        XCTAssertFalse(IRFFDecoderDisplayPolicy.shouldFinishDisplay(endOfFile: false, videoDecoderEmpty: true))
        XCTAssertFalse(IRFFDecoderDisplayPolicy.shouldFinishDisplay(endOfFile: true, videoDecoderEmpty: false))
        XCTAssertTrue(IRFFDecoderDisplayPolicy.shouldFinishDisplay(endOfFile: true, videoDecoderEmpty: true))
    }
}
