import Foundation
import XCTest
@testable import IRPlayer_swift

final class IRFFPlayerTests: XCTestCase {

    func testFactoryCreatesPlayerWhenAudioManagerIsMissing() {
        let abstractPlayer = IRPlayerImp.player()
        abstractPlayer.manager = nil

        let ffPlayer = IRFFPlayer.player(with: abstractPlayer)

        XCTAssertNil(ffPlayer.audioManager)
        XCTAssertEqual(ffPlayer.duration, 0)
        withExtendedLifetime(abstractPlayer) {}
    }

    func testReleaseDoesNotPrintDebugOutput() {
        let abstractPlayer = IRPlayerImp.player()
        abstractPlayer.manager = nil
        var ffPlayer: IRFFPlayer? = IRFFPlayer.player(with: abstractPlayer)
        XCTAssertNotNil(ffPlayer)

        let output = captureStandardOutput {
            ffPlayer = nil
        }

        XCTAssertEqual(output, "")
        withExtendedLifetime(abstractPlayer) {}
    }

    func testPlayableBufferIntervalReloadsFFmpegDecoderBufferDuration() throws {
        let player = IRPlayerImp.player()
        player.decoder = IRPlayerDecoder.FFmpegDecoder()
        player.manager = nil
        player.replaceVideoWithURL(contentURL: NSURL(fileURLWithPath: "/tmp/missing.flv"))

        let ffPlayer = try XCTUnwrap(mirroredFFPlayer(from: player))
        addTeardownBlock {
            ffPlayer.stop()
        }
        let decoder = try XCTUnwrap(ffPlayer.decoder)
        XCTAssertEqual(decoder.minBufferedDuration, 2)

        player.playableBufferInterval = 7

        XCTAssertEqual(decoder.minBufferedDuration, 7)
        withExtendedLifetime(player) {}
    }

    func testPlayableTimePostsNotificationWhenBufferedTimeChangesWithinDuration() throws {
        let abstractPlayer = IRPlayerImp.player()
        abstractPlayer.manager = nil
        let ffPlayer = IRFFPlayer.player(with: abstractPlayer)
        ffPlayer.decoder = FixedDurationFFDecoder(duration: 10)

        let expectation = expectation(description: "playable notification")
        let observer = NotificationCenter.default.addObserver(
            forName: Notification.Name(IRPlayerPlayableChangeNotificationName),
            object: abstractPlayer,
            queue: .main
        ) { notification in
            let playable = IRModel.playable(fromUserInfo: notification.userInfo ?? [:])
            XCTAssertEqual(playable.current, 4, accuracy: 0.0001)
            XCTAssertEqual(playable.total, 10, accuracy: 0.0001)
            expectation.fulfill()
        }
        addTeardownBlock {
            NotificationCenter.default.removeObserver(observer)
        }

        ffPlayer.playableTime = 4

        wait(for: [expectation], timeout: 1)
        withExtendedLifetime(abstractPlayer) {}
    }

    func testAudioCopyPlanRejectsInvalidFrameOffsets() {
        XCTAssertNil(IRFFPlayer.audioCopyPlan(frameSize: 128, outputOffset: -1, remainingFrames: 32, numberOfChannels: 2))
        XCTAssertNil(IRFFPlayer.audioCopyPlan(frameSize: 128, outputOffset: 129, remainingFrames: 32, numberOfChannels: 2))
        XCTAssertNil(IRFFPlayer.audioCopyPlan(frameSize: 128, outputOffset: 0, remainingFrames: 32, numberOfChannels: 0))
    }

    func testAudioCopyPlanRejectsUnalignedFrameOffsets() {
        XCTAssertNil(IRFFPlayer.audioCopyPlan(frameSize: 128, outputOffset: 1, remainingFrames: 32, numberOfChannels: 2))
        XCTAssertNil(IRFFPlayer.audioCopyPlan(frameSize: 128, outputOffset: 4, remainingFrames: 32, numberOfChannels: 2))
    }

    func testAudioCopyPlanRejectsOverflowingFrameCalculations() {
        XCTAssertNil(
            IRFFPlayer.audioCopyPlan(
                frameSize: Int.max,
                outputOffset: 0,
                remainingFrames: .max,
                numberOfChannels: .max
            )
        )
    }

