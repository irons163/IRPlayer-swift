import Foundation
import XCTest
#if SWIFT_PACKAGE
@testable import IRPlayerSwift
#else
@testable import IRPlayer_swift
#endif

final class IRFFFramePoolTests: XCTestCase {
    private final class DelegateProbe:
        NSObject,
        IRFFFrameDelegate
    {
        struct Snapshot {
            let startCount: Int
            let stopCount: Int
            let cancelCount: Int
        }

        private let lock = NSLock()
        private var startCount = 0
        private var stopCount = 0
        private var cancelCount = 0

        var snapshot: Snapshot {
            lock.lock()
            defer { lock.unlock() }
            return Snapshot(
                startCount: startCount,
                stopCount: stopCount,
                cancelCount: cancelCount
            )
        }

        func frameDidStartPlaying(_ frame: IRFFFrame) {
            lock.lock()
            startCount += 1
            lock.unlock()
        }

        func frameDidStopPlaying(_ frame: IRFFFrame) {
            lock.lock()
            stopCount += 1
            lock.unlock()
        }

        func frameDidCancel(_ frame: IRFFFrame) {
            lock.lock()
            cancelCount += 1
            lock.unlock()
        }
    }

    private final class FrameBox:
        @unchecked Sendable
    {
        private let lock = NSLock()
        private var storedFrame: IRFFFrame?

        var frame: IRFFFrame? {
            lock.lock()
            defer { lock.unlock() }
            return storedFrame
        }

        func store(_ frame: IRFFFrame?) {
            lock.lock()
            storedFrame = frame
            lock.unlock()
        }
    }

    func testSpecializedFramesReportTypesAndArtwork() {
        let artwork = IRFFArtworkFrame()
        let picture = Data([1, 2, 3])
        artwork.picture = picture

        XCTAssertEqual(IRFFSubtitleFrame().type, .subtitle)
        XCTAssertEqual(artwork.type, .artwork)
        XCTAssertEqual(artwork.picture, picture)
    }

    func testFramePublishesCoherentTransportSnapshot() {
        let frame = IRFFFrame()
        frame.position = 1.25
        frame.duration = 0.5
        frame.size = 128

        XCTAssertEqual(
            frame.transportSnapshot(),
            IRFFFrameTransportSnapshot(
                position: 1.25,
                duration: 0.5,
                size: 128
            )
        )
    }

    func testFrameLifecycleUpdatesBeforeUnlockedDelegateDelivery() {
        let frame = IRFFFrame()
        let delegate = DelegateProbe()
        frame.delegate = delegate

        frame.startPlaying()
        XCTAssertTrue(frame.playing)
        frame.stopPlaying()
        XCTAssertFalse(frame.playing)
        frame.cancel()

        let snapshot = delegate.snapshot
        XCTAssertEqual(snapshot.startCount, 1)
        XCTAssertEqual(snapshot.stopCount, 1)
        XCTAssertEqual(snapshot.cancelCount, 1)
    }

    func testDefaultPoolsCreateExpectedFrameTypes() {
        let videoFrame =
            IRFFFramePool.videoPool().leaseFrame()
        let audioFrame =
            IRFFFramePool.audioPool().leaseFrame()

        XCTAssertTrue(videoFrame is IRFFAVYUVVideoFrame)
        XCTAssertTrue(audioFrame is IRFFAudioFrame)
    }

