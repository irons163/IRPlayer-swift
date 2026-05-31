import XCTest
@testable import IRPlayer_swift

final class IRPlayerImpLazyPlayerTests: XCTestCase {

    func testPlayerVolumeConvertsFiniteValues() {
        XCTAssertEqual(IRPlayerVolume.normalizedFloat(from: 0.5), 0.5, accuracy: 0.0001)
    }

    func testPlayerVolumeDefaultsNilAndNonFiniteValuesToZero() {
        XCTAssertEqual(IRPlayerVolume.normalizedFloat(from: nil), 0)
        XCTAssertEqual(IRPlayerVolume.normalizedFloat(from: .nan), 0)
        XCTAssertEqual(IRPlayerVolume.normalizedFloat(from: .infinity), 0)
    }

    func testLazyPlayerFactoriesReturnExistingPlayersOrCreateNewOnes() {
        let abstractPlayer = IRPlayerImp.player()

        let existingAVPlayer = IRAVPlayer(abstractPlayer: abstractPlayer)
        XCTAssertTrue(IRPlayerImp.makeAVPlayerIfNeeded(existingAVPlayer, abstractPlayer: abstractPlayer) === existingAVPlayer)

        let createdAVPlayer = IRPlayerImp.makeAVPlayerIfNeeded(nil, abstractPlayer: abstractPlayer)
        XCTAssertTrue(createdAVPlayer.abstractPlayer === abstractPlayer)

        let existingFFPlayer = IRFFPlayer.player(with: abstractPlayer)
        XCTAssertTrue(IRPlayerImp.makeFFPlayerIfNeeded(existingFFPlayer, abstractPlayer: abstractPlayer) === existingFFPlayer)

        let createdFFPlayer = IRPlayerImp.makeFFPlayerIfNeeded(nil, abstractPlayer: abstractPlayer)
        XCTAssertTrue(createdFFPlayer.abstractPlayer === abstractPlayer)

        withExtendedLifetime((existingAVPlayer, createdAVPlayer, existingFFPlayer, createdFFPlayer, abstractPlayer)) {}
    }

    func testScrollToBoundsDoesNotPrintDebugOutput() {
        let player = IRPlayerImp.player()

        let output = captureStandardOutput {
            player.glViewDidScroll(toBounds: nil)
        }

        XCTAssertEqual(output, "")
        withExtendedLifetime(player) {}
    }

    func testReleaseDoesNotPrintDebugOutput() {
        var player: IRPlayerImp? = IRPlayerImp.player()
        XCTAssertNotNil(player)

        let output = captureStandardOutput {
            player = nil
        }

        XCTAssertEqual(output, "")
    }
}
