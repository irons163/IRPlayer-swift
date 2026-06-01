//
//  IRFFFrameQueueTests.swift
//  IRPlayer-swiftTests
//
//  Created by Codex on 2026/5/24.
//

import Foundation
import XCTest
@testable import IRPlayer_swift

final class IRFFFrameQueueTests: XCTestCase {

    func testFrameTimePositionUsesFiniteTimestampAndTimebase() {
        XCTAssertEqual(IRFFFrameTime.position(timestamp: 120, timebase: 0.001), 0.12, accuracy: 0.0001)
    }

    func testFrameTimePositionDefaultsInvalidTimestampOrTimebaseToZero() {
        XCTAssertEqual(IRFFFrameTime.position(timestamp: Int64.min, timebase: 0.001), 0)
        XCTAssertEqual(IRFFFrameTime.position(timestamp: 120, timebase: 0), 0)
        XCTAssertEqual(IRFFFrameTime.position(timestamp: 120, timebase: .nan), 0)
    }

    func testFrameTimePacketPositionFallsBackFromMissingPTSToDTS() {
        XCTAssertEqual(
            IRFFFrameTime.packetPosition(pts: Int64.min, dts: 240, timebase: 0.001),
            0.24,
            accuracy: 0.0001
        )
    }

    func testFrameQueueTracksCountDurationAndSizeWhenPuttingAndFetchingFrames() {
        let queue = IRFFFrameQueue.frameQueue()
        let first = makeFrame(position: 0, duration: 0.25, size: 10)
        let second = makeFrame(position: 1, duration: 0.5, size: 20)

        queue.putFrame(first)
        queue.putFrame(second)

        XCTAssertEqual(queue.count, 2)
        XCTAssertEqual(queue.duration, 0.75, accuracy: 0.0001)
        XCTAssertEqual(queue.size, 30)

        XCTAssertTrue(queue.getFrameAsync() === first)
        XCTAssertEqual(queue.count, 1)
        XCTAssertEqual(queue.duration, 0.5, accuracy: 0.0001)
        XCTAssertEqual(queue.size, 20)
    }

    func testPutSortFrameReturnsFramesInAscendingPositionOrder() {
        let queue = IRFFFrameQueue.frameQueue()
        let later = makeFrame(position: 3, duration: 0.1, size: 1)
        let earlier = makeFrame(position: 1, duration: 0.1, size: 1)
        let middle = makeFrame(position: 2, duration: 0.1, size: 1)

        queue.putSortFrame(later)
        queue.putSortFrame(earlier)
        queue.putSortFrame(middle)

        XCTAssertTrue(queue.getFrameAsync() === earlier)
        XCTAssertTrue(queue.getFrameAsync() === middle)
        XCTAssertTrue(queue.getFrameAsync() === later)
    }

    func testPutSortFramePreservesInsertionOrderForEqualPositions() {
        let queue = IRFFFrameQueue.frameQueue()
        let first = makeFrame(position: 1, duration: 0.1, size: 1)
        let second = makeFrame(position: 1, duration: 0.1, size: 1)
        let third = makeFrame(position: 1, duration: 0.1, size: 1)

        queue.putSortFrame(first)
        queue.putSortFrame(second)
        queue.putSortFrame(third)

        XCTAssertTrue(queue.getFrameAsync() === first)
        XCTAssertTrue(queue.getFrameAsync() === second)
        XCTAssertTrue(queue.getFrameAsync() === third)
    }

    func testPutSortFrameKeepsNonFinitePositionsAfterFiniteFrames() {
        let queue = IRFFFrameQueue.frameQueue()
        let earlier = makeFrame(position: 1, duration: 0.1, size: 1)
        let malformed = makeFrame(position: .nan, duration: 0.1, size: 1)
        let later = makeFrame(position: 2, duration: 0.1, size: 1)

        queue.putSortFrame(earlier)
        queue.putSortFrame(malformed)
        queue.putSortFrame(later)

        XCTAssertTrue(queue.getFrameAsync() === earlier)
        XCTAssertTrue(queue.getFrameAsync() === later)
        XCTAssertTrue(queue.getFrameAsync() === malformed)
    }

    func testFrameQueueIgnoresNegativeFrameAccountingValues() {
        let queue = IRFFFrameQueue.frameQueue()
        let malformed = makeFrame(position: 0, duration: -1, size: -10)
        let valid = makeFrame(position: 1, duration: 0.5, size: 20)

        queue.putFrame(malformed)
        queue.putFrame(valid)

        XCTAssertEqual(queue.count, 2)
        XCTAssertEqual(queue.duration, 0.5, accuracy: 0.0001)
        XCTAssertEqual(queue.size, 20)
        XCTAssertTrue(queue.getFrameAsync() === malformed)
        XCTAssertEqual(queue.duration, 0.5, accuracy: 0.0001)
        XCTAssertEqual(queue.size, 20)
    }

    func testFrameQueueIgnoresNonFiniteFrameDurations() {
        let queue = IRFFFrameQueue.frameQueue()
        let malformed = makeFrame(position: 0, duration: .infinity, size: 10)
        let valid = makeFrame(position: 1, duration: 0.5, size: 20)

        queue.putFrame(malformed)
        queue.putFrame(valid)

        XCTAssertEqual(queue.duration, 0.5, accuracy: 0.0001)
        XCTAssertEqual(queue.size, 30)
        XCTAssertTrue(queue.getFrameAsync() === malformed)
        XCTAssertEqual(queue.duration, 0.5, accuracy: 0.0001)
        XCTAssertEqual(queue.size, 20)
    }

    private func makeFrame(position: TimeInterval, duration: TimeInterval, size: Int) -> IRFFFrame {
        let frame = IRFFFrame()
        frame.position = position
        frame.duration = duration
        frame.size = size
        return frame
    }
}
