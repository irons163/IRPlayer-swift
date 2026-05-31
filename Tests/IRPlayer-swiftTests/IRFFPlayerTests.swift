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

    func testAudioCopyPlanRejectsInvalidFrameOffsets() {
        XCTAssertNil(IRFFPlayer.audioCopyPlan(frameSize: 128, outputOffset: -1, remainingFrames: 32, numberOfChannels: 2))
        XCTAssertNil(IRFFPlayer.audioCopyPlan(frameSize: 128, outputOffset: 129, remainingFrames: 32, numberOfChannels: 2))
        XCTAssertNil(IRFFPlayer.audioCopyPlan(frameSize: 128, outputOffset: 0, remainingFrames: 32, numberOfChannels: 0))
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

}
