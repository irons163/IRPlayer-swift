import CoreGraphics
import UIKit
import XCTest
#if SWIFT_PACKAGE
@testable import IRPlayerSwift
#else
@testable import IRPlayer_swift
#endif

final class IRPlayerFacadeRuntimeTests: XCTestCase {
    func testLoadCommitsSourceBeforeBackendReplacementAndRoutesControls() {
        let harness = makeHarness()
        let player = harness.player
        let source = IRMediaSource(
            url: URL(string: "https://example.com/video.mp4"),
            headers: ["Authorization": "token"],
            videoType: .vr,
            backendPreference: .avFoundation
        )

        player.load(source, autoplay: false)
        let backend = harness.registry.backend(for: .avFoundation)

        XCTAssertEqual(player.activeBackend, .avPlayer)
        XCTAssertEqual(player.mediaSource?.url, source.url)
        XCTAssertEqual(player.contentHeaders, source.headers)
        XCTAssertEqual(backend?.replaceCallCount, 1)
        XCTAssertEqual(backend?.sourceURLsAtReplace, [source.url])
        XCTAssertEqual(backend?.videoTypesAtReplace, [.vr])

        player.play()
        player.seekToTime(time: 12.5)
        player.pause()

        XCTAssertEqual(backend?.playCallCount, 1)
        XCTAssertEqual(backend?.seekTimes, [12.5])
        XCTAssertEqual(backend?.pauseCallCount, 1)
        XCTAssertEqual(harness.idleTimer.values, [true, false])
    }

    func testReplacingCustomInputStopsOldBackendBeforeDetachingInput() {
        let harness = makeHarness()
        let player = harness.player
        let firstInput = IRFFVideoInput()
        let secondInput = IRFFVideoInput()
        let wasBoundWhenStopped = FacadeBoolBox()

        player.load(
            IRMediaSource(
                url: URL(string: "https://example.com/first.mp4"),
                videoInput: firstInput,
                backendPreference: .avFoundation
            ),
            autoplay: false
        )
        let avBackend = harness.registry.backend(for: .avFoundation)
        avBackend?.onStop = {
            wasBoundWhenStopped.value = firstInput.videoOutput != nil
        }
        XCTAssertNotNil(firstInput.videoOutput)

        player.load(
            IRMediaSource(
                url: URL(string: "https://example.com/second.mp4"),
                videoInput: secondInput,
                backendPreference: .ffmpeg
            ),
            autoplay: false
        )

        XCTAssertTrue(wasBoundWhenStopped.value)
        XCTAssertNil(firstInput.videoOutput)
        XCTAssertNotNil(secondInput.videoOutput)
        XCTAssertEqual(player.activeBackend, .ffmpeg)
    }

    func testDecoderVideoInputBindsToBackendOwnedDecoderOutput() {
        let harness = makeHarness()
        let input = IRFFVideoInput(outputType: .decoder)

        harness.player.load(
            IRMediaSource(
                url: URL(string: "https://example.com/video.mp4"),
                videoInput: input,
                backendPreference: .ffmpeg
            ),
            autoplay: false
        )

        let backend = harness.registry.backend(for: .ffmpeg)
        XCTAssertTrue(input.videoOutput === backend?.decoderVideoOutput)
    }

    func testInvalidSourceClearsPreviousSessionAndPublishesLoadError() {
        let harness = makeHarness()
        let input = IRFFVideoInput()
        harness.player.load(
            IRMediaSource(
                url: URL(string: "https://example.com/valid.mp4"),
                videoInput: input,
                backendPreference: .avFoundation
            ),
            autoplay: false
        )
        harness.registry.backend(for: .avFoundation)?.state = .playing

        harness.player.load(IRMediaSource(url: nil), autoplay: false)

        XCTAssertNil(harness.player.mediaSource)
        XCTAssertNil(harness.player.contentURL)
        XCTAssertNil(harness.player.activeBackend)
        XCTAssertNil(input.videoOutput)
        XCTAssertEqual(harness.player.error?.error.domain, "IRPlayer.Load")
        XCTAssertEqual(harness.player.error?.error.code, 1)
    }

