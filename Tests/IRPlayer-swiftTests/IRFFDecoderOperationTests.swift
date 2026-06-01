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

    func testPacketBufferBackpressureSleepIntervalUsesConfiguredThresholdAndPauseState() {
        XCTAssertNil(
            IRFFDecoder.packetBufferBackpressureSleepInterval(
                audioSize: 3,
                videoPacketSize: 6,
                maxBufferSize: 10,
                paused: false
            )
        )
        XCTAssertEqual(
            IRFFDecoder.packetBufferBackpressureSleepInterval(
                audioSize: 4,
                videoPacketSize: 6,
                maxBufferSize: 10,
                paused: false
            ),
            0.1
        )
        XCTAssertEqual(
            IRFFDecoder.packetBufferBackpressureSleepInterval(
                audioSize: 5,
                videoPacketSize: 6,
                maxBufferSize: 10,
                paused: true
            ),
            0.5
        )
    }

    func testPacketBufferBackpressureSleepIntervalRejectsInvalidSizes() {
        XCTAssertNil(
            IRFFDecoder.packetBufferBackpressureSleepInterval(
                audioSize: -1,
                videoPacketSize: 6,
                maxBufferSize: 10,
                paused: false
            )
        )
        XCTAssertNil(
            IRFFDecoder.packetBufferBackpressureSleepInterval(
                audioSize: 4,
                videoPacketSize: -1,
                maxBufferSize: 10,
                paused: false
            )
        )
        XCTAssertNil(
            IRFFDecoder.packetBufferBackpressureSleepInterval(
                audioSize: 4,
                videoPacketSize: 6,
                maxBufferSize: 0,
                paused: false
            )
        )
    }

    func testShouldFetchAudioFrameRequiresActiveAudioPlaybackState() {
        XCTAssertTrue(
            IRFFDecoder.shouldFetchAudioFrame(
                closed: false,
                seeking: false,
                buffering: false,
                paused: false,
                playbackFinished: false,
                audioEnabled: true
            )
        )
        XCTAssertFalse(
            IRFFDecoder.shouldFetchAudioFrame(
                closed: true,
                seeking: false,
                buffering: false,
                paused: false,
                playbackFinished: false,
                audioEnabled: true
            )
        )
        XCTAssertFalse(
            IRFFDecoder.shouldFetchAudioFrame(
                closed: false,
                seeking: true,
                buffering: false,
                paused: false,
                playbackFinished: false,
                audioEnabled: true
            )
        )
        XCTAssertFalse(
            IRFFDecoder.shouldFetchAudioFrame(
                closed: false,
                seeking: false,
                buffering: true,
                paused: false,
                playbackFinished: false,
                audioEnabled: true
            )
        )
        XCTAssertFalse(
            IRFFDecoder.shouldFetchAudioFrame(
                closed: false,
                seeking: false,
                buffering: false,
                paused: true,
                playbackFinished: false,
                audioEnabled: true
            )
        )
        XCTAssertFalse(
            IRFFDecoder.shouldFetchAudioFrame(
                closed: false,
                seeking: false,
                buffering: false,
                paused: false,
                playbackFinished: true,
                audioEnabled: true
            )
        )
        XCTAssertFalse(
            IRFFDecoder.shouldFetchAudioFrame(
                closed: false,
                seeking: false,
                buffering: false,
                paused: false,
                playbackFinished: false,
                audioEnabled: false
            )
        )
    }

    func testReadPacketEOFTransitionOnlyAppliesForNegativeReadResults() {
        XCTAssertNil(IRFFDecoder.readPacketEOFTransition(readFrameResult: 0))
        XCTAssertNil(IRFFDecoder.readPacketEOFTransition(readFrameResult: 1))
        XCTAssertEqual(
            IRFFDecoder.readPacketEOFTransition(readFrameResult: nil),
            IRFFDecoder.ReadPacketEOFTransition(
                endOfFile: true,
                videoEndOfFile: true,
                shouldFinishReadLoop: true,
                shouldNotifyDelegate: true
            )
        )
        XCTAssertEqual(
            IRFFDecoder.readPacketEOFTransition(readFrameResult: -1),
            IRFFDecoder.ReadPacketEOFTransition(
                endOfFile: true,
                videoEndOfFile: true,
                shouldFinishReadLoop: true,
                shouldNotifyDelegate: true
            )
        )
    }

    func testPacketRouteMatchesVideoAndAudioTrackIndexes() {
        XCTAssertEqual(
            IRFFDecoder.packetRoute(streamIndex: 2, videoTrackIndex: 2, audioTrackIndex: 3),
            .video
        )
        XCTAssertEqual(
            IRFFDecoder.packetRoute(streamIndex: 3, videoTrackIndex: 2, audioTrackIndex: 3),
            .audio
        )
        XCTAssertEqual(
            IRFFDecoder.packetRoute(streamIndex: 4, videoTrackIndex: 2, audioTrackIndex: 3),
            .ignored
        )
        XCTAssertEqual(
            IRFFDecoder.packetRoute(streamIndex: 0, videoTrackIndex: nil, audioTrackIndex: nil),
            .ignored
        )
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
