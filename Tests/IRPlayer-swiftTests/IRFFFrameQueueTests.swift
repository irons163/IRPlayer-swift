//
//  IRFFFrameQueueTests.swift
//  IRPlayer-swiftTests
//
//  Created by Codex on 2026/5/24.
//

import Foundation
import XCTest
#if SWIFT_PACKAGE
@testable import IRPlayerSwift
#else
@testable import IRPlayer_swift
#endif

final class IRFFFrameQueueTests: XCTestCase {
    private final class CancelProbe:
        NSObject,
        IRFFFrameDelegate
    {
        private let lock = NSLock()
        private var storedCancelCount = 0
        var onCancel: (() -> Void)?

        var cancelCount: Int {
            lock.lock()
            defer { lock.unlock() }
            return storedCancelCount
        }

        func frameDidStartPlaying(_ frame: IRFFFrame) {}
        func frameDidStopPlaying(_ frame: IRFFFrame) {}

        func frameDidCancel(_ frame: IRFFFrame) {
            lock.lock()
            storedCancelCount += 1
            let action = onCancel
            lock.unlock()
            action?()
        }
    }

    private final class ResultBox:
        @unchecked Sendable
    {
        private let lock = NSLock()
        private var frames: [IRFFFrame?] = []

        func append(_ frame: IRFFFrame?) {
            lock.lock()
            frames.append(frame)
            lock.unlock()
        }

        var snapshot: [IRFFFrame?] {
            lock.lock()
            defer { lock.unlock() }
            return frames
        }
    }

    func testFrameTimePositionUsesCheckedTimestampAndTimebase() {
        XCTAssertEqual(
            IRFFFrameTime.position(
                timestamp: 120,
                timebase: 0.001
            ),
            0.12,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            IRFFFrameTime.position(
                timestamp: Int64.min,
                timebase: 0.001
            ),
            0
        )
        XCTAssertEqual(
            IRFFFrameTime.position(
                timestamp: 120,
                timebase: 0
            ),
            0
        )
        XCTAssertEqual(
            IRFFFrameTime.position(
                timestamp: 120,
                timebase: .nan
            ),
            0
        )
        XCTAssertEqual(
            IRFFFrameTime.position(
                timestamp: Int64.max,
                timebase: .greatestFiniteMagnitude
            ),
            0
        )
    }

    func testFrameTimePacketPositionPrefersPTSAndFallsBackToDTS() {
        XCTAssertEqual(
            IRFFFrameTime.packetPosition(
                pts: 120,
                dts: 240,
                timebase: 0.001
            ),
            0.12,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            IRFFFrameTime.packetPosition(
                pts: Int64.min,
                dts: 240,
                timebase: 0.001
            ),
            0.24,
            accuracy: 0.0001
        )
    }

    func testFIFOAdmissionTracksAndTransfersCapturedAccounting() {
        let queue = IRFFFrameQueue()
        let first = makeFrame(
            position: 0,
            duration: 0.25,
            size: 10
        )
        let second = makeFrame(
            position: 1,
            duration: 0.5,
            size: 20
        )

        XCTAssertEqual(queue.enqueue(first), .accepted)
        XCTAssertEqual(queue.enqueue(second), .accepted)
        var diagnostics = queue.diagnostics
        XCTAssertEqual(diagnostics.phase, .open)
        XCTAssertEqual(diagnostics.count, 2)
        XCTAssertEqual(
            diagnostics.duration,
            0.75,
            accuracy: 0.0001
        )
        XCTAssertEqual(diagnostics.size, 30)

        XCTAssertTrue(queue.dequeue() === first)
        diagnostics = queue.diagnostics
        XCTAssertEqual(diagnostics.count, 1)
        XCTAssertEqual(
            diagnostics.duration,
            0.5,
            accuracy: 0.0001
        )
        XCTAssertEqual(diagnostics.size, 20)
        XCTAssertTrue(queue.waitForFrame() === second)
        XCTAssertEqual(queue.diagnostics.count, 0)
        XCTAssertEqual(queue.diagnostics.duration, 0)
        XCTAssertEqual(queue.diagnostics.size, 0)
    }