    func testBackendFactoryFailureDoesNotLeaveSourceInstalled() {
        let harness = makeHarness(availableKinds: [])

        harness.player.load(
            IRMediaSource(
                url: URL(string: "https://example.com/video.mp4"),
                backendPreference: .avFoundation
            ),
            autoplay: false
        )

        XCTAssertNil(harness.player.mediaSource)
        XCTAssertNil(harness.player.activeBackend)
        XCTAssertEqual(harness.player.error?.error.domain, "IRPlayer.Load")
        XCTAssertEqual(harness.player.error?.error.code, 2)
    }

    func testStaleBackendEventsAreRejectedAfterBackendSwitch() {
        let harness = makeHarness()
        var states: [IRPlayerState] = []
        let observation = harness.player.observeEvents { event in
            if case let .stateChanged(_, current) = event {
                states.append(current)
            }
        }

        harness.player.load(
            IRMediaSource(
                url: URL(string: "https://example.com/av.mp4"),
                backendPreference: .avFoundation
            ),
            autoplay: false
        )
        let avBackend = harness.registry.backend(for: .avFoundation)
        avBackend?.host.playbackBackendDidChangeState(
            previous: .none,
            current: .playing
        )

        harness.player.load(
            IRMediaSource(
                url: URL(string: "https://example.com/ff.mp4"),
                backendPreference: .ffmpeg
            ),
            autoplay: false
        )
        avBackend?.host.playbackBackendDidChangeState(
            previous: .playing,
            current: .failed
        )
        harness.registry.backend(for: .ffmpeg)?
            .host.playbackBackendDidChangeState(
                previous: .none,
                current: .buffering
            )

        XCTAssertEqual(states, [.playing, .buffering])
        XCTAssertEqual(
            harness.player.backendEventRouter.diagnostics
                .acceptedEventCount,
            2
        )
        XCTAssertEqual(
            harness.player.backendEventRouter.diagnostics
                .rejectedEventCount,
            1
        )
        withExtendedLifetime(observation) {}
    }

    func testStopPublishesOneFinalNoneTransitionAndIsIdempotent() {
        let harness = makeHarness()
        harness.player.load(
            IRMediaSource(
                url: URL(string: "https://example.com/video.mp4"),
                backendPreference: .avFoundation
            ),
            autoplay: false
        )
        harness.registry.backend(for: .avFoundation)?.state = .playing
        var transitions: [
            (previous: IRPlayerState, current: IRPlayerState)
        ] = []
        let observation = harness.player.observeEvents { event in
            if case let .stateChanged(previous, current) = event {
                transitions.append((previous, current))
            }
        }

        harness.player.stop()
        harness.player.stop()

        XCTAssertEqual(transitions.count, 1)
        XCTAssertEqual(transitions.first?.previous, .playing)
        XCTAssertEqual(transitions.first?.current, IRPlayerState.none)
        XCTAssertNil(harness.player.activeBackend)
        XCTAssertNil(harness.player.mediaSource)
        withExtendedLifetime(observation) {}
    }

    func testPresentationAPIExposesCurrentModeTapAndSnapshot() {
        let harness = makeHarness()
        let player = harness.player
        var deliveredPlayer: IRPlayerImp?
        var deliveredView: IRPLFView?
        player.viewTapAction = {
            deliveredPlayer = $0
            deliveredView = $1
        }
        player.updateGraphicsViewFrame(
            frame: CGRect(x: 0, y: 0, width: 20, height: 10)
        )

        player.presentationSession.handleSingleTap()

        XCTAssertTrue(player.renderMode === player.renderModes?.first)
        XCTAssertTrue(deliveredPlayer === player)
        XCTAssertTrue(deliveredView === player.view)
        XCTAssertEqual(
            player.snapshot()?.size,
            CGSize(width: 20, height: 10)
        )
    }

