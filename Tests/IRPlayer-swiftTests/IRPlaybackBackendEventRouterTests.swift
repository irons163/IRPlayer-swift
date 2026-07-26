import CoreGraphics
import XCTest
#if SWIFT_PACKAGE
@testable import IRPlayerSwift
#else
@testable import IRPlayer_swift
#endif

final class IRPlaybackBackendEventRouterTests: XCTestCase {
    func testInactiveRouterRejectsEveryEventKind() {
        let sink = BackendEventSinkProbe()
        let router = IRPlaybackBackendEventRouter(sink: sink)
        let error = IRError()
        let activation = activation(.avFoundation, generation: 1)

        router.deliverState(
            from: activation,
            previous: .none,
            current: .playing
        )
        router.deliverProgress(
            from: activation,
            current: 1,
            total: 2
        )
        router.deliverPlayableTime(
            from: activation,
            current: 1.5,
            total: 2
        )
        router.deliverFailure(from: activation, error: error)

        XCTAssertEqual(sink.eventCount, 0)
        XCTAssertEqual(router.diagnostics.acceptedEventCount, 0)
        XCTAssertEqual(router.diagnostics.rejectedEventCount, 4)
    }

    func testRouterAdmitsOnlyEventsFromActiveBackendKind() {
        let sink = BackendEventSinkProbe()
        let router = IRPlaybackBackendEventRouter(sink: sink)
        let ffActivation = activation(.ffmpeg, generation: 1)
        let avActivation = activation(.avFoundation, generation: 2)
        router.activate(ffActivation)

        router.deliverState(
            from: avActivation,
            previous: .none,
            current: .playing
        )
        router.deliverState(
            from: ffActivation,
            previous: .none,
            current: .buffering
        )
        router.deliverProgress(from: ffActivation, current: 3, total: 10)
        router.deliverPlayableTime(
            from: ffActivation,
            current: 7,
            total: 10
        )
        router.deliverFailure(from: ffActivation, error: IRError())

        XCTAssertEqual(sink.states.count, 1)
        XCTAssertEqual(sink.states.first?.previous, IRPlayerState.none)
        XCTAssertEqual(sink.states.first?.current, .buffering)
        XCTAssertEqual(sink.progresses.first?.current, 3)
        XCTAssertEqual(sink.playableTimes.first?.current, 7)
        XCTAssertEqual(sink.failureCount, 1)
        XCTAssertEqual(router.diagnostics.acceptedEventCount, 4)
        XCTAssertEqual(router.diagnostics.rejectedEventCount, 1)
    }

    func testSwitchingActiveKindRejectsEventsFromPreviousBackend() {
        let sink = BackendEventSinkProbe()
        let router = IRPlaybackBackendEventRouter(sink: sink)
        let avActivation = activation(.avFoundation, generation: 1)
        let ffActivation = activation(.ffmpeg, generation: 2)

        router.activate(avActivation)
        router.deliverProgress(
            from: avActivation,
            current: 1,
            total: 5
        )
        router.activate(ffActivation)
        router.deliverProgress(
            from: avActivation,
            current: 2,
            total: 5
        )
        router.deliverProgress(
            from: ffActivation,
            current: 3,
            total: 5
        )

        XCTAssertEqual(sink.progresses.map(\.current), [1, 3])
        XCTAssertEqual(router.diagnostics.activeKind, .ffmpeg)
        XCTAssertEqual(router.diagnostics.generation, 2)
        XCTAssertEqual(router.diagnostics.acceptedEventCount, 2)
        XCTAssertEqual(router.diagnostics.rejectedEventCount, 1)
    }

    func testRouterDoesNotRetainSink() {
        let router = IRPlaybackBackendEventRouter()
        weak var weakSink: BackendEventSinkProbe?

        autoreleasepool {
            let sink = BackendEventSinkProbe()
            weakSink = sink
            router.setSink(sink)
            router.activate(
                activation(.avFoundation, generation: 1)
            )
        }

        XCTAssertNil(weakSink)
        router.deliverProgress(
            from: activation(.avFoundation, generation: 1),
            current: 1,
            total: 2
        )
        XCTAssertEqual(router.diagnostics.rejectedEventCount, 1)
    }

    func testHostAdapterProxiesContextAndTagsEvents() {
        let context = BackendContextProbe()
        let sink = BackendEventSinkProbe()
        let router = IRPlaybackBackendEventRouter(sink: sink)
        let activation = activation(.avFoundation, generation: 1)
        let adapter = IRPlaybackBackendHostAdapter(
            activation: activation,
            context: context,
            eventRouter: router
        )
        router.activate(activation)

        XCTAssertEqual(adapter.contentURL, context.contentURL)
        XCTAssertEqual(adapter.contentHeaders, context.contentHeaders)
        XCTAssertEqual(adapter.videoType, .vr)
        XCTAssertTrue(adapter.decoder === context.decoder)
        XCTAssertEqual(adapter.volume, 0.4)
        XCTAssertEqual(adapter.playableBufferInterval, 8)
        XCTAssertTrue(adapter.isLiveStream)

        let error = IRError()
        adapter.error = error
        adapter.playbackBackendDidUpdateProgress(current: 2, total: 9)
        adapter.playbackBackendDidFail(error)

        XCTAssertTrue(context.error === error)
        XCTAssertEqual(sink.progresses.first?.current, 2)
        XCTAssertEqual(sink.failureCount, 1)
    }

