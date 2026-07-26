import XCTest
import IRFFMpeg
import IRPlayerObjc
#if SWIFT_PACKAGE
@testable import IRPlayerSwift
#else
@testable import IRPlayer_swift
#endif

final class IRFFDecoderReadLoopStateTests: XCTestCase {

    func testExitActionQuitsForClosedOrErroredDecoder() {
        XCTAssertEqual(
            IRFFDecoderReadLoopState.exitAction(closed: true, hasError: false),
            .quit
        )
        XCTAssertEqual(
            IRFFDecoderReadLoopState.exitAction(closed: false, hasError: true),
            .quit
        )
        XCTAssertNil(IRFFDecoderReadLoopState.exitAction(closed: false, hasError: false))
    }

    func testSeekCompletionActionWrapsExistingSeekTransition() {
        XCTAssertNil(IRFFDecoderReadLoopState.seekCompletionAction(seeking: false, progress: 3))
        XCTAssertEqual(
            IRFFDecoderReadLoopState.seekCompletionAction(seeking: true, progress: 3),
            .completeSeek(
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
        )
    }

    func testBackpressureActionWrapsPacketPolicySleep() {
        XCTAssertNil(
            IRFFDecoderReadLoopState.backpressureAction(
                audioSize: 3,
                videoPacketSize: 6,
                maxBufferSize: 10,
                paused: false
            )
        )
        XCTAssertEqual(
            IRFFDecoderReadLoopState.backpressureAction(
                audioSize: 4,
                videoPacketSize: 6,
                maxBufferSize: 10,
                paused: false
            ),
            .sleep(0.1)
        )
        XCTAssertEqual(
            IRFFDecoderReadLoopState.backpressureAction(
                audioSize: 4,
                videoPacketSize: 6,
                maxBufferSize: 10,
                paused: true
            ),
            .sleep(0.5)
        )
    }

    func testEOFActionWrapsPacketEOFTransition() {
        XCTAssertNil(IRFFDecoderReadLoopState.eofAction(readFrameResult: 0))
        XCTAssertNil(
            IRFFDecoderReadLoopState.eofAction(
                readFrameResult: AVERROR(EAGAIN)
            )
        )
        XCTAssertNil(
            IRFFDecoderReadLoopState.eofAction(
                readFrameResult: -1
            )
        )
        XCTAssertEqual(
            IRFFDecoderReadLoopState.eofAction(
                readFrameResult: IR_AVERROR_EOF
            ),
            .finishEOF(
                IRFFDecoder.ReadPacketEOFTransition(
                    endOfFile: true,
                    videoEndOfFile: true,
                    shouldFinishReadLoop: true,
                    shouldNotifyDelegate: true
                )
            )
        )
    }

    func testReadResultRetriesEAGAINWithBoundedBackoff() {
        XCTAssertEqual(
            IRFFDecoderReadLoopState.classifyReadResult(
                AVERROR(EAGAIN),
                retryAttempt: 0
            ),
            .retry(after: 0.002)
        )
        XCTAssertEqual(
            IRFFDecoderReadLoopState.classifyReadResult(
                AVERROR(EAGAIN),
                retryAttempt: 4
            ),
            .retry(after: 0.032)
        )
        XCTAssertEqual(
            IRFFDecoderReadLoopState.classifyReadResult(
                AVERROR(EAGAIN),
                retryAttempt: 20
            ),
            .retry(after: 0.05)
        )
        XCTAssertEqual(
            IRFFDecoderReadLoopState.readAction(
                readFrameResult: AVERROR(EAGAIN),
                retryAttempt: 2
            ),
            .retryRead(0.008)
        )
    }

    func testReadResultTreatsOnlyFFmpegEOFAsTerminal() {
        XCTAssertEqual(
            IRFFDecoderReadLoopState.classifyReadResult(0),
            .packet
        )
        XCTAssertEqual(
            IRFFDecoderReadLoopState.classifyReadResult(
                IR_AVERROR_EOF
            ),
            .endOfStream
        )
        XCTAssertEqual(
            IRFFDecoderReadLoopState.classifyReadResult(-123),
            .failed(code: -123)
        )
        XCTAssertEqual(
            IRFFDecoderReadLoopState.readAction(
                readFrameResult: -123
            ),
            .failRead(-123)
        )
    }

    func testPacketActionRoutesByTrackIndexes() {
        XCTAssertEqual(
            IRFFDecoderReadLoopState.packetAction(
                streamIndex: 2,
                videoTrackIndex: 2,
                audioTrackIndex: 3
            ),
            .routePacket(.video)
        )
        XCTAssertEqual(
            IRFFDecoderReadLoopState.packetAction(
                streamIndex: 3,
                videoTrackIndex: 2,
                audioTrackIndex: 3
            ),
            .routePacket(.audio)
        )
        XCTAssertEqual(
            IRFFDecoderReadLoopState.packetAction(
                streamIndex: 4,
                videoTrackIndex: 2,
                audioTrackIndex: 3
            ),
            .routePacket(.ignored)
        )
    }
}