    func testAdmissionFreezesAccountingAgainstLaterFrameMutation() {
        let queue = IRFFFrameQueue()
        let frame = makeFrame(
            position: 1,
            duration: 0.25,
            size: 10
        )
        XCTAssertEqual(queue.enqueue(frame), .accepted)

        frame.position = 100
        frame.duration = 50
        frame.size = Int.max

        XCTAssertEqual(queue.count, 1)
        XCTAssertEqual(queue.duration, 0.25)
        XCTAssertEqual(queue.size, 10)
        XCTAssertTrue(queue.dequeue() === frame)
        XCTAssertEqual(queue.duration, 0)
        XCTAssertEqual(queue.size, 0)
    }

    func testSortedAdmissionUsesCapturedAscendingPosition() {
        let queue = IRFFFrameQueue()
        let later = makeFrame(
            position: 3,
            duration: 0.1,
            size: 1
        )
        let earlier = makeFrame(
            position: 1,
            duration: 0.1,
            size: 1
        )
        let middle = makeFrame(
            position: 2,
            duration: 0.1,
            size: 1
        )

        queue.enqueueSorted(later)
        later.position = -100
        queue.enqueueSorted(earlier)
        queue.enqueueSorted(middle)

        XCTAssertTrue(queue.dequeue() === earlier)
        XCTAssertTrue(queue.dequeue() === middle)
        XCTAssertTrue(queue.dequeue() === later)
    }

    func testSortedAdmissionIsStableForEqualAndNonFinitePositions() {
        let queue = IRFFFrameQueue()
        let first = makeFrame(
            position: 1,
            duration: 0.1,
            size: 1
        )
        let second = makeFrame(
            position: 1,
            duration: 0.1,
            size: 1
        )
        let malformed1 = makeFrame(
            position: .nan,
            duration: 0.1,
            size: 1
        )
        let malformed2 = makeFrame(
            position: .infinity,
            duration: 0.1,
            size: 1
        )

        queue.enqueueSorted(first)
        queue.enqueueSorted(malformed1)
        queue.enqueueSorted(second)
        queue.enqueueSorted(malformed2)

        XCTAssertTrue(queue.dequeue() === first)
        XCTAssertTrue(queue.dequeue() === second)
        XCTAssertTrue(queue.dequeue() === malformed1)
        XCTAssertTrue(queue.dequeue() === malformed2)
    }

    func testNegativeAndNonFiniteAccountingContributesZero() {
        let queue = IRFFFrameQueue()
        let negative = makeFrame(
            position: 0,
            duration: -1,
            size: -10
        )
        let infinite = makeFrame(
            position: 1,
            duration: .infinity,
            size: 10
        )

        XCTAssertEqual(queue.enqueue(negative), .accepted)
        XCTAssertEqual(queue.enqueue(infinite), .accepted)
        XCTAssertEqual(queue.count, 2)
        XCTAssertEqual(queue.duration, 0)
        XCTAssertEqual(queue.size, 10)
    }

    func testSizeOverflowRejectsAndReturnsOfferedFrame() {
        let queue = IRFFFrameQueue()
        let retained = makeFrame(
            position: 0,
            duration: 0,
            size: Int.max
        )
        let rejected = makeFrame(
            position: 1,
            duration: 0,
            size: 1
        )
        let probe = CancelProbe()
        rejected.delegate = probe

        XCTAssertEqual(queue.enqueue(retained), .accepted)
        XCTAssertEqual(
            queue.enqueue(rejected),
            .rejectedAccountingOverflow
        )
        XCTAssertEqual(probe.cancelCount, 1)
        XCTAssertEqual(queue.count, 1)
        XCTAssertEqual(queue.size, Int.max)
    }

    func testDurationOverflowRejectsAndReturnsOfferedFrame() {
        let queue = IRFFFrameQueue()
        let retained = makeFrame(
            position: 0,
            duration: .greatestFiniteMagnitude,
            size: 0
        )
        let rejected = makeFrame(
            position: 1,
            duration: .greatestFiniteMagnitude,
            size: 0
        )
        let probe = CancelProbe()
        rejected.delegate = probe

        XCTAssertEqual(queue.enqueue(retained), .accepted)
        XCTAssertEqual(
            queue.enqueue(rejected),
            .rejectedAccountingOverflow
        )
        XCTAssertEqual(probe.cancelCount, 1)
        XCTAssertEqual(
            queue.duration,
            .greatestFiniteMagnitude
        )
    }