    func testPoolMovesOneOwnedFrameThroughExactBuckets()
        throws
    {
        let pool = makePool(capacity: 2)
        let frame = try XCTUnwrap(pool.leaseFrame())

        XCTAssertEqual(
            pool.diagnostics,
            .init(
                phase: .open,
                maximumCapacity: 2,
                availableCount: 0,
                leasedCount: 1,
                hasPlayingFrame: false,
                playingCount: 0,
                totalCount: 1,
                revision: 1
            )
        )

        frame.startPlaying()
        var diagnostics = pool.diagnostics
        XCTAssertEqual(diagnostics.availableCount, 0)
        XCTAssertEqual(diagnostics.leasedCount, 0)
        XCTAssertTrue(diagnostics.hasPlayingFrame)
        XCTAssertEqual(diagnostics.playingCount, 1)
        XCTAssertEqual(diagnostics.totalCount, 1)

        frame.stopPlaying()
        diagnostics = pool.diagnostics
        XCTAssertEqual(diagnostics.availableCount, 1)
        XCTAssertEqual(diagnostics.leasedCount, 0)
        XCTAssertFalse(diagnostics.hasPlayingFrame)
        XCTAssertEqual(diagnostics.totalCount, 1)
        XCTAssertFalse(frame.playing)
    }

    func testFlushNeverRevokesLeasedOrPlayingFrames()
        throws
    {
        let pool = makePool(capacity: 2)
        let leased = try XCTUnwrap(pool.leaseFrame())
        let playing = try XCTUnwrap(pool.leaseFrame())
        playing.startPlaying()

        XCTAssertEqual(pool.flush(), 0)

        var diagnostics = pool.diagnostics
        XCTAssertEqual(diagnostics.availableCount, 0)
        XCTAssertEqual(diagnostics.leasedCount, 1)
        XCTAssertTrue(diagnostics.hasPlayingFrame)
        XCTAssertEqual(diagnostics.playingCount, 1)
        XCTAssertEqual(diagnostics.totalCount, 2)
        XCTAssertTrue(playing.playing)

        XCTAssertNil(pool.leaseFrame())
        leased.cancel()
        let reusedFrame = try XCTUnwrap(pool.leaseFrame())
        XCTAssertTrue(reusedFrame === leased)
        XCTAssertFalse(reusedFrame === playing)
        reusedFrame.cancel()
        playing.stopPlaying()

        diagnostics = pool.diagnostics
        XCTAssertEqual(diagnostics.availableCount, 2)
        XCTAssertEqual(diagnostics.leasedCount, 0)
        XCTAssertEqual(diagnostics.playingCount, 0)

        let firstReuse = try XCTUnwrap(pool.leaseFrame())
        let secondReuse = try XCTUnwrap(pool.leaseFrame())
        let reusedIdentifiers = Set([
            ObjectIdentifier(firstReuse),
            ObjectIdentifier(secondReuse)
        ])
        let returned = Set([
            ObjectIdentifier(leased),
            ObjectIdentifier(playing)
        ])
        XCTAssertTrue(
            reusedIdentifiers.isSubset(of: returned)
        )
    }

    func testCapacityIsHardBoundAndZeroCapacityRejectsLeases()
        throws
    {
        let pool = makePool(capacity: 2)
        let first = try XCTUnwrap(pool.leaseFrame())
        let second = try XCTUnwrap(pool.leaseFrame())
        first.startPlaying()

        XCTAssertNil(pool.leaseFrame())
        XCTAssertEqual(pool.diagnostics.totalCount, 2)

        second.cancel()
        XCTAssertTrue(pool.leaseFrame() === second)
        XCTAssertEqual(pool.diagnostics.totalCount, 2)

        let emptyPool = makePool(capacity: 0)
        XCTAssertNil(emptyPool.leaseFrame())
        XCTAssertEqual(emptyPool.diagnostics.totalCount, 0)
    }

    func testCancelReturnsFrameAndPlayingLeasesReleaseIndependently()
        throws
    {
        let pool = makePool(capacity: 2)
        let first = try XCTUnwrap(pool.leaseFrame())
        first.position = 1
        first.duration = 0.5
        first.size = 128
        first.cancel()

        let reused = try XCTUnwrap(pool.leaseFrame())
        XCTAssertTrue(reused === first)
        XCTAssertEqual(
            reused.transportSnapshot(),
            .init(position: 0, duration: 0, size: 0)
        )
        reused.startPlaying()

        let second = try XCTUnwrap(pool.leaseFrame())
        second.startPlaying()

        var diagnostics = pool.diagnostics
        XCTAssertEqual(diagnostics.availableCount, 0)
        XCTAssertEqual(diagnostics.leasedCount, 0)
        XCTAssertTrue(diagnostics.hasPlayingFrame)
        XCTAssertEqual(diagnostics.playingCount, 2)
        XCTAssertTrue(reused.playing)

        reused.cancel()
        diagnostics = pool.diagnostics
        XCTAssertEqual(diagnostics.availableCount, 1)
        XCTAssertEqual(diagnostics.playingCount, 1)
        XCTAssertFalse(reused.playing)

        second.stopPlaying()
        let afterStop = pool.diagnostics
        XCTAssertEqual(afterStop.availableCount, 2)
        XCTAssertFalse(afterStop.hasPlayingFrame)
    }

