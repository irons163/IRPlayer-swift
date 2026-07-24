//
//  IRFFPacketQueueTests.swift
//  IRPlayer-swiftTests
//
//  Created by Codex on 2026/5/24.
//

import IRFFMpeg
import XCTest
#if SWIFT_PACKAGE
@testable import IRPlayerSwift
#else
@testable import IRPlayer_swift
#endif

final class IRFFPacketQueueTests: XCTestCase {
    func testPacketQueueSubtractsFallbackDurationWhenPacketDurationIsMissing() {
        let queue = IRFFPacketQueue.packetQueue(
            withTimebase: 0.001
        )

        queue.putPacket(
            makePacket(size: 10, duration: 0),
            duration: 0.25
        )
        queue.putPacket(
            makePacket(size: 20, duration: 0),
            duration: 0.5
        )

        XCTAssertEqual(queue.duration, 0.75, accuracy: 0.0001)
        XCTAssertEqual(queue.size, 30)

        let dequeued = packet(from: queue.getItem())

        XCTAssertEqual(dequeued?.snapshot?.size, 10)
        XCTAssertEqual(queue.duration, 0.5, accuracy: 0.0001)
        XCTAssertEqual(queue.size, 20)
    }

    func testPacketQueueUsesPacketDurationWhenPresent() {
        let queue = IRFFPacketQueue.packetQueue(
            withTimebase: 0.001
        )
        queue.putPacket(
            makePacket(size: 10, duration: 250),
            duration: 10
        )
        queue.putPacket(
            makePacket(size: 20, duration: 500),
            duration: 10
        )

        XCTAssertEqual(queue.duration, 0.75, accuracy: 0.0001)

        _ = queue.getItem()

        XCTAssertEqual(queue.duration, 0.5, accuracy: 0.0001)
        XCTAssertEqual(queue.size, 20)
    }

    func testPacketQueueIgnoresNegativePacketSizesForByteAccounting() {
        let queue = IRFFPacketQueue.packetQueue(
            withTimebase: 0.001
        )
        queue.putPacket(
            makePacket(size: -10, duration: 250),
            duration: 10
        )
        queue.putPacket(
            makePacket(size: 20, duration: 500),
            duration: 10
        )

        XCTAssertEqual(queue.size, 20)

        _ = queue.getItem()

        XCTAssertEqual(queue.size, 20)
    }

    func testPacketQueueIgnoresNonFiniteFallbackDurations() {
        let queue = IRFFPacketQueue.packetQueue(
            withTimebase: 0.001
        )
        queue.putPacket(
            makePacket(size: 10, duration: 0),
            duration: .infinity
        )
        queue.putPacket(
            makePacket(size: 20, duration: 0),
            duration: 0.5
        )

        XCTAssertEqual(queue.duration, 0.5, accuracy: 0.0001)
        XCTAssertEqual(queue.size, 30)

        _ = queue.getItem()

        XCTAssertEqual(queue.duration, 0.5, accuracy: 0.0001)
        XCTAssertEqual(queue.size, 20)
    }

    func testPacketQueueFlushClosesPacketsAndClearsAccounting() {
        let events = LockedPacketTestValue<[String]>([])
        let queue = IRFFPacketQueue.packetQueue(
            withTimebase: 0.001
        )
        queue.putPacket(
            makePacket(
                streamIndex: 10,
                size: 10,
                duration: 250,
                runtime: makePacketTestRuntime(
                    events: events
                )
            ),
            duration: 10
        )
        queue.putPacket(
            makePacket(
                streamIndex: 11,
                size: 20,
                duration: 500,
                runtime: makePacketTestRuntime(
                    events: events
                )
            ),
            duration: 10
        )

        queue.flush()

        XCTAssertEqual(
            events.value,
            [
                "move",
                "move",
                "unref-10",
                "unref-11"
            ]
        )
        XCTAssertEqual(queue.count, 0)
        XCTAssertEqual(queue.duration, 0, accuracy: 0.0001)
        XCTAssertEqual(queue.size, 0)
    }

    func testPacketQueueUsesTypedFlushAndClosedItems() {
        let queue = IRFFPacketQueue.packetQueue(
            withTimebase: 0.001
        )

        XCTAssertTrue(queue.putFlush())
        if case .flush = queue.getItem() {
            // Expected.
        } else {
            XCTFail("Expected a typed flush item")
        }

        queue.destroy()
        if case .closed = queue.getItem() {
            // Expected.
        } else {
            XCTFail("Expected a typed closed item")
        }
        XCTAssertFalse(queue.putFlush())
    }

    func testPacketQueueDestroyClosesQueuedAndRejectedPackets() {
        let events = LockedPacketTestValue<[String]>([])
        let runtime = makePacketTestRuntime(
            events: events
        )
        let queue = IRFFPacketQueue.packetQueue(
            withTimebase: 0.001
        )
        queue.putPacket(
            makePacket(
                streamIndex: 12,
                size: 10,
                duration: 250,
                runtime: runtime
            ),
            duration: 10
        )

        queue.destroy()
        let rejected = makePacket(
            streamIndex: 13,
            size: 20,
            duration: 500,
            runtime: runtime
        )

        XCTAssertFalse(
            queue.putPacket(
                rejected,
                duration: 10
            )
        )
        XCTAssertEqual(
            events.value,
            [
                "move",
                "unref-12",
                "move",
                "unref-13"
            ]
        )
        XCTAssertEqual(queue.count, 0)
        XCTAssertEqual(queue.duration, 0, accuracy: 0.0001)
        XCTAssertEqual(queue.size, 0)
    }

