import XCTest
#if SWIFT_PACKAGE
@testable import IRPlayerSwift
#else
@testable import IRPlayer_swift
#endif

final class IRFFDecoderAudioSemanticsTests: XCTestCase {

    func testAudioPacketErrorUsesPacketResult() throws {
        XCTAssertNil(IRFFDecoder.audioPacketError(fromPacketResult: 0))

        let error = try XCTUnwrap(
            IRFFDecoder.audioPacketError(fromPacketResult: -1)
        )
        XCTAssertEqual(error.code, IRFFDecoderErrorCode.codecAudioSendPacket.rawValue)
        XCTAssertTrue(error.domain.contains("ffmpeg code: -1"))
    }

    func testAudioPacketErrorRejectsUnrepresentableResultWithoutTrap() throws {
        XCTAssertNil(
            IRFFDecoder.audioPacketError(
                fromPacketResult: Int.max
            )
        )
        let error = try XCTUnwrap(
            IRFFDecoder.audioPacketError(
                fromPacketResult: Int.min
            )
        )
        XCTAssertEqual(
            error.code,
            IRFFDecoderErrorCode
                .codecAudioSendPacket.rawValue
        )
        XCTAssertTrue(error.domain.contains("outside Int32"))
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

    func testBufferedDurationTransitionNormalizesNonFiniteDurations() {
        XCTAssertEqual(
            IRFFDecoder.bufferedDurationTransition(bufferedDuration: .nan, endOfFile: true),
            IRFFDecoder.BufferedDurationTransition(bufferedDuration: 0, shouldFinishPlayback: true)
        )
        XCTAssertEqual(
            IRFFDecoder.bufferedDurationTransition(bufferedDuration: .infinity, endOfFile: false),
            IRFFDecoder.BufferedDurationTransition(bufferedDuration: 0, shouldFinishPlayback: false)
        )
    }

    func testShouldFetchAudioFrameRequiresActiveAudioPlaybackState() {
        XCTAssertTrue(
            IRFFDecoder.shouldFetchAudioFrame(
                closed: false,
                hasError: false,
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
                hasError: false,
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
                hasError: false,
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
                hasError: false,
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
                hasError: false,
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
                hasError: false,
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
                hasError: false,
                seeking: false,
                buffering: false,
                paused: false,
                playbackFinished: false,
                audioEnabled: false
            )
        )
        XCTAssertFalse(
            IRFFDecoder.shouldFetchAudioFrame(
                closed: false,
                hasError: true,
                seeking: false,
                buffering: false,
                paused: false,
                playbackFinished: false,
                audioEnabled: true
            )
        )
    }

    func testBufferingStatusTransitionEntersRegularBufferingAtLowDuration() {
        XCTAssertEqual(
            IRFFDecoder.bufferingStatusTransition(
                buffering: false,
                bufferedDuration: 0.2,
                endOfFile: false,
                isLiveStream: false,
                minBufferedDuration: 1.5,
                bufferingStartTime: 0,
                currentTime: 42
            ),
            IRFFDecoder.BufferingStatusTransition(buffering: true, bufferingStartTime: 42)
        )
    }

    func testBufferingStatusTransitionEntersLiveBufferingAtCriticalDuration() {
        XCTAssertEqual(
            IRFFDecoder.bufferingStatusTransition(
                buffering: false,
                bufferedDuration: 0.05,
                endOfFile: false,
                isLiveStream: true,
                minBufferedDuration: 1.5,
                bufferingStartTime: 0,
                currentTime: 42
            ),
            IRFFDecoder.BufferingStatusTransition(buffering: true, bufferingStartTime: 42)
        )
        XCTAssertEqual(
            IRFFDecoder.bufferingStatusTransition(
                buffering: false,
                bufferedDuration: 0.1,
                endOfFile: false,
                isLiveStream: true,
                minBufferedDuration: 1.5,
                bufferingStartTime: 7,
                currentTime: 42
            ),
            IRFFDecoder.BufferingStatusTransition(buffering: false, bufferingStartTime: 7)
        )
    }

    func testBufferingStatusTransitionExitsWhenBufferedDurationMeetsThreshold() {
        XCTAssertEqual(
            IRFFDecoder.bufferingStatusTransition(
                buffering: true,
                bufferedDuration: 1.5,
                endOfFile: false,
                isLiveStream: false,
                minBufferedDuration: 1.5,
                bufferingStartTime: 10,
                currentTime: 11
            ),
            IRFFDecoder.BufferingStatusTransition(buffering: false, bufferingStartTime: 0)
        )
    }

    func testBufferingStatusTransitionExitsAfterRegularTimeout() {
        XCTAssertEqual(
            IRFFDecoder.bufferingStatusTransition(
                buffering: true,
                bufferedDuration: 0.3,
                endOfFile: false,
                isLiveStream: false,
                minBufferedDuration: 1.5,
                bufferingStartTime: 10,
                currentTime: 12.1
            ),
            IRFFDecoder.BufferingStatusTransition(buffering: false, bufferingStartTime: 0)
        )
    }

    func testBufferingStatusTransitionRejectsMalformedValues() {
        let cases: [
            (
                buffered: TimeInterval,
                minimum: TimeInterval,
                start: TimeInterval,
                now: TimeInterval
            )
        ] = [
            (.nan, 1.5, 10, 12),
            (-1, 1.5, 10, 12),
            (0.3, .infinity, 10, 12),
            (0.3, -1, 10, 12),
            (0.3, 1.5, .nan, 12),
            (0.3, 1.5, 10, .infinity)
        ]

        for item in cases {
            let transition =
                IRFFDecoder.bufferingStatusTransition(
                    buffering: true,
                    bufferedDuration: item.buffered,
                    endOfFile: false,
                    isLiveStream: false,
                    minBufferedDuration: item.minimum,
                    bufferingStartTime: item.start,
                    currentTime: item.now
                )
            XCTAssertTrue(transition.buffering)
            if item.start.isNaN {
                XCTAssertTrue(
                    transition.bufferingStartTime.isNaN
                )
            } else {
                XCTAssertEqual(
                    transition.bufferingStartTime,
                    item.start
                )
            }
        }
    }

    func testBufferingStatusTransitionRejectsElapsedOverflow() {
        XCTAssertEqual(
            IRFFDecoder.bufferingStatusTransition(
                buffering: true,
                bufferedDuration: 0.3,
                endOfFile: false,
                isLiveStream: false,
                minBufferedDuration: 1.5,
                bufferingStartTime:
                    -.greatestFiniteMagnitude,
                currentTime: .greatestFiniteMagnitude
            ),
            .init(
                buffering: true,
                bufferingStartTime:
                    -.greatestFiniteMagnitude
            )
        )
    }
}