    func testPoolRejectsIncompatibleFactoryResult() {
        let pool = IRFFFramePool(
            capacity: 1,
            frameClassName: IRFFAudioFrame.self
        ) {
            IRFFAVYUVVideoFrame()
        }

        XCTAssertNil(pool.leaseFrame())
        XCTAssertEqual(pool.diagnostics.totalCount, 0)
    }

    func testPoolRejectsDuplicateFactoryIdentity() throws {
        let factoryFrame = IRFFFrame()
        let pool = IRFFFramePool(
            capacity: 1,
            frameClassName: IRFFFrame.self
        ) {
            factoryFrame
        }

        XCTAssertTrue(
            try XCTUnwrap(pool.leaseFrame())
                === factoryFrame
        )
        XCTAssertNil(pool.leaseFrame())
        XCTAssertEqual(pool.diagnostics.leasedCount, 1)
        XCTAssertEqual(pool.diagnostics.totalCount, 1)
    }

    func testCloseWhileFactoryIsInFlightRejectsPublication() {
        let factoryStarted = expectation(
            description: "factory started"
        )
        let leaseFinished = expectation(
            description: "lease finished"
        )
        let allowFactoryToFinish =
            DispatchSemaphore(value: 0)
        let createdFrame = IRFFFrame()
        let result = FrameBox()
        let pool = IRFFFramePool(
            capacity: 1,
            frameClassName: IRFFFrame.self
        ) {
            factoryStarted.fulfill()
            allowFactoryToFinish.wait()
            return createdFrame
        }

        DispatchQueue.global(qos: .default).async {
            result.store(pool.leaseFrame())
            leaseFinished.fulfill()
        }

        wait(for: [factoryStarted], timeout: 1)
        XCTAssertTrue(pool.close())
        allowFactoryToFinish.signal()
        wait(for: [leaseFinished], timeout: 1)

        XCTAssertNil(result.frame)
        XCTAssertNil(createdFrame.delegate)
        XCTAssertEqual(pool.diagnostics.phase, .closed)
        XCTAssertEqual(pool.diagnostics.totalCount, 0)
    }

    func testForeignAndAlreadyAvailableFramesCannotChangeBuckets()
        throws
    {
        let pool = makePool(capacity: 1)
        let owned = try XCTUnwrap(pool.leaseFrame())
        let foreign = IRFFFrame()
        foreign.delegate = pool

        foreign.startPlaying()
        foreign.stopPlaying()
        foreign.cancel()
        XCTAssertEqual(pool.diagnostics.leasedCount, 1)

        owned.cancel()
        let revision = pool.diagnostics.revision
        owned.cancel()
        owned.startPlaying()

        let diagnostics = pool.diagnostics
        XCTAssertEqual(diagnostics.availableCount, 1)
        XCTAssertEqual(diagnostics.totalCount, 1)
        XCTAssertEqual(diagnostics.revision, revision)
        XCTAssertFalse(owned.playing)
    }

