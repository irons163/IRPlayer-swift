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

}
