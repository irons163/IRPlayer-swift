import Foundation
import XCTest
@testable import IRPlayer_swift

final class IRFFDecoderOperationTests: XCTestCase {

    func testStaticPolicyWrappersRemainSourceCompatible() {
        XCTAssertEqual(
            IRFFDecoder.needsScheduling(nil),
            IRFFDecoderOperationPolicy.needsScheduling(nil)
        )
        XCTAssertEqual(
            IRFFDecoder.audioPacketError(fromPacketResult: -1)?.code,
            IRFFDecoderAudioPolicy.audioPacketError(fromPacketResult: -1)?.code
        )
        XCTAssertEqual(
            IRFFDecoder.bufferedDurationTransition(bufferedDuration: 0, endOfFile: true),
            IRFFDecoderAudioPolicy.bufferedDurationTransition(bufferedDuration: 0, endOfFile: true)
        )
        XCTAssertEqual(
            IRFFDecoder.packetBufferBackpressureSleepInterval(
                audioSize: 4,
                videoPacketSize: 6,
                maxBufferSize: 10,
                paused: false
            ),
            IRFFDecoderPacketPolicy.packetBufferBackpressureSleepInterval(
                audioSize: 4,
                videoPacketSize: 6,
                maxBufferSize: 10,
                paused: false
            )
        )
        XCTAssertEqual(
            IRFFDecoder.seekPreparation(
                requestedTime: 30,
                seekEnabled: true,
                hasError: false,
                hasAudio: true,
                seekMinTime: 0,
                duration: 40,
                minBufferedDuration: 2
            ),
            IRFFDecoderSeekPolicy.seekPreparation(
                requestedTime: 30,
                seekEnabled: true,
                hasError: false,
                hasAudio: true,
                seekMinTime: 0,
                duration: 40,
                minBufferedDuration: 2
            )
        )
        XCTAssertEqual(
            IRFFDecoder.audioSyncedVideoSleepDuration(
                framePosition: 10,
                frameDuration: 0.04,
                audioTimeClock: 9,
                fps: 25
            ),
            IRFFDecoderDisplayPolicy.audioSyncedVideoSleepDuration(
                framePosition: 10,
                frameDuration: 0.04,
                audioTimeClock: 9,
                fps: 25
            )
        )
        XCTAssertEqual(
            IRFFDecoder.standaloneVideoSleepDuration(frameDuration: 0.04, fps: 25),
            IRFFDecoderDisplayPolicy.standaloneVideoSleepDuration(frameDuration: 0.04, fps: 25)
        )
        XCTAssertEqual(
            IRFFDecoder.videoFrameOrderingPosition(1.25),
            IRFFDecoderDisplayPolicy.videoFrameOrderingPosition(1.25)
        )
        XCTAssertEqual(
            IRFFDecoder.shouldAcceptVideoFrame(currentPosition: 1, nextPosition: 2),
            IRFFDecoderDisplayPolicy.shouldAcceptVideoFrame(currentPosition: 1, nextPosition: 2)
        )
        XCTAssertEqual(
            IRFFDecoder.shouldFetchAudioFrame(
                closed: false,
                seeking: false,
                buffering: false,
                paused: false,
                playbackFinished: false,
                audioEnabled: true
            ),
            IRFFDecoderAudioPolicy.shouldFetchAudioFrame(
                closed: false,
                seeking: false,
                buffering: false,
                paused: false,
                playbackFinished: false,
                audioEnabled: true
            )
        )
        XCTAssertEqual(
            IRFFDecoder.resumeSeekTarget(playbackFinished: true),
            IRFFDecoderSeekPolicy.resumeSeekTarget(playbackFinished: true)
        )
        XCTAssertEqual(
            IRFFDecoder.seekCompletionTransition(seeking: true, progress: 3),
            IRFFDecoderSeekPolicy.seekCompletionTransition(seeking: true, progress: 3)
        )
        XCTAssertEqual(
            IRFFDecoder.audioTrackSelectionSeekTarget(
                selectionPending: true,
                decoderWasReset: true,
                hasAudioDecoder: true,
                playbackFinished: false,
                audioTimeClock: 12
            ),
            IRFFDecoderSeekPolicy.audioTrackSelectionSeekTarget(
                selectionPending: true,
                decoderWasReset: true,
                hasAudioDecoder: true,
                playbackFinished: false,
                audioTimeClock: 12
            )
        )
        XCTAssertEqual(
            IRFFDecoder.readPacketEOFTransition(readFrameResult: -1),
            IRFFDecoderPacketPolicy.readPacketEOFTransition(readFrameResult: -1)
        )
        XCTAssertEqual(
            IRFFDecoder.packetRoute(streamIndex: 2, videoTrackIndex: 2, audioTrackIndex: 3),
            IRFFDecoderPacketPolicy.packetRoute(streamIndex: 2, videoTrackIndex: 2, audioTrackIndex: 3)
        )
        XCTAssertEqual(
            IRFFDecoder.displayIdleSleepInterval(
                seeking: true,
                buffering: false,
                paused: false,
                hasCurrentFrame: false
            ),
            IRFFDecoderDisplayPolicy.displayIdleSleepInterval(
                seeking: true,
                buffering: false,
                paused: false,
                hasCurrentFrame: false
            )
        )
        XCTAssertEqual(
            IRFFDecoder.shouldFinishDisplay(endOfFile: true, videoDecoderEmpty: true),
            IRFFDecoderDisplayPolicy.shouldFinishDisplay(endOfFile: true, videoDecoderEmpty: true)
        )
    }

    func testCodecContextHelpersRejectMissingOrDisabledFormatContext() {
        let formatContext = IRFFFormatContext(contentURL: URL(fileURLWithPath: "/tmp/missing.mp4"), videoFormat: .mpeg4)

        XCTAssertNil(IRFFDecoderCodecContextPolicy.videoCodecContext(from: nil))
        XCTAssertNil(IRFFDecoderCodecContextPolicy.audioCodecContext(from: nil))
        XCTAssertNil(IRFFDecoderCodecContextPolicy.videoCodecContext(from: formatContext))
        XCTAssertNil(IRFFDecoderCodecContextPolicy.audioCodecContext(from: formatContext))
        XCTAssertNil(IRFFDecoder.videoCodecContext(from: nil))
        XCTAssertNil(IRFFDecoder.audioCodecContext(from: nil))
        XCTAssertNil(IRFFDecoder.videoCodecContext(from: formatContext))
        XCTAssertNil(IRFFDecoder.audioCodecContext(from: formatContext))
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