    func testGetItemWaitsUntilPacketIsEnqueued() {
        let queue = IRFFPacketQueue.packetQueue(
            withTimebase: 0.001
        )
        let completion = expectation(
            description: "getItem returns after enqueue"
        )
        let result = LockedPacketTestValue<
            IRFFPacketQueueItem?
        >(nil)
        defer { queue.destroy() }

        DispatchQueue.global().async {
            result.withValue {
                $0 = queue.getItem()
            }
            completion.fulfill()
        }

        Thread.sleep(forTimeInterval: 0.05)
        queue.putPacket(
            makePacket(size: 12, duration: 250),
            duration: 10
        )

        wait(for: [completion], timeout: 1)

        XCTAssertEqual(
            packet(from: result.value)?.snapshot?.size,
            12
        )
        XCTAssertEqual(queue.count, 0)
        XCTAssertEqual(queue.duration, 0, accuracy: 0.0001)
        XCTAssertEqual(queue.size, 0)
    }

    func testDestroyUnblocksWaitingConsumerWithClosedItem() {
        let queue = IRFFPacketQueue.packetQueue(
            withTimebase: 0.001
        )
        let result = LockedPacketTestValue<
            IRFFPacketQueueItem?
        >(nil)
        let consumerFinished = DispatchSemaphore(
            value: 0
        )

        DispatchQueue.global().async {
            result.withValue {
                $0 = queue.getItem()
            }
            consumerFinished.signal()
        }
        Thread.sleep(forTimeInterval: 0.05)

        queue.destroy()

        XCTAssertEqual(
            consumerFinished.wait(timeout: .now() + 1),
            .success
        )
        if case .closed = result.value {
            // Expected.
        } else {
            XCTFail("Expected destroy to unblock as closed")
        }
    }

    func testConcurrentMutationAndAccountingReadsRemainRaceFree() {
        let queue = IRFFPacketQueue.packetQueue(
            withTimebase: 0.001
        )
        let workers = DispatchGroup()
        let workQueue = DispatchQueue(
            label: "IRFFPacketQueueTests.concurrent",
            attributes: .concurrent
        )

        for worker in 0..<4 {
            workers.enter()
            workQueue.async {
                for iteration in 0..<500 {
                    queue.putPacket(
                        self.makePacket(
                            size: Int32(worker + 1),
                            duration: Int64(iteration + 1)
                        ),
                        duration: 0.001
                    )
                    _ = queue.count
                    _ = queue.size
                    _ = queue.duration
                }
                workers.leave()
            }
        }

        workers.enter()
        workQueue.async {
            for _ in 0..<500 {
                queue.flush()
                _ = queue.count
                _ = queue.size
                _ = queue.duration
            }
            workers.leave()
        }

        XCTAssertEqual(
            workers.wait(timeout: .now() + 5),
            .success
        )
        queue.flush()
        XCTAssertEqual(queue.count, 0)
        XCTAssertEqual(queue.size, 0)
        XCTAssertEqual(queue.duration, 0, accuracy: 0.0001)
    }

    func testAccountedDurationUsesPacketDurationOnlyWithValidTimebase() {
        let packet = makePacket(
            size: 10,
            duration: 250
        ).snapshot!

        XCTAssertEqual(
            IRFFPacketQueue.accountedDuration(
                for: packet,
                fallbackDuration: 10,
                timebase: 0.001
            ),
            0.25,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            IRFFPacketQueue.accountedDuration(
                for: packet,
                fallbackDuration: 10,
                timebase: 0
            ),
            10,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            IRFFPacketQueue.accountedDuration(
                for: packet,
                fallbackDuration: 10,
                timebase: .nan
            ),
            10,
            accuracy: 0.0001
        )
        let overflowing = makePacket(
            size: 10,
            duration: Int64.max
        ).snapshot!
        XCTAssertEqual(
            IRFFPacketQueue.accountedDuration(
                for: overflowing,
                fallbackDuration: 10,
                timebase: .greatestFiniteMagnitude
            ),
            0,
            accuracy: 0.0001
        )
    }

    private func packet(
        from item: IRFFPacketQueueItem?
    ) -> IRFFPacket? {
        guard case let .packet(packet) = item else {
            return nil
        }
        return packet
    }

    private func makePacket(
        streamIndex: Int32 = 0,
        size: Int32,
        duration: Int64,
        runtime: IRFFPacketRuntime = .live
    ) -> IRFFPacket {
        var packet = AVPacket()
        packet.stream_index = streamIndex
        packet.size = size
        packet.duration = duration
        return IRFFPacket(
            consuming: &packet,
            runtime: runtime
        )
    }

}