    func testBackgroundFacadeCommandsMarshalToRuntimeThread() {
        let harness = makeHarness()
        let finished = expectation(description: "background facade commands")

        DispatchQueue.global(qos: .userInitiated).async {
            harness.player.load(
                IRMediaSource(
                    url: URL(string: "https://example.com/video.mp4"),
                    backendPreference: .avFoundation
                ),
                autoplay: false
            )
            harness.player.play()
            harness.player.seekToTime(time: 4)
            harness.player.pause()
            finished.fulfill()
        }
        wait(for: [finished], timeout: 3)

        let backend = harness.registry.backend(for: .avFoundation)
        XCTAssertEqual(backend?.executionWasMainThread.count, 4)
        XCTAssertTrue(
            backend?.executionWasMainThread.allSatisfy { $0 } == true
        )
    }

    func testRuntimeOwnersDoNotCreateFacadeRetainCycle() {
        let registry = FacadeBackendRegistry(
            availableKinds: [.avFoundation, .ffmpeg]
        )
        weak var weakPlayer: IRPlayerImp?

        autoreleasepool {
            let player = makeHarness(registry: registry).player
            weakPlayer = player
            player.load(
                IRMediaSource(
                    url: URL(string: "https://example.com/video.mp4"),
                    backendPreference: .avFoundation
                ),
                autoplay: false
            )
        }

        XCTAssertNil(weakPlayer)
    }

    private func makeHarness(
        availableKinds: Set<IRPlaybackBackendKind> = [
            .avFoundation,
            .ffmpeg
        ],
        registry: FacadeBackendRegistry? = nil
    ) -> FacadeRuntimeHarness {
        let registry = registry ?? FacadeBackendRegistry(
            availableKinds: availableKinds
        )
        let idleTimer = FacadeIdleTimerProbe()
        let environment = IRPlayerEnvironmentDependencies(
            notificationCenter: NotificationCenter(),
            clock: { 100 },
            commandDispatcher: { $0() },
            idleTimer: idleTimer,
            audioManagerFactory: { nil }
        )
        let player = IRPlayerImp(
            runtimeDependencies: IRPlayerRuntimeDependencies(
                presentation: .system,
                environment: environment,
                backendFactory: registry.makeBackend
            )
        )
        return FacadeRuntimeHarness(
            player: player,
            registry: registry,
            idleTimer: idleTimer
        )
    }
}

private struct FacadeRuntimeHarness {
    let player: IRPlayerImp
    let registry: FacadeBackendRegistry
    let idleTimer: FacadeIdleTimerProbe
}

private final class FacadeBackendRegistry: @unchecked Sendable {
    private let lock = NSLock()
    private let availableKinds: Set<IRPlaybackBackendKind>
    private var backends:
        [IRPlaybackBackendKind: FacadeBackendProbe] = [:]

    init(availableKinds: Set<IRPlaybackBackendKind>) {
        self.availableKinds = availableKinds
    }

    func makeBackend(
        kind: IRPlaybackBackendKind,
        host: any IRPlaybackBackendHost
    ) -> (any IRPlaybackBackend)? {
        guard availableKinds.contains(kind) else { return nil }
        let backend = FacadeBackendProbe(kind: kind, host: host)
        lock.lock()
        backends[kind] = backend
        lock.unlock()
        return backend
    }

    func backend(
        for kind: IRPlaybackBackendKind
    ) -> FacadeBackendProbe? {
        lock.lock()
        defer { lock.unlock() }
        return backends[kind]
    }
}

