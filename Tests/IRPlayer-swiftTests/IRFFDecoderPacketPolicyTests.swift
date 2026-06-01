import XCTest
@testable import IRPlayer_swift

final class IRFFDecoderPacketPolicyTests: XCTestCase {

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
}
