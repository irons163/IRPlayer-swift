import XCTest
#if SWIFT_PACKAGE
@testable import IRPlayerSwift
#else
@testable import IRPlayer_swift
#endif

final class IRFFDecoderDisplayLoopStateTests: XCTestCase {

    func testExitActionQuitsForClosedOrErroredDecoder() {
        XCTAssertEqual(
            IRFFDecoderDisplayLoopState.exitAction(closed: true, hasError: false),
            .quit
        )
        XCTAssertEqual(
            IRFFDecoderDisplayLoopState.exitAction(closed: false, hasError: true),
            .quit
        )
        XCTAssertNil(IRFFDecoderDisplayLoopState.exitAction(closed: false, hasError: false))
    }

    func testIdleActionPreservesSeekingBufferingAndPausedReplay() {
        XCTAssertEqual(
            IRFFDecoderDisplayLoopState.idleAction(
                seeking: true,
                buffering: false,
                paused: true,
                hasCurrentFrame: true
            ),
            .idleSleep(interval: 0.01, replayCurrentFrame: false)
        )
        XCTAssertEqual(
            IRFFDecoderDisplayLoopState.idleAction(
                seeking: false,
                buffering: true,
                paused: false,
                hasCurrentFrame: false
            ),
            .idleSleep(interval: 0.01, replayCurrentFrame: false)
        )
        XCTAssertEqual(
            IRFFDecoderDisplayLoopState.idleAction(
                seeking: false,
                buffering: false,
                paused: true,
                hasCurrentFrame: true
            ),
            .idleSleep(interval: 0.03, replayCurrentFrame: true)
        )
        XCTAssertNil(
            IRFFDecoderDisplayLoopState.idleAction(
                seeking: false,
                buffering: false,
                paused: false,
                hasCurrentFrame: true
            )
        )
    }

    func testFinishActionRequiresEndOfFileAndEmptyVideoQueue() {
        XCTAssertNil(IRFFDecoderDisplayLoopState.finishAction(endOfFile: false, videoDecoderEmpty: true))
        XCTAssertNil(IRFFDecoderDisplayLoopState.finishAction(endOfFile: true, videoDecoderEmpty: false))
        XCTAssertEqual(
            IRFFDecoderDisplayLoopState.finishAction(endOfFile: true, videoDecoderEmpty: true),
            .finish
        )
    }

    func testAudioSyncActionWaitsForAudioClock() {
        XCTAssertNil(
            IRFFDecoderDisplayLoopState.audioSyncAction(
                currentFramePosition: nil,
                currentFrameDuration: nil,
                audioTimeClock: 9,
                fps: 25
            )
        )
        XCTAssertEqual(
            IRFFDecoderDisplayLoopState.audioSyncAction(
                currentFramePosition: 10,
                currentFrameDuration: 0.04,
                audioTimeClock: 9,
                fps: 25
            ),
            .waitForAudio(interval: 0.02)
        )
        XCTAssertEqual(
            IRFFDecoderDisplayLoopState.audioSyncAction(
                currentFramePosition: 10,
                currentFrameDuration: 0.02,
                audioTimeClock: 10.01,
                fps: 25
            ),
            .waitForAudio(interval: 0.015)
        )
    }

    func testFrameAcceptanceUsesDisplayPolicyOrdering() {
        XCTAssertTrue(
            IRFFDecoderDisplayLoopState.shouldAcceptFrame(
                currentPosition: nil,
                nextPosition: 0.5
            )
        )
        XCTAssertTrue(
            IRFFDecoderDisplayLoopState.shouldAcceptFrame(
                currentPosition: 1,
                nextPosition: 1
            )
        )
        XCTAssertFalse(
            IRFFDecoderDisplayLoopState.shouldAcceptFrame(
                currentPosition: 1,
                nextPosition: 0.5
            )
        )
        XCTAssertFalse(
            IRFFDecoderDisplayLoopState.shouldAcceptFrame(
                currentPosition: 1,
                nextPosition: .nan
            )
        )
    }

    func testStandaloneSleepActionUsesFrameDurationOrFPSFallback() {
        XCTAssertEqual(
            IRFFDecoderDisplayLoopState.standaloneSleepAction(frameDuration: 0.04, fps: 25),
            .sleepAfterFrame(interval: 0.04)
        )
        XCTAssertEqual(
            IRFFDecoderDisplayLoopState.standaloneSleepAction(frameDuration: 0, fps: 25),
            .sleepAfterFrame(interval: 0.04)
        )
        XCTAssertNil(IRFFDecoderDisplayLoopState.standaloneSleepAction(frameDuration: 0, fps: 0))
    }
}
