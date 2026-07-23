import XCTest
@testable import IRPlayer_swift

final class IRFFDecoderSeekPolicyTests: XCTestCase {

    func testSeekPreparationClampsRequestedTimeUsingAudioOrVideoTailBuffer() {
        XCTAssertEqual(
            IRFFDecoderSeekPolicy.seekPreparation(
                requestedTime: 90,
                seekEnabled: true,
                hasError: false,
                hasAudio: true,
                seekMinTime: 10,
                duration: 120,
                minBufferedDuration: 2
            ),
            IRFFDecoder.SeekPreparation(clampedTime: 90)
        )
        XCTAssertEqual(
            IRFFDecoderSeekPolicy.seekPreparation(
                requestedTime: 500,
                seekEnabled: true,
                hasError: false,
                hasAudio: true,
                seekMinTime: 10,
                duration: 120,
                minBufferedDuration: 2
            ),
            IRFFDecoder.SeekPreparation(clampedTime: 110)
        )
        XCTAssertEqual(
            IRFFDecoderSeekPolicy.seekPreparation(
                requestedTime: 500,
                seekEnabled: true,
                hasError: false,
                hasAudio: false,
                seekMinTime: 10,
                duration: 120,
                minBufferedDuration: 2
            ),
            IRFFDecoder.SeekPreparation(clampedTime: 103)
        )
    }

    func testSeekPreparationRejectsDisabledErroredOrInvalidInputs() {
        XCTAssertNil(
            IRFFDecoderSeekPolicy.seekPreparation(
                requestedTime: 30,
                seekEnabled: false,
                hasError: false,
                hasAudio: false,
                seekMinTime: 0,
                duration: 120,
                minBufferedDuration: 2
            )
        )
        XCTAssertNil(
            IRFFDecoderSeekPolicy.seekPreparation(
                requestedTime: 30,
                seekEnabled: true,
                hasError: true,
                hasAudio: false,
                seekMinTime: 0,
                duration: 120,
                minBufferedDuration: 2
            )
        )
        XCTAssertNil(
            IRFFDecoderSeekPolicy.seekPreparation(
                requestedTime: .nan,
                seekEnabled: true,
                hasError: false,
                hasAudio: false,
                seekMinTime: 0,
                duration: 120,
                minBufferedDuration: 2
            )
        )
    }

    func testResumeSeekTargetRestartsOnlyFinishedPlayback() {
        XCTAssertNil(IRFFDecoderSeekPolicy.resumeSeekTarget(playbackFinished: false))
        XCTAssertEqual(IRFFDecoderSeekPolicy.resumeSeekTarget(playbackFinished: true), 0)
    }

    func testSeekCompletionTransitionResetsPendingSeekState() {
        XCTAssertNil(IRFFDecoderSeekPolicy.seekCompletionTransition(seeking: false, progress: 3))
        XCTAssertEqual(
            IRFFDecoderSeekPolicy.seekCompletionTransition(seeking: true, progress: 3),
            IRFFDecoder.SeekCompletionTransition(
                endOfFile: false,
                playbackFinished: false,
                buffering: true,
                videoPaused: false,
                videoEndOfFile: false,
                seekToTime: 0,
                audioTimeClock: 3,
                shouldClearFrames: true
            )
        )
    }

}