    func testAudioSilenceByteCountRejectsInvalidOrOverflowingInputs() {
        XCTAssertNil(IRFFPlayer.audioSilenceByteCount(numberOfFrames: 0, numberOfChannels: 2))
        XCTAssertNil(IRFFPlayer.audioSilenceByteCount(numberOfFrames: 10, numberOfChannels: 0))
        XCTAssertNil(IRFFPlayer.audioSilenceByteCount(numberOfFrames: .max, numberOfChannels: .max))
    }

    func testAudioSilenceByteCountCalculatesFloatStorageSize() {
        XCTAssertEqual(IRFFPlayer.audioSilenceByteCount(numberOfFrames: 10, numberOfChannels: 2), 80)
    }

    func testAudioCopyPlanCalculatesFramesAndBytesWithinBounds() throws {
        let partial = try XCTUnwrap(
            IRFFPlayer.audioCopyPlan(frameSize: 128, outputOffset: 0, remainingFrames: 10, numberOfChannels: 2)
        )
        XCTAssertEqual(partial.bytesToCopy, 80)
        XCTAssertEqual(partial.framesToCopy, 10)
        XCTAssertTrue(partial.hasRemainingFrameBytes)

        let final = try XCTUnwrap(
            IRFFPlayer.audioCopyPlan(frameSize: 128, outputOffset: 120, remainingFrames: 10, numberOfChannels: 2)
        )
        XCTAssertEqual(final.bytesToCopy, 8)
        XCTAssertEqual(final.framesToCopy, 1)
        XCTAssertFalse(final.hasRemainingFrameBytes)
    }

    func testAudioCopyPlanCopiesOnlyWholeFrames() throws {
        let plan = try XCTUnwrap(
            IRFFPlayer.audioCopyPlan(frameSize: 10, outputOffset: 0, remainingFrames: 2, numberOfChannels: 2)
        )

        XCTAssertEqual(plan.bytesToCopy, 8)
        XCTAssertEqual(plan.framesToCopy, 1)
        XCTAssertTrue(plan.hasRemainingFrameBytes)
    }

    func testStaticPolicyWrappersRemainSourceCompatible() {
        XCTAssertEqual(
            IRFFPlayer.replaceVideoReadiness(hasAbstractPlayer: true, hasContentURL: true, hasDisplayView: false),
            IRFFPlayerPlaybackPolicy.replaceVideoReadiness(
                hasAbstractPlayer: true,
                hasContentURL: true,
                hasDisplayView: false
            )
        )
        XCTAssertEqual(
            IRFFPlayer.playTransition(from: .finished),
            IRFFPlayerPlaybackPolicy.playTransition(from: .finished)
        )
        XCTAssertEqual(
            IRFFPlayer.pauseTransition(from: .playing),
            IRFFPlayerPlaybackPolicy.pauseTransition(from: .playing)
        )
        XCTAssertEqual(
            IRFFPlayer.bufferingTransition(isBuffering: false, isPlaying: false, hasPreparedOnce: false),
            IRFFPlayerPlaybackPolicy.bufferingTransition(
                isBuffering: false,
                isPlaying: false,
                hasPreparedOnce: false
            )
        )
        XCTAssertEqual(
            IRFFPlayer.audioSilenceByteCount(numberOfFrames: 10, numberOfChannels: 2),
            IRFFPlayerPlaybackPolicy.audioSilenceByteCount(numberOfFrames: 10, numberOfChannels: 2)
        )

        XCTAssertEqual(
            IRFFPlayer.audioCopyPlan(
                frameSize: 128,
                outputOffset: 0,
                remainingFrames: 10,
                numberOfChannels: 2
            ),
            IRFFPlayerPlaybackPolicy.audioCopyPlan(
                frameSize: 128,
                outputOffset: 0,
                remainingFrames: 10,
                numberOfChannels: 2
            )
        )
    }