    func testDuplicateAdmissionDoesNotCancelQueueOwnedIdentity() {
        let queue = IRFFFrameQueue()
        let frame = makeFrame(
            position: 0,
            duration: 0.1,
            size: 1
        )
        let probe = CancelProbe()
        frame.delegate = probe

        XCTAssertEqual(queue.enqueue(frame), .accepted)
        XCTAssertEqual(
            queue.enqueueSorted(frame),
            .rejectedDuplicate
        )
        XCTAssertEqual(probe.cancelCount, 0)
        XCTAssertEqual(queue.count, 1)

        XCTAssertEqual(queue.flush(), 1)
        XCTAssertEqual(probe.cancelCount, 1)
    }

    func testNilAdmissionHasNoOwnershipSideEffects() {
        let queue = IRFFFrameQueue()

        XCTAssertEqual(queue.enqueue(nil), .rejectedNil)
        XCTAssertEqual(queue.enqueueSorted(nil), .rejectedNil)
        XCTAssertEqual(queue.diagnostics.count, 0)
    }

    func testSynchronousFetchWakesWhenProducerSignals() {
        let queue = IRFFFrameQueue()
        let frame = makeFrame(
            position: 0,
            duration: 0.1,
            size: 1
        )
        let started = expectation(
            description: "consumer started"
        )
        let finished = expectation(
            description: "consumer finished"
        )
        let producerFinished = expectation(
            description: "producer finished"
        )
        let result = ResultBox()

        DispatchQueue.global(qos: .userInitiated).async {
            started.fulfill()
            result.append(queue.waitForFrame())
            finished.fulfill()
        }

        wait(for: [started], timeout: 1)
        DispatchQueue.global(qos: .userInitiated).async {
            queue.enqueue(frame)
            producerFinished.fulfill()
        }
        wait(
            for: [producerFinished, finished],
            timeout: 1
        )
        XCTAssertTrue(result.snapshot.first! === frame)
    }

    func testCloseWakesEveryWaiterAndIsTerminalRepeatable() {
        let queue = IRFFFrameQueue()
        let started = expectation(
            description: "consumers started"
        )
        started.expectedFulfillmentCount = 3
        let finished = expectation(
            description: "consumers finished"
        )
        finished.expectedFulfillmentCount = 3
        let result = ResultBox()
        let closeFinished = expectation(
            description: "close finished"
        )

        for _ in 0..<3 {
            DispatchQueue.global(qos: .userInitiated)
                .async {
                    started.fulfill()
                    result.append(queue.waitForFrame())
                    finished.fulfill()
                }
        }

        wait(for: [started], timeout: 1)
        DispatchQueue.global(qos: .userInitiated).async {
            queue.close()
            closeFinished.fulfill()
        }
        wait(for: [closeFinished], timeout: 1)
        XCTAssertFalse(queue.close())
        wait(for: [finished], timeout: 1)
        XCTAssertEqual(result.snapshot.count, 3)
        XCTAssertTrue(
            result.snapshot.allSatisfy { $0 == nil }
        )
        XCTAssertEqual(queue.diagnostics.phase, .closed)
    }

    func testFlushCancelsDrainedFramesAndRemainsOpen() {
        let queue = IRFFFrameQueue()
        let first = makeFrame(
            position: 0,
            duration: 0.25,
            size: 10
        )
        let second = makeFrame(
            position: 1,
            duration: 0.5,
            size: 20
        )
        let firstProbe = CancelProbe()
        let secondProbe = CancelProbe()
        first.delegate = firstProbe
        second.delegate = secondProbe
        queue.enqueue(first)
        queue.enqueue(second)

        XCTAssertEqual(queue.flush(), 2)
        XCTAssertEqual(queue.flush(), 0)
        XCTAssertEqual(firstProbe.cancelCount, 1)
        XCTAssertEqual(secondProbe.cancelCount, 1)
        XCTAssertEqual(queue.diagnostics.phase, .open)
        XCTAssertEqual(queue.count, 0)

        let replacement = IRFFFrame()
        XCTAssertEqual(
            queue.enqueue(replacement),
            .accepted
        )
        XCTAssertTrue(
            queue.dequeue() === replacement
        )
    }

