//
//  IRFFPacketQueueTests.swift
//  IRPlayer-swiftTests
//
//  Created by Codex on 2026/5/24.
//

import IRFFMpeg
import XCTest
@testable import IRPlayer_swift

final class IRFFPacketQueueTests: XCTestCase {

    func testPacketQueueSubtractsFallbackDurationWhenPacketDurationIsMissing() {
        let queue = IRFFPacketQueue.packetQueue(withTimebase: 0.001)
        let first = makePacket(size: 10, duration: 0)
        let second = makePacket(size: 20, duration: 0)

        queue.putPacket(first, duration: 0.25)
        queue.putPacket(second, duration: 0.5)

        XCTAssertEqual(queue.duration, 0.75, accuracy: 0.0001)
        XCTAssertEqual(queue.size, 30)

        let dequeued = queue.getPacket()

        XCTAssertEqual(dequeued.size, 10)
        XCTAssertEqual(queue.duration, 0.5, accuracy: 0.0001)
        XCTAssertEqual(queue.size, 20)
    }

    func testPacketQueueUsesPacketDurationWhenPresent() {
        let queue = IRFFPacketQueue.packetQueue(withTimebase: 0.001)
        let first = makePacket(size: 10, duration: 250)
        let second = makePacket(size: 20, duration: 500)

        queue.putPacket(first, duration: 10)
        queue.putPacket(second, duration: 10)

        XCTAssertEqual(queue.duration, 0.75, accuracy: 0.0001)

        _ = queue.getPacket()

        XCTAssertEqual(queue.duration, 0.5, accuracy: 0.0001)
        XCTAssertEqual(queue.size, 20)
    }

    func testPacketQueueIgnoresNegativePacketSizesForByteAccounting() {
        let queue = IRFFPacketQueue.packetQueue(withTimebase: 0.001)
        let malformed = makePacket(size: -10, duration: 250)
        let valid = makePacket(size: 20, duration: 500)

        queue.putPacket(malformed, duration: 10)
        queue.putPacket(valid, duration: 10)

        XCTAssertEqual(queue.size, 20)

        _ = queue.getPacket()

        XCTAssertEqual(queue.size, 20)
    }

    private func makePacket(size: Int32, duration: Int64) -> AVPacket {
        var packet = AVPacket()
        packet.size = size
        packet.duration = duration
        return packet
    }
}
