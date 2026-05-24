import XCTest
@testable import IRPlayer_swift

final class IRPlayerImpLazyPlayerTests: XCTestCase {

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
}