private final class FacadeBackendProbe:
    IRPlaybackBackend,
    @unchecked Sendable
{
    let kind: IRPlaybackBackendKind
    let host: any IRPlaybackBackendHost
    let decoderVideoOutput: IRFFDecoderVideoOutput? =
        FacadeVideoOutputProbe()

    private let lock = NSLock()
    private var storedState: IRPlayerState = .none
    private var storedPlayCallCount = 0
    private var storedPauseCallCount = 0
    private var storedStopCallCount = 0
    private var storedReplaceCallCount = 0
    private var storedSeekTimes: [TimeInterval] = []
    private var storedSourceURLsAtReplace: [URL?] = []
    private var storedVideoTypesAtReplace: [IRVideoType] = []
    private var storedExecutionWasMainThread: [Bool] = []
    var onStop: (() -> Void)?

    init(
        kind: IRPlaybackBackendKind,
        host: any IRPlaybackBackendHost
    ) {
        self.kind = kind
        self.host = host
    }

    var state: IRPlayerState {
        get {
            lock.lock()
            defer { lock.unlock() }
            return storedState
        }
        set {
            lock.lock()
            storedState = newValue
            lock.unlock()
        }
    }

    var presentationSize: CGSize { .zero }
    var bitrate: TimeInterval { 0 }
    var progress: TimeInterval { 0 }
    var duration: TimeInterval { 0 }
    var playableTime: TimeInterval { 0 }
    var seeking: Bool { false }

    var playCallCount: Int {
        locked { storedPlayCallCount }
    }

    var pauseCallCount: Int {
        locked { storedPauseCallCount }
    }

    var stopCallCount: Int {
        locked { storedStopCallCount }
    }

    var replaceCallCount: Int {
        locked { storedReplaceCallCount }
    }

    var seekTimes: [TimeInterval] {
        locked { storedSeekTimes }
    }

    var sourceURLsAtReplace: [URL?] {
        locked { storedSourceURLsAtReplace }
    }

    var videoTypesAtReplace: [IRVideoType] {
        locked { storedVideoTypesAtReplace }
    }

    var executionWasMainThread: [Bool] {
        locked { storedExecutionWasMainThread }
    }

    func play() {
        lock.lock()
        storedPlayCallCount += 1
        storedExecutionWasMainThread.append(Thread.isMainThread)
        lock.unlock()
    }

    func pause() {
        lock.lock()
        storedPauseCallCount += 1
        storedExecutionWasMainThread.append(Thread.isMainThread)
        lock.unlock()
    }

    func stop() {
        lock.lock()
        storedStopCallCount += 1
        let callback = onStop
        lock.unlock()
        callback?()
    }

    func seek(
        to time: TimeInterval,
        completionHandler: ((Bool) -> Void)?
    ) {
        lock.lock()
        storedSeekTimes.append(time)
        storedExecutionWasMainThread.append(Thread.isMainThread)
        lock.unlock()
        completionHandler?(true)
    }

    func replaceVideo() {
        let sourceURL = host.contentURL as URL?
        let videoType = host.videoType
        lock.lock()
        storedReplaceCallCount += 1
        storedSourceURLsAtReplace.append(sourceURL)
        storedVideoTypesAtReplace.append(videoType)
        storedExecutionWasMainThread.append(Thread.isMainThread)
        lock.unlock()
    }

    func reloadVolume() {}
    func reloadPlayableBufferInterval() {}

    private func locked<Result>(_ body: () -> Result) -> Result {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }
}

private final class FacadeVideoOutputProbe:
    NSObject,
    IRFFDecoderVideoOutput
{}

private final class FacadeIdleTimerProbe:
    IRPlayerIdleTimerControlling,
    @unchecked Sendable
{
    private let lock = NSLock()
    private var storedValues: [Bool] = []

    var values: [Bool] {
        lock.lock()
        defer { lock.unlock() }
        return storedValues
    }

    func setDisabled(_ disabled: Bool) {
        lock.lock()
        storedValues.append(disabled)
        lock.unlock()
    }
}

private final class FacadeBoolBox: @unchecked Sendable {
    private let lock = NSLock()
    private var storedValue = false

    var value: Bool {
        get {
            lock.lock()
            defer { lock.unlock() }
            return storedValue
        }
        set {
            lock.lock()
            storedValue = newValue
            lock.unlock()
        }
    }
}