    func testCloseIsTerminalRepeatableAndDetachesFrames()
        throws
    {
        let pool = makePool(capacity: 2)
        let leased = try XCTUnwrap(pool.leaseFrame())
        let playing = try XCTUnwrap(pool.leaseFrame())
        playing.startPlaying()

        XCTAssertTrue(pool.close())
        XCTAssertFalse(pool.close())
        XCTAssertNil(pool.leaseFrame())
        leased.cancel()
        playing.stopPlaying()

        let diagnostics = pool.diagnostics
        XCTAssertEqual(diagnostics.phase, .closed)
        XCTAssertEqual(diagnostics.availableCount, 0)
        XCTAssertEqual(diagnostics.leasedCount, 0)
        XCTAssertFalse(diagnostics.hasPlayingFrame)
        XCTAssertEqual(diagnostics.totalCount, 0)
        XCTAssertNil(leased.delegate)
        XCTAssertNil(playing.delegate)
    }

    func testCloseReleasesPoolOwnedFrames() {
        let pool = makePool(capacity: 1)
        weak var weakFrame: IRFFFrame?

        autoreleasepool {
            var frame = pool.leaseFrame()
            weakFrame = frame
            frame = nil
        }
        XCTAssertNotNil(weakFrame)

        pool.close()
        XCTAssertNil(weakFrame)
    }

    func testConcurrentLifecycleAndDiagnosticsRemainCoherent() {
        let pool = makePool(capacity: 32)
        let group = DispatchGroup()
        let queue = DispatchQueue(
            label: "IRFFFramePoolTests.concurrent",
            attributes: .concurrent
        )
        let resultLock = NSLock()
        var observedInvalidSnapshot = false

        for worker in 0..<6 {
            group.enter()
            queue.async {
                for iteration in 0..<300 {
                    if let frame = pool.leaseFrame() {
                        if (worker + iteration).isMultiple(of: 2) {
                            frame.startPlaying()
                            frame.stopPlaying()
                        } else {
                            frame.cancel()
                        }
                    }

                    let diagnostics = pool.diagnostics
                    let partitionCount =
                        diagnostics.availableCount
                        + diagnostics.leasedCount
                        + diagnostics.playingCount
                    if diagnostics.phase != .open
                        || partitionCount
                            != diagnostics.totalCount
                        || diagnostics.totalCount > 32 {
                        resultLock.lock()
                        observedInvalidSnapshot = true
                        resultLock.unlock()
                    }
                }
                group.leave()
            }
        }

        XCTAssertEqual(
            group.wait(timeout: .now() + 5),
            .success
        )
        pool.flush()
        resultLock.lock()
        XCTAssertFalse(observedInvalidSnapshot)
        resultLock.unlock()

        let diagnostics = pool.diagnostics
        XCTAssertEqual(
            diagnostics.availableCount,
            diagnostics.totalCount
        )
        XCTAssertEqual(diagnostics.leasedCount, 0)
        XCTAssertFalse(diagnostics.hasPlayingFrame)
    }

    func testConcurrentFrameTransportAndLifecycleAccessIsRaceFree() {
        let frame = IRFFFrame()
        let delegate = DelegateProbe()
        frame.delegate = delegate
        let group = DispatchGroup()
        let queue = DispatchQueue(
            label: "IRFFFrameTests.concurrent",
            attributes: .concurrent
        )

        for worker in 0..<4 {
            group.enter()
            queue.async {
                for iteration in 0..<500 {
                    frame.position =
                        TimeInterval(worker * 500 + iteration)
                    frame.duration = 0.001
                    frame.size = iteration
                    _ = frame.transportSnapshot()
                    if iteration.isMultiple(of: 3) {
                        frame.startPlaying()
                    } else if iteration.isMultiple(of: 2) {
                        frame.stopPlaying()
                    } else {
                        frame.cancel()
                    }
                }
                group.leave()
            }
        }

        XCTAssertEqual(
            group.wait(timeout: .now() + 5),
            .success
        )
        XCTAssertTrue(frame.duration.isFinite)
        XCTAssertGreaterThanOrEqual(frame.size, 0)
    }

    private func makePool(
        capacity: Int
    ) -> IRFFFramePool {
        IRFFFramePool(
            capacity: capacity,
            frameClassName: IRFFFrame.self
        )
    }
}