    func testConcurrentDeliveryIsRaceFreeAndLossless() {
        let sink = BackendEventSinkProbe()
        let router = IRPlaybackBackendEventRouter(sink: sink)
        let activation = activation(.ffmpeg, generation: 1)
        router.activate(activation)

        DispatchQueue.concurrentPerform(iterations: 1_000) { index in
            router.deliverProgress(
                from: activation,
                current: TimeInterval(index),
                total: 1_000
            )
        }
        let drained = expectation(description: "concurrent events drained")
        DispatchQueue.main.async { drained.fulfill() }
        wait(for: [drained], timeout: 2)

        XCTAssertEqual(sink.progresses.count, 1_000)
        XCTAssertEqual(router.diagnostics.acceptedEventCount, 1_000)
        XCTAssertEqual(router.diagnostics.rejectedEventCount, 0)
    }

    func testSameKindPreviousActivationCannotDeliverToReplacement() {
        let sink = BackendEventSinkProbe()
        let router = IRPlaybackBackendEventRouter(sink: sink)
        let first = activation(.avFoundation, generation: 1)
        let second = activation(.avFoundation, generation: 2)

        router.activate(first)
        router.deliverProgress(from: first, current: 1, total: 5)
        router.activate(second)
        router.deliverFailure(from: first, error: IRError())
        router.deliverProgress(from: second, current: 2, total: 5)

        XCTAssertEqual(sink.progresses.map(\.current), [1, 2])
        XCTAssertEqual(sink.failureCount, 0)
        XCTAssertEqual(router.diagnostics.rejectedEventCount, 1)
    }

    func testQueuedWorkerDeliveryRevalidatesOnMainQueue() {
        let sink = BackendEventSinkProbe()
        let router = IRPlaybackBackendEventRouter(sink: sink)
        let first = activation(.avFoundation, generation: 1)
        let second = activation(.avFoundation, generation: 2)
        let queued = DispatchSemaphore(value: 0)
        router.activate(first)

        DispatchQueue.global(qos: .userInitiated).async {
            router.deliverProgress(from: first, current: 1, total: 5)
            queued.signal()
        }
        XCTAssertEqual(queued.wait(timeout: .now() + 1), .success)
        router.activate(second)
        let drained = expectation(description: "main delivery drained")
        DispatchQueue.main.async { drained.fulfill() }
        wait(for: [drained], timeout: 1)

        XCTAssertTrue(sink.progresses.isEmpty)
        XCTAssertEqual(router.diagnostics.rejectedEventCount, 1)
    }

    private func activation(
        _ kind: IRPlaybackBackendKind,
        generation: UInt64
    ) -> IRPlaybackBackendActivation {
        IRPlaybackBackendActivation(
            generation: generation,
            kind: kind
        )
    }
}

private final class BackendEventSinkProbe:
    IRPlaybackBackendEventSink,
    @unchecked Sendable
{
    private let lock = NSLock()
    private var storedStates:
        [(previous: IRPlayerState, current: IRPlayerState)] = []
    private var storedProgresses:
        [(current: TimeInterval, total: TimeInterval)] = []
    private var storedPlayableTimes:
        [(current: TimeInterval, total: TimeInterval)] = []
    private var storedFailureCount = 0

    var states: [(previous: IRPlayerState, current: IRPlayerState)] {
        lock.lock()
        defer { lock.unlock() }
        return storedStates
    }

    var progresses: [(current: TimeInterval, total: TimeInterval)] {
        lock.lock()
        defer { lock.unlock() }
        return storedProgresses
    }

    var playableTimes: [(current: TimeInterval, total: TimeInterval)] {
        lock.lock()
        defer { lock.unlock() }
        return storedPlayableTimes
    }

    var failureCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return storedFailureCount
    }

    var eventCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return storedStates.count
            + storedProgresses.count
            + storedPlayableTimes.count
            + storedFailureCount
    }

    func receiveBackendState(
        previous: IRPlayerState,
        current: IRPlayerState
    ) {
        lock.lock()
        storedStates.append((previous, current))
        lock.unlock()
    }

    func receiveBackendProgress(
        current: TimeInterval,
        total: TimeInterval
    ) {
        lock.lock()
        storedProgresses.append((current, total))
        lock.unlock()
    }

    func receiveBackendPlayableTime(
        current: TimeInterval,
        total: TimeInterval
    ) {
        lock.lock()
        storedPlayableTimes.append((current, total))
        lock.unlock()
    }

    func receiveBackendFailure(_ error: IRError) {
        lock.lock()
        storedFailureCount += 1
        lock.unlock()
    }
}

private final class BackendContextProbe: IRPlaybackBackendContext {
    var contentURL: NSURL? = NSURL(string: "https://example.com/video.mp4")
    var contentHeaders: [String: String]? = ["Token": "value"]
    var videoType: IRVideoType = .vr
    var videoInput: IRFFVideoInput?
    let decoder = IRPlayerDecoder.defaultDecoder()
    var displayView: IRGLView?
    var manager: IRAudioManager?
    var error: IRError?
    var volume: CGFloat = 0.4
    var playableBufferInterval: TimeInterval = 8
    var isLiveStream = true
}