    func testReplaceVideoReadinessDistinguishesNoOpAndFailurePreconditions() {
        XCTAssertEqual(
            IRFFPlayer.replaceVideoReadiness(hasAbstractPlayer: false, hasContentURL: true, hasDisplayView: true),
            .missingRequiredInput
        )
        XCTAssertEqual(
            IRFFPlayer.replaceVideoReadiness(hasAbstractPlayer: true, hasContentURL: false, hasDisplayView: true),
            .missingRequiredInput
        )
        XCTAssertEqual(
            IRFFPlayer.replaceVideoReadiness(hasAbstractPlayer: true, hasContentURL: true, hasDisplayView: false),
            .missingDisplayView
        )
        XCTAssertEqual(
            IRFFPlayer.replaceVideoReadiness(hasAbstractPlayer: true, hasContentURL: true, hasDisplayView: true),
            .ready
        )
    }

    func testPlayTransitionMapsCurrentStateToNextStateAndSeekDecision() {
        XCTAssertEqual(IRFFPlayer.playTransition(from: .finished), IRFFPlayer.PlayTransition(nextState: .playing, shouldSeekToStart: true))
        XCTAssertEqual(IRFFPlayer.playTransition(from: .none), IRFFPlayer.PlayTransition(nextState: .buffering, shouldSeekToStart: false))
        XCTAssertEqual(IRFFPlayer.playTransition(from: .failed), IRFFPlayer.PlayTransition(nextState: .buffering, shouldSeekToStart: false))
        XCTAssertEqual(IRFFPlayer.playTransition(from: .buffering), IRFFPlayer.PlayTransition(nextState: .buffering, shouldSeekToStart: false))
        XCTAssertEqual(IRFFPlayer.playTransition(from: .readyToPlay), IRFFPlayer.PlayTransition(nextState: .playing, shouldSeekToStart: false))
        XCTAssertEqual(IRFFPlayer.playTransition(from: .playing), IRFFPlayer.PlayTransition(nextState: .playing, shouldSeekToStart: false))
        XCTAssertEqual(IRFFPlayer.playTransition(from: .suspend), IRFFPlayer.PlayTransition(nextState: .playing, shouldSeekToStart: false))
    }

    func testPauseTransitionSuspendsOnlyActiveOrTerminalPlaybackStates() {
        XCTAssertNil(IRFFPlayer.pauseTransition(from: .none))
        XCTAssertNil(IRFFPlayer.pauseTransition(from: .suspend))
        XCTAssertEqual(IRFFPlayer.pauseTransition(from: .failed), .suspend)
        XCTAssertEqual(IRFFPlayer.pauseTransition(from: .readyToPlay), .suspend)
        XCTAssertEqual(IRFFPlayer.pauseTransition(from: .finished), .suspend)
        XCTAssertEqual(IRFFPlayer.pauseTransition(from: .playing), .suspend)
        XCTAssertEqual(IRFFPlayer.pauseTransition(from: .buffering), .suspend)
    }

    func testBufferingTransitionMapsDecoderBufferingStateAndPrepareToken() {
        XCTAssertEqual(
            IRFFPlayer.bufferingTransition(isBuffering: true, isPlaying: false, hasPreparedOnce: false),
            IRFFPlayer.BufferingTransition(nextState: .buffering, hasPreparedOnce: false)
        )
        XCTAssertEqual(
            IRFFPlayer.bufferingTransition(isBuffering: false, isPlaying: true, hasPreparedOnce: false),
            IRFFPlayer.BufferingTransition(nextState: .playing, hasPreparedOnce: false)
        )
        XCTAssertEqual(
            IRFFPlayer.bufferingTransition(isBuffering: false, isPlaying: false, hasPreparedOnce: false),
            IRFFPlayer.BufferingTransition(nextState: .readyToPlay, hasPreparedOnce: true)
        )
        XCTAssertEqual(
            IRFFPlayer.bufferingTransition(isBuffering: false, isPlaying: false, hasPreparedOnce: true),
            IRFFPlayer.BufferingTransition(nextState: .suspend, hasPreparedOnce: true)
        )
    }

}

private final class FixedDurationFFDecoder: IRFFDecoder {
    private let fixedDuration: TimeInterval

    init(duration: TimeInterval) {
        self.fixedDuration = duration
        super.init(
            contentURL: URL(fileURLWithPath: "/tmp/fixed-duration.mp4"),
            videoFormat: .mpeg4,
            videoOutput: nil,
            audioOutput: nil
        )
    }

    override var duration: TimeInterval {
        fixedDuration
    }
}
