import XCTest
@testable import IRPlayer_swift

final class IRFFDecoderPacketPolicyTests: XCTestCase {

    func testPacketBufferBackpressureSleepIntervalUsesConfiguredThresholdAndPauseState() {
        XCTAssertNil(
            IRFFDecoderPacketPolicy.packetBufferBackpressureSleepInterval(
                audioSize: 3,
                videoPacketSize: 6,
                maxBufferSize: 10,
                paused: false
            )
        )
        XCTAssertEqual(
            IRFFDecoderPacketPolicy.packetBufferBackpressureSleepInterval(
                audioSize: 4,
                videoPacketSize: 6,
                maxBufferSize: 10,
                paused: false
            ),
            0.1
        )
        XCTAssertEqual(
            IRFFDecoderPacketPolicy.packetBufferBackpressureSleepInterval(
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
            IRFFDecoderPacketPolicy.packetBufferBackpressureSleepInterval(
                audioSize: -1,
                videoPacketSize: 6,
                maxBufferSize: 10,
                paused: false
            )
        )
        XCTAssertNil(
            IRFFDecoderPacketPolicy.packetBufferBackpressureSleepInterval(
                audioSize: 4,
                videoPacketSize: -1,
                maxBufferSize: 10,
                paused: false
            )
        )
        XCTAssertNil(
            IRFFDecoderPacketPolicy.packetBufferBackpressureSleepInterval(
                audioSize: 4,
                videoPacketSize: 6,
                maxBufferSize: 0,
                paused: false
            )
        )
    }

    func testReadPacketEOFTransitionOnlyAppliesForNegativeReadResults() {
        XCTAssertNil(IRFFDecoderPacketPolicy.readPacketEOFTransition(readFrameResult: 0))
        XCTAssertNil(IRFFDecoderPacketPolicy.readPacketEOFTransition(readFrameResult: 1))
        XCTAssertEqual(
            IRFFDecoderPacketPolicy.readPacketEOFTransition(readFrameResult: nil),
            IRFFDecoder.ReadPacketEOFTransition(
                endOfFile: true,
                videoEndOfFile: true,
                shouldFinishReadLoop: true,
                shouldNotifyDelegate: true
            )
        )
        XCTAssertEqual(
            IRFFDecoderPacketPolicy.readPacketEOFTransition(readFrameResult: -1),
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
            IRFFDecoderPacketPolicy.packetRoute(streamIndex: 2, videoTrackIndex: 2, audioTrackIndex: 3),
            .video
        )
        XCTAssertEqual(
            IRFFDecoderPacketPolicy.packetRoute(streamIndex: 3, videoTrackIndex: 2, audioTrackIndex: 3),
            .audio
        )
        XCTAssertEqual(
            IRFFDecoderPacketPolicy.packetRoute(streamIndex: 4, videoTrackIndex: 2, audioTrackIndex: 3),
            .ignored
        )
        XCTAssertEqual(
            IRFFDecoderPacketPolicy.packetRoute(streamIndex: 0, videoTrackIndex: nil, audioTrackIndex: nil),
            .ignored
        )
    }
}