    func testQueueDrainReturnsLeasedFrameToItsPool() throws {
        let pool = IRFFFramePool(
            capacity: 1,
            frameClassName: IRFFFrame.self
        )
        let queue = IRFFFrameQueue()
        let frame = try XCTUnwrap(pool.leaseFrame())
        XCTAssertEqual(pool.diagnostics.leasedCount, 1)
        XCTAssertEqual(queue.enqueue(frame), .accepted)

        XCTAssertEqual(queue.flush(), 1)

        XCTAssertEqual(pool.diagnostics.leasedCount, 0)
        XCTAssertEqual(pool.diagnostics.availableCount, 1)
        XCTAssertTrue(pool.leaseFrame() === frame)
    }

    func testFlushDeliversCancellationOutsideQueueLock() {
        let queue = IRFFFrameQueue()
        let drained = IRFFFrame()
        let replacement = IRFFFrame()
        let probe = CancelProbe()
        probe.onCancel = {
            XCTAssertEqual(
                queue.enqueue(replacement),
                .accepted
            )
        }
        drained.delegate = probe
        queue.enqueue(drained)

        XCTAssertEqual(queue.flush(), 1)
        XCTAssertEqual(probe.cancelCount, 1)
        XCTAssertTrue(
            queue.dequeue() === replacement
        )
    }

    func testCloseDrainsAndRejectsFutureOwnership() {
        let queue = IRFFFrameQueue()
        let queued = IRFFFrame()
        let late = IRFFFrame()
        let queuedProbe = CancelProbe()
        let lateProbe = CancelProbe()
        queued.delegate = queuedProbe
        late.delegate = lateProbe
        queue.enqueue(queued)

        XCTAssertTrue(queue.close())
        XCTAssertEqual(queuedProbe.cancelCount, 1)
        XCTAssertEqual(
            queue.enqueue(late),
            .rejectedClosed
        )
        XCTAssertEqual(lateProbe.cancelCount, 1)
        XCTAssertNil(queue.dequeue())
        XCTAssertNil(queue.waitForFrame())
        XCTAssertEqual(queue.count, 0)
        XCTAssertEqual(queue.duration, 0)
        XCTAssertEqual(queue.size, 0)
    }

    func testDeinitDrainsQueueOwnedFrames() {
        let frame = IRFFFrame()
        let probe = CancelProbe()
        frame.delegate = probe
        var queue: IRFFFrameQueue? = IRFFFrameQueue()
        queue?.enqueue(frame)

        queue = nil

        XCTAssertEqual(probe.cancelCount, 1)
    }

    func testConcurrentMutationAndSnapshotsRemainCoherent() {
        let queue = IRFFFrameQueue()
        let workers = DispatchGroup()
        let workQueue = DispatchQueue(
            label: "IRFFFrameQueueTests.concurrent",
            attributes: .concurrent
        )
        let resultLock = NSLock()
        var observedInvalidSnapshot = false

        for worker in 0..<4 {
            workers.enter()
            workQueue.async {
                for iteration in 0..<400 {
                    let frame = self.makeFrame(
                        position: TimeInterval(iteration),
                        duration: 0.001,
                        size: worker + 1
                    )
                    queue.enqueue(frame)
                    let diagnostics = queue.diagnostics
                    if diagnostics.count < 0
                        || diagnostics.size < 0
                        || !diagnostics.duration.isFinite
                        || diagnostics.duration < 0 {
                        resultLock.lock()
                        observedInvalidSnapshot = true
                        resultLock.unlock()
                    }
                }
                workers.leave()
            }
        }

        workers.enter()
        workQueue.async {
            for _ in 0..<400 {
                queue.flush()
                _ = queue.diagnostics
            }
            workers.leave()
        }

        XCTAssertEqual(
            workers.wait(timeout: .now() + 5),
            .success
        )
        queue.flush()
        resultLock.lock()
        XCTAssertFalse(observedInvalidSnapshot)
        resultLock.unlock()
        XCTAssertEqual(
            queue.diagnostics,
            .init(
                phase: .open,
                count: 0,
                duration: 0,
                size: 0,
                revision: queue.diagnostics.revision
            )
        )
    }

    private func makeFrame(
        position: TimeInterval,
        duration: TimeInterval,
        size: Int
    ) -> IRFFFrame {
        let frame = IRFFFrame()
        frame.position = position
        frame.duration = duration
        frame.size = size
        return frame
    }
}
