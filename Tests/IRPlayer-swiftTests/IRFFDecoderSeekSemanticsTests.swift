import XCTest
@testable import IRPlayer_swift

final class IRFFDecoderSeekSemanticsTests: XCTestCase {

    func testSeekPreparationClampsRequestedTimeUsingAudioOrVideoTailBuffer() {
        XCTAssertEqual(
            IRFFDecoder.seekPreparation(
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
            IRFFDecoder.seekPreparation(
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
            IRFFDecoder.seekPreparation(
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
            IRFFDecoder.seekPreparation(
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
            IRFFDecoder.seekPreparation(
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
            IRFFDecoder.seekPreparation(
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

    func testSeekPreparationRejectsNegativeAndNonFiniteBounds() {
        let invalidCases: [
            (
                seekMinTime: TimeInterval,
                duration: TimeInterval,
                minBufferedDuration: TimeInterval
            )
        ] = [
            (-1, 120, 2),
            (0, -1, 2),
            (0, 120, -1),
            (0, .infinity, 2),
            (0, 120, .infinity)
        ]

        for invalidCase in invalidCases {
            XCTAssertNil(
                IRFFDecoder.seekPreparation(
                    requestedTime: 30,
                    seekEnabled: true,
                    hasError: false,
                    hasAudio: true,
                    seekMinTime: invalidCase.seekMinTime,
                    duration: invalidCase.duration,
                    minBufferedDuration:
                        invalidCase.minBufferedDuration
                )
            )
        }
    }

    func testSeekPreparationHandlesGreatestFiniteBounds() {
        XCTAssertEqual(
            IRFFDecoder.seekPreparation(
                requestedTime: 30,
                seekEnabled: true,
                hasError: false,
                hasAudio: true,
                seekMinTime: 0,
                duration: .greatestFiniteMagnitude,
                minBufferedDuration: .greatestFiniteMagnitude
            ),
            .init(clampedTime: 0)
        )
    }

    func testSeekPreparationCollapsesInvertedRangeToMinimum() {
        XCTAssertEqual(
            IRFFDecoder.seekPreparation(
                requestedTime: 500,
                seekEnabled: true,
                hasError: false,
                hasAudio: false,
                seekMinTime: 10,
                duration: 5,
                minBufferedDuration: 2
            ),
            .init(clampedTime: 10)
        )
    }

    func testResumeSeekTargetRestartsOnlyFinishedPlayback() {
        XCTAssertNil(
            IRFFDecoder.resumeSeekTarget(playbackFinished: false)
        )
        XCTAssertEqual(
            IRFFDecoder.resumeSeekTarget(playbackFinished: true),
            0
        )
    }

    func testSeekCompletionTransitionResetsPendingSeekState() {
        XCTAssertNil(
            IRFFDecoder.seekCompletionTransition(
                seeking: false,
                progress: 3
            )
        )
        XCTAssertNil(
            IRFFDecoder.seekCompletionTransition(
                seeking: true,
                progress: .nan
            )
        )
        XCTAssertEqual(
            IRFFDecoder.seekCompletionTransition(
                seeking: true,
                progress: 3
            ),
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
