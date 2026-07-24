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

        router.deliverState(
            from: .avFoundation,
            previous: .none,
            current: .playing
        )
        router.deliverProgress(
            from: .avFoundation,
            current: 1,
            total: 2
        )
        router.deliverPlayableTime(
            from: .avFoundation,
            current: 1.5,
            total: 2
        )
        router.deliverFailure(from: .avFoundation, error: error)

        XCTAssertEqual(sink.eventCount, 0)
        XCTAssertEqual(router.diagnostics.acceptedEventCount, 0)
        XCTAssertEqual(router.diagnostics.rejectedEventCount, 4)
    }

    func testRouterAdmitsOnlyEventsFromActiveBackendKind() {
        let sink = BackendEventSinkProbe()
        let router = IRPlaybackBackendEventRouter(sink: sink)
        router.activate(.ffmpeg)

        router.deliverState(
            from: .avFoundation,
            previous: .none,
            current: .playing
        )
        router.deliverState(
            from: .ffmpeg,
            previous: .none,
            current: .buffering
        )
        router.deliverProgress(from: .ffmpeg, current: 3, total: 10)
        router.deliverPlayableTime(from: .ffmpeg, current: 7, total: 10)
        router.deliverFailure(from: .ffmpeg, error: IRError())

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

        router.activate(.avFoundation)
        router.deliverProgress(from: .avFoundation, current: 1, total: 5)
        router.activate(.ffmpeg)
        router.deliverProgress(from: .avFoundation, current: 2, total: 5)
        router.deliverProgress(from: .ffmpeg, current: 3, total: 5)

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
            router.activate(.avFoundation)
        }

        XCTAssertNil(weakSink)
        router.deliverProgress(from: .avFoundation, current: 1, total: 2)
        XCTAssertEqual(router.diagnostics.rejectedEventCount, 1)
    }

    func testHostAdapterProxiesContextAndTagsEvents() {
        let context = BackendContextProbe()
        let sink = BackendEventSinkProbe()
        let router = IRPlaybackBackendEventRouter(sink: sink)
        let adapter = IRPlaybackBackendHostAdapter(
            kind: .avFoundation,
            context: context,
            eventRouter: router
        )
        router.activate(.avFoundation)

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
        router.activate(.ffmpeg)

        DispatchQueue.concurrentPerform(iterations: 1_000) { index in
            router.deliverProgress(
                from: .ffmpeg,
                current: TimeInterval(index),
                total: 1_000
            )
        }

        XCTAssertEqual(sink.progresses.count, 1_000)
        XCTAssertEqual(router.diagnostics.acceptedEventCount, 1_000)
        XCTAssertEqual(router.diagnostics.rejectedEventCount, 0)
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
