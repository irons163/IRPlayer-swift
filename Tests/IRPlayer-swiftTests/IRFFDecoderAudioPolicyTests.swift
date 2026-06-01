import XCTest
@testable import IRPlayer_swift

final class IRFFDecoderAudioPolicyTests: XCTestCase {

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
}
