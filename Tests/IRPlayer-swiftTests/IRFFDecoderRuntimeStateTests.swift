import XCTest
@testable import IRPlayer_swift

final class IRFFDecoderRuntimeStateTests: XCTestCase {
    func testScalarChangesAreAtomicAndSuppressDuplicates() {
        let state = IRFFDecoderRuntimeState()

        XCTAssertEqual(
            state.setProgress(4),
            IRFFDecoderRuntimeState.Change(previous: 0, current: 4)
        )
        XCTAssertNil(state.setProgress(4))
        XCTAssertEqual(
            state.setBuffering(true),
            IRFFDecoderRuntimeState.Change(previous: false, current: true)
        )
        XCTAssertEqual(
            state.setAudioTimeClock(3.5),
            IRFFDecoderRuntimeState.Change(previous: 0, current: 3.5)
        )

        let snapshot = state.snapshot
        XCTAssertEqual(snapshot.progress, 4)
        XCTAssertTrue(snapshot.buffering)
        XCTAssertEqual(snapshot.audioTimeClock, 3.5)
        XCTAssertFalse(snapshot.closed)
        XCTAssertFalse(snapshot.hasError)
    }

    func testBufferedDurationPreservesRequestedChangeAfterNormalization() {
        let state = IRFFDecoderRuntimeState()

        let change = state.applyBufferedDuration(
            requestedValue: 0.000_000_1,
            normalizedValue: 0
        )

        XCTAssertEqual(change?.previous, 0)
        XCTAssertEqual(change?.current, 0)
        XCTAssertEqual(state.snapshot.bufferedDuration, 0)
        XCTAssertNil(
            state.applyBufferedDuration(
                requestedValue: 0,
                normalizedValue: 0
            )
        )
    }

    func testConcurrentCloseElectsExactlyOneCleanupOwner() {
        let state = IRFFDecoderRuntimeState()
        let resultLock = NSLock()
        var ownershipCount = 0

        DispatchQueue.concurrentPerform(iterations: 100) { _ in
            guard state.beginClose() else { return }
            resultLock.lock()
            ownershipCount += 1
            resultLock.unlock()
        }

        XCTAssertEqual(ownershipCount, 1)
        XCTAssertTrue(state.snapshot.closed)
        XCTAssertFalse(state.beginClose())
    }

    func testSeekReplacementAndConsumptionAreDeterministic() {
        let state = IRFFDecoderRuntimeState()
        var firstResults: [Bool] = []
        var secondResults: [Bool] = []

        let first = state.beginSeek(to: 2) { firstResults.append($0) }
        XCTAssertEqual(first?.progressChange?.current, 2)
        XCTAssertNil(first?.displacedCompletion)
        XCTAssertEqual(state.snapshot.progress, 2)
        XCTAssertTrue(state.snapshot.seeking)

        let second = state.beginSeek(to: 8) { secondResults.append($0) }
        second?.displacedCompletion?(false)
        XCTAssertEqual(firstResults, [false])
        XCTAssertEqual(second?.progressChange?.previous, 2)
        XCTAssertEqual(second?.progressChange?.current, 8)

        let request = state.takePendingSeek()
        XCTAssertEqual(request?.target, 8)
        XCTAssertTrue(state.snapshot.seeking)
        XCTAssertNil(state.takePendingSeek())

        let completion = request.flatMap(state.finishSeek)
        completion?(true)
        XCTAssertFalse(state.snapshot.seeking)
        XCTAssertEqual(secondResults, [true])
    }

    func testSeekStartedDuringActiveSeekRemainsPending() {
        let state = IRFFDecoderRuntimeState()
        var firstResults: [Bool] = []
        var secondResults: [Bool] = []
        _ = state.beginSeek(to: 5) { firstResults.append($0) }
        let activeRequest = state.takePendingSeek()

        _ = state.beginSeek(to: 9) { secondResults.append($0) }
        let activeCompletion = activeRequest.flatMap(state.finishSeek)
        activeCompletion?(true)

        XCTAssertEqual(firstResults, [true])
        XCTAssertTrue(state.snapshot.seeking)
        let pendingRequest = state.takePendingSeek()
        XCTAssertEqual(pendingRequest?.target, 9)
        let pendingCompletion = pendingRequest.flatMap(state.finishSeek)
        pendingCompletion?(true)
        XCTAssertEqual(secondResults, [true])
        XCTAssertFalse(state.snapshot.seeking)
    }

    func testClosingRejectsAndCancelsPendingAndActiveSeeksExactlyOnce() {
        let state = IRFFDecoderRuntimeState()
        var activeResults: [Bool] = []
        var pendingResults: [Bool] = []
        _ = state.beginSeek(to: 5) { activeResults.append($0) }
        let activeRequest = state.takePendingSeek()
        _ = state.beginSeek(to: 7) { pendingResults.append($0) }

        XCTAssertTrue(state.beginClose())
        let completions = state.cancelSeeks()
        completions.forEach { $0(false) }

        XCTAssertEqual(activeResults, [false])
        XCTAssertEqual(pendingResults, [false])
        XCTAssertTrue(state.cancelSeeks().isEmpty)
        XCTAssertNil(activeRequest.flatMap(state.finishSeek))
        XCTAssertNil(state.beginSeek(to: 9, completion: nil))
        XCTAssertFalse(state.snapshot.seeking)
    }

    func testFrameReferencesAreProtectedAndClearedTogether() {
        let state = IRFFDecoderRuntimeState()
        let videoFrame = IRFFVideoFrame()
        let audioFrame = IRFFAudioFrame()

        state.currentVideoFrame = videoFrame
        state.currentAudioFrame = audioFrame

        XCTAssertTrue(state.currentVideoFrame === videoFrame)
        XCTAssertTrue(state.currentAudioFrame === audioFrame)

        state.clearFrames()

        XCTAssertNil(state.currentVideoFrame)
        XCTAssertNil(state.currentAudioFrame)
    }

    func testConcurrentSnapshotsAndMutationsRemainValid() {
        let state = IRFFDecoderRuntimeState()
        let failures = LockedFailureCount()

        DispatchQueue.concurrentPerform(iterations: 2_000) { index in
            if index.isMultiple(of: 2) {
                _ = state.setProgress(TimeInterval(index))
                _ = state.setBufferedDuration(TimeInterval(index / 2))
                _ = state.setPaused(index.isMultiple(of: 4))
            } else {
                let snapshot = state.snapshot
                if !snapshot.progress.isFinite ||
                    !snapshot.bufferedDuration.isFinite ||
                    snapshot.progress < 0 ||
                    snapshot.bufferedDuration < 0 {
                    failures.increment()
                }
            }
        }

        XCTAssertEqual(failures.value, 0)
    }
}

private final class LockedFailureCount: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }

    func increment() {
        lock.lock()
        count += 1
        lock.unlock()
    }
}
