import XCTest
@testable import IRPlayer_swift

final class IRPlaybackTimePolicyTests: XCTestCase {

    func testPercentUsesFinitePositiveTotal() {
        XCTAssertEqual(IRPlaybackTimePolicy.percent(current: 3, total: 12), NSNumber(value: 0.25))
        XCTAssertEqual(IRPlaybackTimePolicy.percent(current: 3, total: 0), NSNumber(value: 0))
        XCTAssertEqual(IRPlaybackTimePolicy.percent(current: 3, total: -1), NSNumber(value: 0))
        XCTAssertEqual(IRPlaybackTimePolicy.percent(current: .nan, total: 12), NSNumber(value: 0))
        XCTAssertEqual(IRPlaybackTimePolicy.percent(current: 3, total: .infinity), NSNumber(value: 0))
    }

    func testClampedPlayableTimeBoundsFiniteValuesToDuration() {
        XCTAssertEqual(IRPlaybackTimePolicy.clampedPlayableTime(4, duration: 10), 4)
        XCTAssertEqual(IRPlaybackTimePolicy.clampedPlayableTime(-1, duration: 10), 0)
        XCTAssertEqual(IRPlaybackTimePolicy.clampedPlayableTime(12, duration: 10), 10)
    }

    func testClampedPlayableTimeRejectsInvalidValues() {
        XCTAssertEqual(IRPlaybackTimePolicy.clampedPlayableTime(.nan, duration: 10), 0)
        XCTAssertEqual(IRPlaybackTimePolicy.clampedPlayableTime(5, duration: .nan), 0)
        XCTAssertEqual(IRPlaybackTimePolicy.clampedPlayableTime(5, duration: -1), 0)
    }

    func testClampedSeekTimeBoundsRequestedTime() {
        XCTAssertEqual(IRPlaybackTimePolicy.clampedSeekTime(requested: 5, min: 1, max: 10), 5)
        XCTAssertEqual(IRPlaybackTimePolicy.clampedSeekTime(requested: -2, min: 1, max: 10), 1)
        XCTAssertEqual(IRPlaybackTimePolicy.clampedSeekTime(requested: 12, min: 1, max: 10), 10)
        XCTAssertEqual(IRPlaybackTimePolicy.clampedSeekTime(requested: 12, min: 4, max: 2), 4)
    }

    func testClampedSeekTimeRejectsNonFiniteInputs() {
        XCTAssertNil(IRPlaybackTimePolicy.clampedSeekTime(requested: .nan, min: 0, max: 10))
        XCTAssertNil(IRPlaybackTimePolicy.clampedSeekTime(requested: 1, min: .infinity, max: 10))
        XCTAssertNil(IRPlaybackTimePolicy.clampedSeekTime(requested: 1, min: 0, max: .nan))
    }

    func testBufferingStateEntersAndExitsBuffering() {
        XCTAssertTrue(IRPlaybackTimePolicy.bufferingState(currentlyBuffering: false, bufferedDuration: 0.2, minBufferedDuration: 2, endOfFile: false))
        XCTAssertFalse(IRPlaybackTimePolicy.bufferingState(currentlyBuffering: false, bufferedDuration: 0.3, minBufferedDuration: 2, endOfFile: false))
        XCTAssertTrue(IRPlaybackTimePolicy.bufferingState(currentlyBuffering: true, bufferedDuration: 1, minBufferedDuration: 2, endOfFile: false))
        XCTAssertFalse(IRPlaybackTimePolicy.bufferingState(currentlyBuffering: true, bufferedDuration: 2, minBufferedDuration: 2, endOfFile: false))
        XCTAssertFalse(IRPlaybackTimePolicy.bufferingState(currentlyBuffering: true, bufferedDuration: 0, minBufferedDuration: 2, endOfFile: true))
    }

    func testBufferingStateTreatsNonFiniteDurationsAsZero() {
        XCTAssertTrue(IRPlaybackTimePolicy.bufferingState(currentlyBuffering: false, bufferedDuration: .nan, minBufferedDuration: 2, endOfFile: false))
        XCTAssertFalse(IRPlaybackTimePolicy.bufferingState(currentlyBuffering: true, bufferedDuration: 1, minBufferedDuration: .nan, endOfFile: false))
    }

    func testProgressPostDecisionPostsAtStartEndAndThrottleBoundary() {
        XCTAssertEqual(
            IRPlaybackTimePolicy.progressPostDecision(progress: 0, oldProgress: 1, duration: 10, lastPostTime: 20, now: 20.1, seekEnabled: true),
            IRPlaybackTimePolicy.ProgressPostDecision(shouldPost: true, current: 0, total: 10, nextLastPostTime: 20)
        )

        XCTAssertEqual(
            IRPlaybackTimePolicy.progressPostDecision(progress: 10, oldProgress: 9, duration: 10, lastPostTime: 20, now: 20.1, seekEnabled: true),
            IRPlaybackTimePolicy.ProgressPostDecision(shouldPost: true, current: 10, total: 10, nextLastPostTime: 20)
        )

        XCTAssertEqual(
            IRPlaybackTimePolicy.progressPostDecision(progress: 5, oldProgress: 4, duration: 10, lastPostTime: 20, now: 20.5, seekEnabled: true),
            IRPlaybackTimePolicy.ProgressPostDecision(shouldPost: false, current: 5, total: 10, nextLastPostTime: 20)
        )

        XCTAssertEqual(
            IRPlaybackTimePolicy.progressPostDecision(progress: 5, oldProgress: 4, duration: 10, lastPostTime: 20, now: 21, seekEnabled: true),
            IRPlaybackTimePolicy.ProgressPostDecision(shouldPost: true, current: 5, total: 10, nextLastPostTime: 21)
        )
    }

    func testProgressPostDecisionUsesProgressAsDurationWhenSeekingIsDisabled() {
        XCTAssertEqual(
            IRPlaybackTimePolicy.progressPostDecision(progress: 5, oldProgress: 4, duration: 10, lastPostTime: 20, now: 21, seekEnabled: false),
            IRPlaybackTimePolicy.ProgressPostDecision(shouldPost: true, current: 5, total: 5, nextLastPostTime: 21)
        )
    }

    func testProgressPostDecisionRejectsUnchangedOrNonFiniteProgress() {
        XCTAssertEqual(
            IRPlaybackTimePolicy.progressPostDecision(progress: 4, oldProgress: 4, duration: 10, lastPostTime: 20, now: 21, seekEnabled: true),
            IRPlaybackTimePolicy.ProgressPostDecision(shouldPost: false, current: 4, total: 10, nextLastPostTime: 20)
        )

        XCTAssertEqual(
            IRPlaybackTimePolicy.progressPostDecision(progress: .nan, oldProgress: 4, duration: 10, lastPostTime: 20, now: 21, seekEnabled: true),
            IRPlaybackTimePolicy.ProgressPostDecision(shouldPost: false, current: 0, total: 10, nextLastPostTime: 20)
        )
    }
}
