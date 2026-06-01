import XCTest
@testable import IRPlayer_swift

final class IRFFFramePoolTests: XCTestCase {

    func testDefaultPoolsCreateExpectedFrameTypesWithoutModuleNameLookup() {
        let videoFrame = IRFFFramePool.videoPool().getUnuseFrame()
        let audioFrame = IRFFFramePool.audioPool().getUnuseFrame()

        XCTAssertTrue(videoFrame is IRFFAVYUVVideoFrame)
        XCTAssertTrue(audioFrame is IRFFAudioFrame)
    }

    func testFramePoolReserveCapacityRejectsNegativeValues() {
        XCTAssertEqual(IRFFFramePool.reserveCapacity(from: 2), 2)
        XCTAssertEqual(IRFFFramePool.reserveCapacity(from: 0), 0)
        XCTAssertEqual(IRFFFramePool.reserveCapacity(from: -1), 0)
    }

    func testFrameCompatibilityRequiresMatchingFrameClass() {
        XCTAssertFalse(IRFFFramePool.isFrame(nil, compatibleWith: IRFFAudioFrame.self))
        XCTAssertTrue(IRFFFramePool.isFrame(IRFFAudioFrame(), compatibleWith: IRFFAudioFrame.self))
        XCTAssertFalse(IRFFFramePool.isFrame(IRFFAVYUVVideoFrame(), compatibleWith: IRFFAudioFrame.self))
    }

    func testFramePoolMovesFramesThroughUsedPlayingAndUnuseBuckets() throws {
        let pool = IRFFFramePool.pool(withCapacity: 2, frameClassName: IRFFFrame.self)
        let frame = try XCTUnwrap(pool.getUnuseFrame())

        XCTAssertEqual(pool.usedCount, 1)
        XCTAssertEqual(pool.unuseCount, 0)

        frame.startPlaying()
        XCTAssertEqual(pool.usedCount, 0)
        XCTAssertEqual(pool.unuseCount, 0)
        XCTAssertTrue(pool.playingFrame === frame)

        frame.stopPlaying()
        XCTAssertNil(pool.playingFrame)
        XCTAssertEqual(pool.usedCount, 0)
        XCTAssertEqual(pool.unuseCount, 1)
    }

    func testFlushReturnsUsedAndPlayingFramesToUnuseBucket() throws {
        let pool = IRFFFramePool.pool(withCapacity: 2, frameClassName: IRFFFrame.self)
        let usedFrame = try XCTUnwrap(pool.getUnuseFrame())
        let playingFrame = try XCTUnwrap(pool.getUnuseFrame())

        playingFrame.startPlaying()
        pool.flush()

        XCTAssertNil(pool.playingFrame)
        XCTAssertEqual(pool.usedCount, 0)
        XCTAssertEqual(pool.unuseCount, 2)
        XCTAssertEqual(pool.count, 2)
        XCTAssertTrue(pool.unuseFrames.contains(usedFrame))
        XCTAssertTrue(pool.unuseFrames.contains(playingFrame))
    }

    func testSetFrameUnuseClearsMatchingPlayingFrame() throws {
        let pool = IRFFFramePool.pool(withCapacity: 1, frameClassName: IRFFFrame.self)
        let frame = try XCTUnwrap(pool.getUnuseFrame())

        frame.startPlaying()
        pool.setFrameUnuse(frame)

        XCTAssertNil(pool.playingFrame)
        XCTAssertEqual(pool.usedCount, 0)
        XCTAssertEqual(pool.unuseCount, 1)
    }

    func testSetFramesUnuseClearsMatchingPlayingFrame() throws {
        let pool = IRFFFramePool.pool(withCapacity: 2, frameClassName: IRFFFrame.self)
        let usedFrame = try XCTUnwrap(pool.getUnuseFrame())
        let playingFrame = try XCTUnwrap(pool.getUnuseFrame())

        playingFrame.startPlaying()
        pool.setFramesUnuse([usedFrame, playingFrame])

        XCTAssertNil(pool.playingFrame)
        XCTAssertEqual(pool.usedCount, 0)
        XCTAssertEqual(pool.unuseCount, 2)
        XCTAssertTrue(pool.unuseFrames.contains(usedFrame))
        XCTAssertTrue(pool.unuseFrames.contains(playingFrame))
    }
}
