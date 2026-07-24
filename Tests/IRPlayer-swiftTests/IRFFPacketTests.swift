import IRFFMpeg
import XCTest
@testable import IRPlayer_swift

final class IRFFPacketTests: XCTestCase {
    func testEmptyOwnerRejectsBorrowAndClosesExactlyOnce() {
        let events = LockedPacketTestValue<[String]>([])
        let packet = IRFFPacket(
            runtime: makePacketTestRuntime(
                events: events
            )
        )
        var borrowRan = false

        XCTAssertNil(packet.snapshot)
        XCTAssertFalse(
            packet.withPacket { _ in
                borrowRan = true
                return true
            }
        )
        XCTAssertFalse(borrowRan)
        XCTAssertTrue(packet.close())
        XCTAssertFalse(packet.close())
        XCTAssertEqual(events.value, ["unref-0"])
    }

    func testOwnerMovesSourceAndClosesExactlyOnce() {
        let events = LockedPacketTestValue<[String]>([])
        let runtime = makePacketTestRuntime(events: events)
        var source = AVPacket()
        source.stream_index = 3
        source.size = 24
        source.duration = 250

        let packet = IRFFPacket(
            consuming: &source,
            runtime: runtime
        )

        XCTAssertEqual(source.stream_index, 0)
        XCTAssertEqual(source.size, 0)
        XCTAssertEqual(
            packet.snapshot,
            .init(
                streamIndex: 3,
                size: 24,
                duration: 250,
                presentationTimestamp: 0,
                decodeTimestamp: 0,
                hasData: false
            )
        )
        XCTAssertTrue(packet.close())
        XCTAssertFalse(packet.close())
        XCTAssertEqual(events.value, ["move", "unref-3"])
        XCTAssertEqual(
            packet.diagnostics,
            .init(
                phase: .closed,
                hasData: false
            )
        )
    }

    func testFillPublishesOneReadyGeneration() {
        let events = LockedPacketTestValue<[String]>([])
        let packet = IRFFPacket(
            runtime: makePacketTestRuntime(
                events: events
            )
        )
        var secondFillRan = false

        XCTAssertEqual(
            packet.fill { rawPacket in
                rawPacket.stream_index = 4
                rawPacket.size = 32
                rawPacket.duration = 500
                return 0
            },
            0
        )
        XCTAssertEqual(
            packet.fill { _ in
                secondFillRan = true
                return 0
            },
            -1
        )

        XCTAssertFalse(secondFillRan)
        XCTAssertEqual(packet.snapshot?.streamIndex, 4)
        XCTAssertEqual(packet.snapshot?.size, 32)
        XCTAssertEqual(packet.snapshot?.duration, 500)
        XCTAssertEqual(packet.diagnostics.phase, .ready)
        XCTAssertTrue(packet.close())
        XCTAssertEqual(events.value, ["unref-4"])
    }

    func testFailedFillReleasesPartialStateAndCloses() {
        let events = LockedPacketTestValue<[String]>([])
        let packet = IRFFPacket(
            runtime: makePacketTestRuntime(
                events: events
            )
        )

        XCTAssertEqual(
            packet.fill { rawPacket in
                rawPacket.stream_index = 5
                rawPacket.size = 64
                return -7
            },
            -7
        )

        XCTAssertNil(packet.snapshot)
        XCTAssertEqual(packet.diagnostics.phase, .closed)
        XCTAssertFalse(packet.close())
        XCTAssertEqual(events.value, ["unref-5"])
    }

    func testConcurrentCloseReleasesExactlyOnce() {
        let events = LockedPacketTestValue<[String]>([])
        var source = AVPacket()
        source.stream_index = 7
        let packet = IRFFPacket(
            consuming: &source,
            runtime: makePacketTestRuntime(
                events: events
            )
        )
        let closeOwners = LockedPacketTestValue(0)

        DispatchQueue.concurrentPerform(iterations: 100) { _ in
            if packet.close() {
                closeOwners.withValue { $0 += 1 }
            }
        }

        XCTAssertEqual(closeOwners.value, 1)
        XCTAssertEqual(events.value, ["move", "unref-7"])
    }

    func testCloseWaitsForScopedBorrow() {
        let events = LockedPacketTestValue<[String]>([])
        var source = AVPacket()
        source.stream_index = 8
        let packet = IRFFPacket(
            consuming: &source,
            runtime: makePacketTestRuntime(
                events: events
            )
        )
        let borrowStarted = DispatchSemaphore(value: 0)
        let releaseBorrow = DispatchSemaphore(value: 0)
        let borrowFinished = DispatchSemaphore(value: 0)
        let closeFinished = DispatchSemaphore(value: 0)

        DispatchQueue.global().async {
            packet.withPacket { borrowedPacket in
                XCTAssertEqual(
                    borrowedPacket.stream_index,
                    8
                )
                borrowStarted.signal()
                releaseBorrow.wait()
                return true
            }
            borrowFinished.signal()
        }
        XCTAssertEqual(
            borrowStarted.wait(timeout: .now() + 1),
            .success
        )

        DispatchQueue.global().async {
            packet.close()
            closeFinished.signal()
        }
        XCTAssertEqual(
            closeFinished.wait(timeout: .now() + 0.05),
            .timedOut
        )

        releaseBorrow.signal()
        XCTAssertEqual(
            borrowFinished.wait(timeout: .now() + 1),
            .success
        )
        XCTAssertEqual(
            closeFinished.wait(timeout: .now() + 1),
            .success
        )
        XCTAssertEqual(events.value, ["move", "unref-8"])
    }

    func testDeinitClosesReadyReference() {
        let events = LockedPacketTestValue<[String]>([])

        autoreleasepool {
            var source = AVPacket()
            source.stream_index = 9
            _ = IRFFPacket(
                consuming: &source,
                runtime: makePacketTestRuntime(
                    events: events
                )
            )
        }

        XCTAssertEqual(events.value, ["move", "unref-9"])
    }
}

func makePacketTestRuntime(
    events: LockedPacketTestValue<[String]>
) -> IRFFPacketRuntime {
    IRFFPacketRuntime(
        moveReference: { destination, source in
            events.withValue { $0.append("move") }
            destination = source
            source = AVPacket()
        },
        unreference: { packet in
            events.withValue {
                $0.append(
                    "unref-\(packet.stream_index)"
                )
            }
            packet = AVPacket()
        }
    )
}

final class LockedPacketTestValue<Value>:
    @unchecked Sendable
{
    private let lock = NSLock()
    private var storage: Value

    init(_ value: Value) {
        storage = value
    }

    var value: Value {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func withValue(
        _ body: (inout Value) -> Void
    ) {
        lock.lock()
        body(&storage)
        lock.unlock()
    }
}
