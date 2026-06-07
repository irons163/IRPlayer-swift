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

    func testPacketQueueIgnoresNonFiniteFallbackDurations() {
        let queue = IRFFPacketQueue.packetQueue(withTimebase: 0.001)
        let malformed = makePacket(size: 10, duration: 0)
        let valid = makePacket(size: 20, duration: 0)

        queue.putPacket(malformed, duration: .infinity)
        queue.putPacket(valid, duration: 0.5)

        XCTAssertEqual(queue.duration, 0.5, accuracy: 0.0001)
        XCTAssertEqual(queue.size, 30)

        _ = queue.getPacket()

        XCTAssertEqual(queue.duration, 0.5, accuracy: 0.0001)
        XCTAssertEqual(queue.size, 20)
    }

    func testPacketQueueFlushClearsQueuedPacketsAndAccounting() {
        let queue = IRFFPacketQueue.packetQueue(withTimebase: 0.001)

        queue.putPacket(makePacket(size: 10, duration: 250), duration: 10)
        queue.putPacket(makePacket(size: 20, duration: 500), duration: 10)
        queue.flush()

        XCTAssertEqual(queue.count, 0)
        XCTAssertEqual(queue.duration, 0, accuracy: 0.0001)
        XCTAssertEqual(queue.size, 0)
    }

    func testPacketQueueDestroyUnblocksEmptyFetchAndIgnoresFuturePackets() {
        let queue = IRFFPacketQueue.packetQueue(withTimebase: 0.001)

        queue.destroy()
        let packet = queue.getPacket()
        queue.putPacket(makePacket(size: 10, duration: 250), duration: 10)

        XCTAssertEqual(packet.stream_index, -2)
        XCTAssertEqual(queue.count, 0)
        XCTAssertEqual(queue.duration, 0, accuracy: 0.0001)
        XCTAssertEqual(queue.size, 0)
    }

    func testGetPacketWaitsUntilPacketIsEnqueued() {
        let queue = IRFFPacketQueue.packetQueue(withTimebase: 0.001)
        let completion = expectation(description: "getPacket returns after packet is enqueued")
        let lock = NSLock()
        var returnedPacket: AVPacket?
        defer { queue.destroy() }

        DispatchQueue.global().async {
            let packet = queue.getPacket()
            lock.lock()
            returnedPacket = packet
            lock.unlock()
            completion.fulfill()
        }

        Thread.sleep(forTimeInterval: 0.05)
        queue.putPacket(makePacket(size: 12, duration: 250), duration: 10)

        wait(for: [completion], timeout: 1)

        lock.lock()
        let packet = returnedPacket
        lock.unlock()

        XCTAssertEqual(packet?.size, 12)
        XCTAssertEqual(queue.count, 0)
        XCTAssertEqual(queue.duration, 0, accuracy: 0.0001)
        XCTAssertEqual(queue.size, 0)
    }

    func testAccountedDurationUsesPacketDurationOnlyWithValidTimebase() {
        let packet = makePacket(size: 10, duration: 250)

        XCTAssertEqual(
            IRFFPacketQueue.accountedDuration(for: packet, fallbackDuration: 10, timebase: 0.001),
            0.25,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            IRFFPacketQueue.accountedDuration(for: packet, fallbackDuration: 10, timebase: 0),
            10,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            IRFFPacketQueue.accountedDuration(for: packet, fallbackDuration: 10, timebase: .nan),
            10,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            IRFFPacketQueue.accountedDuration(for: makePacket(size: 10, duration: Int64.max),
                                              fallbackDuration: 10,
                                              timebase: .greatestFiniteMagnitude),
            0,
            accuracy: 0.0001
        )
    }

    func testStaticPolicyWrappersRemainSourceCompatible() {
        let packet = makePacket(size: 10, duration: 250)
        let malformed = makePacket(size: -10, duration: 0)

        XCTAssertEqual(
            IRFFPacketQueue.accountedDuration(for: packet, fallbackDuration: 10, timebase: 0.001),
            IRFFPacketQueuePolicy.accountedDuration(for: packet, fallbackDuration: 10, timebase: 0.001),
            accuracy: 0.0001
        )
        XCTAssertEqual(
            IRFFPacketQueue.accountedDuration(for: malformed, fallbackDuration: 0.5, timebase: .nan),
            IRFFPacketQueuePolicy.accountedDuration(for: malformed, fallbackDuration: 0.5, timebase: .nan),
            accuracy: 0.0001
        )
        XCTAssertEqual(IRFFPacketQueue.accountedSize(for: packet), IRFFPacketQueuePolicy.accountedSize(for: packet))
        XCTAssertEqual(IRFFPacketQueue.accountedSize(for: malformed), IRFFPacketQueuePolicy.accountedSize(for: malformed))
    }

    private func makePacket(size: Int32, duration: Int64) -> AVPacket {
        var packet = AVPacket()
        packet.size = size
        packet.duration = duration
        return packet
    }
}
