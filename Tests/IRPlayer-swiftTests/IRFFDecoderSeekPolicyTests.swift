import XCTest
@testable import IRPlayer_swift

final class IRFFDecoderSeekPolicyTests: XCTestCase {

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

    func testResumeSeekTargetRestartsOnlyFinishedPlayback() {
        XCTAssertNil(IRFFDecoder.resumeSeekTarget(playbackFinished: false))
        XCTAssertEqual(IRFFDecoder.resumeSeekTarget(playbackFinished: true), 0)
    }

    func testSeekCompletionTransitionResetsPendingSeekState() {
        XCTAssertNil(IRFFDecoder.seekCompletionTransition(seeking: false, progress: 3))
        XCTAssertEqual(
            IRFFDecoder.seekCompletionTransition(seeking: true, progress: 3),
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

    func testAudioTrackSelectionSeekTargetRequiresRebuiltActiveAudioDecoder() {
        XCTAssertNil(
            IRFFDecoder.audioTrackSelectionSeekTarget(
                selectionPending: false,
                decoderWasReset: true,
                hasAudioDecoder: true,
                playbackFinished: false,
                audioTimeClock: 12
            )
        )
        XCTAssertNil(
            IRFFDecoder.audioTrackSelectionSeekTarget(
                selectionPending: true,
                decoderWasReset: false,
                hasAudioDecoder: true,
                playbackFinished: false,
                audioTimeClock: 12
            )
        )
        XCTAssertNil(
            IRFFDecoder.audioTrackSelectionSeekTarget(
                selectionPending: true,
                decoderWasReset: true,
                hasAudioDecoder: false,
                playbackFinished: false,
                audioTimeClock: 12
            )
        )
        XCTAssertNil(
            IRFFDecoder.audioTrackSelectionSeekTarget(
                selectionPending: true,
                decoderWasReset: true,
                hasAudioDecoder: true,
                playbackFinished: true,
                audioTimeClock: 12
            )
        )
        XCTAssertEqual(
            IRFFDecoder.audioTrackSelectionSeekTarget(
                selectionPending: true,
                decoderWasReset: true,
                hasAudioDecoder: true,
                playbackFinished: false,
                audioTimeClock: 12
            ),
            12
        )
    }
}
