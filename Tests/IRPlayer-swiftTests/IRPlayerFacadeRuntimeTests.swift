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
            videoType: .vr
        )

        player.load(source, autoplay: false)
        let backend = harness.registry.backend(for: .ffmpeg)

        XCTAssertEqual(player.activeBackend, .ffmpeg)
        XCTAssertEqual(player.mediaSource?.url, source.url)
        XCTAssertEqual(player.contentHeaders, source.headers)
        XCTAssertEqual(backend?.replaceCallCount, 1)
        XCTAssertEqual(backend?.sourceURLsAtReplace, [source.url])
        XCTAssertEqual(
            backend?.sourceHeadersAtReplace,
            [source.headers]
        )
        XCTAssertEqual(backend?.videoTypesAtReplace, [.vr])
        XCTAssertNil(harness.registry.backend(for: .avFoundation))

        player.play()
        player.seekToTime(time: 12.5)
        player.pause()

        XCTAssertEqual(backend?.playCallCount, 1)
        XCTAssertEqual(backend?.seekTimes, [12.5])
        XCTAssertEqual(backend?.pauseCallCount, 1)
        XCTAssertEqual(harness.idleTimer.values, [true, false])
    }

    func testHeaderMutationStaysSourceCoherentAcrossBackendReload() {
        let harness = makeHarness()
        let source = IRMediaSource(
            url: URL(
                string: "https://example.com/video.mp4"
            ),
            headers: ["Initial": "value"],
            backendPreference: .ffmpeg
        )
        harness.player.load(source, autoplay: false)
        let backend = harness.registry.backend(
            for: .ffmpeg
        )

        harness.player.setRequestHeaderFields(
            ["Authorization": "token"]
        )
        backend?.replaceVideo()

        XCTAssertEqual(
            harness.player.contentHeaders,
            ["Authorization": "token"]
        )
        XCTAssertEqual(
            harness.player.mediaSource?.headers,
            ["Authorization": "token"]
        )
        XCTAssertEqual(
            backend?.sourceHeadersAtReplace,
            [
                ["Initial": "value"],
                ["Authorization": "token"]
            ]
        )
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
                backendPreference: .ffmpeg
            ),
            autoplay: false
        )
        let firstBackend = harness.registry.backend(for: .ffmpeg)
        firstBackend?.onStop = {
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
                backendPreference: .ffmpeg
            ),
            autoplay: false
        )
        harness.registry.backend(for: .ffmpeg)?.state = .playing
        var events: [String] = []
        let observation = harness.player.observeEvents { event in
            switch event {
            case let .stateChanged(previous, current):
                XCTAssertEqual(previous, .playing)
                XCTAssertEqual(current, .none)
                events.append("state")
            case let .progress(snapshot):
                XCTAssertEqual(
                    snapshot,
                    IRPlayerTimeSnapshot(
                        current: 0,
                        total: 0,
                        fraction: 0
                    )
                )
                events.append("progress")
            case let .playable(snapshot):
                XCTAssertEqual(
                    snapshot,
                    IRPlayerTimeSnapshot(
                        current: 0,
                        total: 0,
                        fraction: 0
                    )
                )
                events.append("playable")
            case .failure:
                events.append("failure")
            }
        }

        harness.player.load(IRMediaSource(url: nil), autoplay: false)

        XCTAssertNil(harness.player.mediaSource)
        XCTAssertNil(harness.player.contentURL)
        XCTAssertNil(harness.player.activeBackend)
        XCTAssertNil(input.videoOutput)
        XCTAssertEqual(harness.player.error?.error.domain, "IRPlayer.Load")
        XCTAssertEqual(harness.player.error?.error.code, 1)
        XCTAssertEqual(
            events,
            ["state", "progress", "playable", "failure"]
        )
        withExtendedLifetime(observation) {}
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

    func testSameKindFailureFromPreviousActivationIsRejected() {
        let harness = makeHarness()
        let firstURL = URL(string: "https://example.com/first.mp4")
        let secondURL = URL(string: "https://example.com/second.mp4")
        harness.player.load(
            IRMediaSource(
                url: firstURL,
                backendPreference: .avFoundation
            ),
            autoplay: false
        )
        let firstBackend = harness.registry.backend(
            for: .avFoundation
        )
        var replaced = false
        let observation = harness.player.observeEvents { event in
            guard !replaced,
                  case let .stateChanged(_, current) = event,
                  current == .failed else {
                return
            }
            replaced = true
            harness.player.load(
                IRMediaSource(
                    url: secondURL,
                    backendPreference: .avFoundation
                ),
                autoplay: false
            )
        }
        let staleError = IRError()
        staleError.error = NSError(
            domain: "stale.activation",
            code: 7
        )

        firstBackend?.host.error = staleError
        firstBackend?.host.playbackBackendDidChangeState(
            previous: .playing,
            current: .failed
        )
        firstBackend?.host.playbackBackendDidFail(staleError)

        XCTAssertEqual(harness.player.mediaSource?.url, secondURL)
        XCTAssertNil(harness.player.error)
        XCTAssertEqual(
            harness.player.backendEventRouter.diagnostics
                .rejectedEventCount,
            1
        )
        withExtendedLifetime(observation) {}
    }

    func testReentrantLoadSupersedesOuterFacadeTransaction() {
        let registry = FacadeBackendRegistry(
            availableKinds: [.avFoundation, .ffmpeg]
        )
        registry.setBackendConfigurator { backend in
            guard backend.kind == .avFoundation else { return }
            backend.onReplace = { [weak backend] in
                backend?.host.playbackBackendDidUpdateProgress(
                    current: 0,
                    total: 0
                )
            }
        }
        let harness = makeHarness(registry: registry)
        let nestedURL = URL(string: "https://example.com/nested.flv")
        var loadedNestedSource = false
        let observation = harness.player.observeEvents { event in
            guard !loadedNestedSource,
                  case .progress = event else {
                return
            }
            loadedNestedSource = true
            harness.player.load(
                IRMediaSource(
                    url: nestedURL,
                    backendPreference: .ffmpeg
                ),
                autoplay: false
            )
        }

        harness.player.load(
            IRMediaSource(
                url: URL(string: "https://example.com/outer.mp4"),
                backendPreference: .avFoundation
            ),
            autoplay: true
        )

        XCTAssertEqual(harness.player.mediaSource?.url, nestedURL)
        XCTAssertEqual(harness.player.activeBackend, .ffmpeg)
        XCTAssertEqual(
            registry.backend(for: .ffmpeg)?.playCallCount,
            0
        )
        withExtendedLifetime(observation) {}
    }

    func testCapabilityMatrixRoutesAdvancedAutomaticSourcesToFFmpeg() {
        let harness = makeHarness()

        harness.player.load(
            IRMediaSource(
                url: URL(string: "https://example.com/fisheye.mp4"),
                videoType: .fisheye
            ),
            autoplay: false
        )
        XCTAssertEqual(harness.player.activeBackend, .ffmpeg)

        harness.player.load(
            IRMediaSource(
                url: URL(string: "https://example.com/custom.mp4"),
                videoInput: IRFFVideoInput()
            ),
            autoplay: false
        )
        XCTAssertEqual(harness.player.activeBackend, .ffmpeg)
    }

    func testExplicitUnsupportedAVSourcePublishesLoadFailure() {
        let harness = makeHarness()
        var typedError: IRError?
        let observation = harness.player.observeEvents { event in
            guard case let .failure(error) = event else { return }
            typedError = error
        }
        let legacy = expectation(
            forNotification:
                Notification.Name(IRPlayerErrorNotificationName),
            object: harness.player
        )

        harness.player.load(
            IRMediaSource(
                url: URL(string: "https://example.com/fisheye.mp4"),
                videoType: .fisheye,
                backendPreference: .avFoundation
            ),
            autoplay: false
        )

        wait(for: [legacy], timeout: 1)
        XCTAssertNil(harness.player.activeBackend)
        XCTAssertNil(harness.player.mediaSource)
        XCTAssertEqual(typedError?.error.domain, "IRPlayer.Load")
        XCTAssertEqual(typedError?.error.code, 3)
        withExtendedLifetime(observation) {}
    }

    func testExplicitAVSourceWithHeadersPublishesLoadFailure() {
        let harness = makeHarness()
        var typedError: IRError?
        let observation = harness.player.observeEvents { event in
            guard case let .failure(error) = event else { return }
            typedError = error
        }
        let legacy = expectation(
            forNotification:
                Notification.Name(IRPlayerErrorNotificationName),
            object: harness.player
        )

        harness.player.load(
            IRMediaSource(
                url: URL(string: "https://example.com/video.mp4"),
                headers: ["Authorization": "token"],
                backendPreference: .avFoundation
            ),
            autoplay: false
        )

        wait(for: [legacy], timeout: 1)
        XCTAssertNil(harness.player.activeBackend)
        XCTAssertNil(harness.player.mediaSource)
        XCTAssertEqual(typedError?.error.domain, "IRPlayer.Load")
        XCTAssertEqual(typedError?.error.code, 3)
        XCTAssertNil(harness.registry.backend(for: .avFoundation))
        withExtendedLifetime(observation) {}
    }

    func testUnsupportedAutomaticURLsDoNotReportMissingURL() {
        let harness = makeHarness()
        harness.player.decoder.unkonwnFormat = .error
        var failures: [NSError] = []
        let observation = harness.player.observeEvents { event in
            guard case let .failure(error) = event else {
                return
            }
            failures.append(error.error)
        }

        harness.player.load(
            IRMediaSource(
                url: URL(
                    string: "custom://example.com/media"
                )
            ),
            autoplay: false
        )
        harness.player.load(
            IRMediaSource(
                url: URL(
                    string:
                        "https://example.com/video.unknown"
                )
            ),
            autoplay: false
        )

        XCTAssertEqual(
            failures.map(\.code),
            [4, 4]
        )
        XCTAssertTrue(
            failures.allSatisfy {
                $0.localizedDescription
                    == "No playback backend supports this media source."
            }
        )
        XCTAssertNil(harness.player.mediaSource)
        XCTAssertNil(harness.player.activeBackend)
        withExtendedLifetime(observation) {}
    }

    func testLoadInvalidatesQueuedLifecycleCommand() {
        let dispatcher = FacadeDeferredDispatcher()
        let harness = makeHarness(
            commandDispatcher: dispatcher.enqueue
        )
        harness.player.load(
            IRMediaSource(
                url: URL(string: "https://example.com/first.mp4"),
                backendPreference: .avFoundation
            ),
            autoplay: false
        )
        harness.registry.backend(for: .avFoundation)?.state = .playing
        harness.player.environmentSession.didEnterBackground()
        XCTAssertEqual(dispatcher.count, 1)

        harness.player.load(
            IRMediaSource(
                url: URL(string: "https://example.com/second.flv"),
                backendPreference: .ffmpeg
            ),
            autoplay: false
        )
        dispatcher.runAll()

        XCTAssertEqual(
            harness.registry.backend(for: .ffmpeg)?.pauseCallCount,
            0
        )
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
        var progressEvents: [IRPlayerTimeSnapshot] = []
        var playableEvents: [IRPlayerTimeSnapshot] = []
        let observation = harness.player.observeEvents { event in
            switch event {
            case let .stateChanged(previous, current):
                transitions.append((previous, current))
            case let .progress(snapshot):
                progressEvents.append(snapshot)
            case let .playable(snapshot):
                playableEvents.append(snapshot)
            case .failure:
                break
            }
        }

        harness.player.stop()
        harness.player.stop()

        XCTAssertEqual(transitions.count, 1)
        XCTAssertEqual(transitions.first?.previous, .playing)
        XCTAssertEqual(transitions.first?.current, IRPlayerState.none)
        XCTAssertEqual(
            progressEvents,
            [IRPlayerTimeSnapshot(
                current: 0,
                total: 0,
                fraction: 0
            )]
        )
        XCTAssertEqual(
            playableEvents,
            [IRPlayerTimeSnapshot(
                current: 0,
                total: 0,
                fraction: 0
            )]
        )
        XCTAssertNil(harness.player.activeBackend)
        XCTAssertNil(harness.player.mediaSource)
        withExtendedLifetime(observation) {}
    }

    func testReentrantLoadSupersedesRemainingResetPublications() {
        let harness = makeHarness()
        let nestedURL = URL(
            string: "https://example.com/nested.flv"
        )
        harness.player.load(
            IRMediaSource(
                url: URL(
                    string: "https://example.com/first.mp4"
                ),
                backendPreference: .avFoundation
            ),
            autoplay: false
        )
        harness.registry.backend(for: .avFoundation)?
            .state = .playing
        var events: [String] = []
        var didReload = false
        let observation = harness.player.observeEvents { event in
            switch event {
            case .stateChanged:
                events.append("state")
                guard !didReload else { return }
                didReload = true
                harness.player.load(
                    IRMediaSource(
                        url: nestedURL,
                        backendPreference: .ffmpeg
                    ),
                    autoplay: false
                )
            case .progress:
                events.append("progress")
            case .playable:
                events.append("playable")
            case .failure:
                events.append("failure")
            }
        }

        harness.player.stop()

        XCTAssertEqual(events, ["state"])
        XCTAssertEqual(
            harness.player.mediaSource?.url,
            nestedURL
        )
        XCTAssertEqual(
            harness.player.activeBackend,
            .ffmpeg
        )
        withExtendedLifetime(observation) {}
    }

    func testReentrantLoadSupersedesInvalidSourceFailure() {
        let harness = makeHarness()
        let nestedURL = URL(
            string: "https://example.com/nested.flv"
        )
        harness.player.load(
            IRMediaSource(
                url: URL(
                    string: "https://example.com/first.mp4"
                ),
                backendPreference: .avFoundation
            ),
            autoplay: false
        )
        harness.registry.backend(for: .avFoundation)?
            .state = .playing
        var failures = 0
        var didReload = false
        let observation = harness.player.observeEvents { event in
            switch event {
            case .stateChanged:
                guard !didReload else { return }
                didReload = true
                harness.player.load(
                    IRMediaSource(
                        url: nestedURL,
                        videoType: .vr,
                        backendPreference: .ffmpeg
                    ),
                    autoplay: false
                )
            case .failure:
                failures += 1
            case .progress, .playable:
                break
            }
        }

        harness.player.load(
            IRMediaSource(
                url: nil,
                videoType: .fisheye
            ),
            autoplay: false
        )

        XCTAssertEqual(
            harness.player.mediaSource?.url,
            nestedURL
        )
        XCTAssertEqual(harness.player.videoType, .vr)
        XCTAssertNil(harness.player.error)
        XCTAssertEqual(failures, 0)
        withExtendedLifetime(observation) {}
    }

    func testLegacyResetQueueRejectsEventsAfterReentrantLoad() {
        let harness = makeHarness()
        let nestedURL = URL(
            string: "https://example.com/nested.flv"
        )
        harness.player.load(
            IRMediaSource(
                url: URL(
                    string: "https://example.com/first.mp4"
                ),
                backendPreference: .avFoundation
            ),
            autoplay: false
        )
        harness.registry.backend(for: .avFoundation)?
            .state = .playing

        var events: [String] = []
        var didReload = false
        var tokens: [NSObjectProtocol] = []
        let center = NotificationCenter.default
        tokens.append(
            center.addObserver(
                forName: Notification.Name(
                    IRPlayerStateChangeNotificationName
                ),
                object: harness.player,
                queue: .main
            ) { _ in
                events.append("state")
                guard !didReload else { return }
                didReload = true
                harness.player.load(
                    IRMediaSource(
                        url: nestedURL,
                        backendPreference: .ffmpeg
                    ),
                    autoplay: false
                )
            }
        )
        for (name, label) in [
            (
                IRPlayerProgressChangeNotificationName,
                "progress"
            ),
            (
                IRPlayerPlayableChangeNotificationName,
                "playable"
            ),
            (
                IRPlayerErrorNotificationName,
                "failure"
            )
        ] {
            tokens.append(
                center.addObserver(
                    forName: Notification.Name(name),
                    object: harness.player,
                    queue: .main
                ) { _ in
                    events.append(label)
                }
            )
        }
        defer {
            tokens.forEach(center.removeObserver)
        }

        harness.player.load(
            IRMediaSource(url: nil),
            autoplay: false
        )
        let drained = expectation(
            description: "legacy notification queue drained"
        )
        DispatchQueue.main.async {
            DispatchQueue.main.async {
                drained.fulfill()
            }
        }
        wait(for: [drained], timeout: 1)

        XCTAssertEqual(events, ["state"])
        XCTAssertEqual(harness.player.mediaSource?.url, nestedURL)
        XCTAssertEqual(harness.player.activeBackend, .ffmpeg)
        XCTAssertNil(harness.player.error)
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
        registry: FacadeBackendRegistry? = nil,
        commandDispatcher:
            @escaping IRPlayerEnvironmentDependencies.CommandDispatcher =
                { $0() }
    ) -> FacadeRuntimeHarness {
        let registry = registry ?? FacadeBackendRegistry(
            availableKinds: availableKinds
        )
        let idleTimer = FacadeIdleTimerProbe()
        let environment = IRPlayerEnvironmentDependencies(
            notificationCenter: NotificationCenter(),
            clock: { 100 },
            commandDispatcher: commandDispatcher,
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
    private var backendConfigurator:
        ((FacadeBackendProbe) -> Void)?

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
        let configurator = backendConfigurator
        backends[kind] = backend
        lock.unlock()
        configurator?(backend)
        return backend
    }

    func backend(
        for kind: IRPlaybackBackendKind
    ) -> FacadeBackendProbe? {
        lock.lock()
        defer { lock.unlock() }
        return backends[kind]
    }

    func setBackendConfigurator(
        _ configurator:
            @escaping (FacadeBackendProbe) -> Void
    ) {
        lock.lock()
        backendConfigurator = configurator
        lock.unlock()
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
    private var storedSourceHeadersAtReplace:
        [[String: String]?] = []
    private var storedVideoTypesAtReplace: [IRVideoType] = []
    private var storedExecutionWasMainThread: [Bool] = []
    var onStop: (() -> Void)?
    var onReplace: (() -> Void)?

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

    var sourceHeadersAtReplace:
        [[String: String]?]
    {
        locked { storedSourceHeadersAtReplace }
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
        let sourceHeaders = host.contentHeaders
        let videoType = host.videoType
        lock.lock()
        storedReplaceCallCount += 1
        storedSourceURLsAtReplace.append(sourceURL)
        storedSourceHeadersAtReplace.append(sourceHeaders)
        storedVideoTypesAtReplace.append(videoType)
        storedExecutionWasMainThread.append(Thread.isMainThread)
        let callback = onReplace
        lock.unlock()
        callback?()
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

private final class FacadeDeferredDispatcher:
    @unchecked Sendable
{
    private let lock = NSLock()
    private var blocks: [() -> Void] = []

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return blocks.count
    }

    func enqueue(_ block: @escaping () -> Void) {
        lock.lock()
        blocks.append(block)
        lock.unlock()
    }

    func runAll() {
        lock.lock()
        let pending = blocks
        blocks = []
        lock.unlock()
        pending.forEach { $0() }
    }
}
