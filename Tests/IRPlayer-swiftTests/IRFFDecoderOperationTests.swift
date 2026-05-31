import Foundation
import XCTest
@testable import IRPlayer_swift

final class IRFFDecoderOperationTests: XCTestCase {

    func testCodecContextHelpersRejectMissingOrDisabledFormatContext() {
        let formatContext = IRFFFormatContext(contentURL: URL(fileURLWithPath: "/tmp/missing.mp4"), videoFormat: .mpeg4)

        XCTAssertNil(IRFFDecoder.videoCodecContext(from: nil))
        XCTAssertNil(IRFFDecoder.audioCodecContext(from: nil))
        XCTAssertNil(IRFFDecoder.videoCodecContext(from: formatContext))
        XCTAssertNil(IRFFDecoder.audioCodecContext(from: formatContext))
    }

    func testOperationSchedulingTreatsMissingOrFinishedOperationsAsSchedulable() {
        XCTAssertTrue(IRFFDecoder.needsScheduling(nil))

        let operation = BlockOperation {}
        XCTAssertFalse(IRFFDecoder.needsScheduling(operation))

        operation.start()
        XCTAssertTrue(operation.isFinished)
        XCTAssertTrue(IRFFDecoder.needsScheduling(operation))
    }

    func testOperationHelpersIgnoreMissingInputsAndWireDependencies() {
        let queue = OperationQueue()
        queue.isSuspended = true

        let operation = BlockOperation {}
        let dependency = BlockOperation {}

        XCTAssertFalse(IRFFDecoder.addDependency(dependency, to: nil))
        XCTAssertFalse(IRFFDecoder.addDependency(nil, to: operation))
        XCTAssertTrue(IRFFDecoder.addDependency(dependency, to: operation))
        XCTAssertTrue(operation.dependencies.contains { $0 === dependency })

        XCTAssertFalse(IRFFDecoder.enqueue(nil, on: queue))
        XCTAssertFalse(IRFFDecoder.enqueue(operation, on: nil))
        XCTAssertTrue(IRFFDecoder.enqueue(operation, on: queue))
        XCTAssertTrue(queue.operations.contains { $0 === operation })

        queue.cancelAllOperations()
        queue.isSuspended = false
    }

    func testAudioPacketErrorUsesPacketResult() throws {
        XCTAssertNil(IRFFDecoder.audioPacketError(fromPacketResult: 0))

        let error = try XCTUnwrap(IRFFDecoder.audioPacketError(fromPacketResult: -1))
        XCTAssertEqual(error.code, IRFFDecoderErrorCode.codecAudioSendPacket.rawValue)
        XCTAssertTrue(error.domain.contains("ffmpeg code: -1"))
    }

    func testBufferedDurationTransitionNormalizesTinyDurationsAndMarksFinishedAtEndOfFile() {
        XCTAssertEqual(
            IRFFDecoder.bufferedDurationTransition(bufferedDuration: 0.0000001, endOfFile: false),
            IRFFDecoder.BufferedDurationTransition(bufferedDuration: 0, shouldFinishPlayback: false)
        )
        XCTAssertEqual(
            IRFFDecoder.bufferedDurationTransition(bufferedDuration: 0, endOfFile: true),
            IRFFDecoder.BufferedDurationTransition(bufferedDuration: 0, shouldFinishPlayback: true)
        )
        XCTAssertEqual(
            IRFFDecoder.bufferedDurationTransition(bufferedDuration: 0.5, endOfFile: true),
            IRFFDecoder.BufferedDurationTransition(bufferedDuration: 0.5, shouldFinishPlayback: false)
        )
    }

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

    func testReleaseDoesNotPrintDebugOutput() {
        var decoder: IRFFDecoder? = IRFFDecoder(
            contentURL: URL(fileURLWithPath: "/tmp/missing.mp4"),
            videoFormat: .mpeg4,
            videoOutput: nil,
            audioOutput: nil
        )
        XCTAssertNotNil(decoder)

        let output = captureStandardOutput {
            decoder = nil
        }

        XCTAssertEqual(output, "")
    }
}
