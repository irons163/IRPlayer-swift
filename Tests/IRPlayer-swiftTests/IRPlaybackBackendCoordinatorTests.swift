import CoreGraphics
import XCTest
#if SWIFT_PACKAGE
@testable import IRPlayerSwift
#else
@testable import IRPlayer_swift
#endif

final class IRPlaybackBackendCoordinatorTests: XCTestCase {
    func testStateStoreReturnsOnlyRealTransitions() {
        let store = IRPlayerStateStore()

        XCTAssertEqual(store.value, .none)
        XCTAssertNil(store.transition(to: .none))

        let transition = store.transition(to: .buffering)
        XCTAssertEqual(transition?.previous, IRPlayerState.none)
        XCTAssertEqual(transition?.current, .buffering)
        XCTAssertEqual(store.value, .buffering)
        XCTAssertNil(store.transition(to: .buffering))
    }

    func testReplacementCreatesBackendOnceAndMakesItActiveBeforeReplace() {
        var createdKinds: [IRPlaybackBackendKind] = []
        var coordinator: IRPlaybackBackendCoordinator!
        let avBackend = PlaybackBackendSpy(kind: .avFoundation)
        avBackend.onReplace = {
            XCTAssertEqual(coordinator.activeKind, .avFoundation)
        }
        coordinator = IRPlaybackBackendCoordinator { kind in
            createdKinds.append(kind)
            return avBackend
        }

        coordinator.replace(with: .avFoundation)
        coordinator.replace(with: .avFoundation)

        XCTAssertEqual(createdKinds, [.avFoundation])
        XCTAssertEqual(avBackend.replaceCallCount, 2)
        XCTAssertTrue(coordinator.activeBackend === avBackend)
    }

    func testFactoryFailureLeavesCoordinatorInactiveWithoutCrashing() {
        let coordinator = IRPlaybackBackendCoordinator { _ in nil }

        XCTAssertNil(coordinator.replace(with: .ffmpeg))
        XCTAssertNil(coordinator.activeKind)
        XCTAssertEqual(coordinator.snapshot, .empty)
    }

    func testInactiveSeekCompletesWithFailure() {
        let coordinator = IRPlaybackBackendCoordinator { _ in nil }
        var result: Bool?

        coordinator.seek(to: 12) { result = $0 }

        XCTAssertEqual(result, false)
        XCTAssertEqual(coordinator.diagnostics.commandCount, 0)
    }

    func testMismatchedFactoryResultIsRejected() {
        let coordinator = IRPlaybackBackendCoordinator { _ in
            PlaybackBackendSpy(kind: .avFoundation)
        }

        XCTAssertNil(coordinator.replace(with: .ffmpeg))
        XCTAssertFalse(coordinator.hasBackend(for: .ffmpeg))
        XCTAssertNil(coordinator.activeKind)
    }

    func testReplacementStopsOppositeBackendAndRoutesCommandsToActiveBackend() {
        let avBackend = PlaybackBackendSpy(kind: .avFoundation)
        let ffBackend = PlaybackBackendSpy(kind: .ffmpeg)
        let coordinator = makeCoordinator(avBackend: avBackend, ffBackend: ffBackend)

        coordinator.replace(with: .avFoundation)
        coordinator.play()
        coordinator.seek(to: 12.5, completionHandler: nil)
        coordinator.pause()
        coordinator.replace(with: .ffmpeg)
        coordinator.play()

        XCTAssertEqual(avBackend.playCallCount, 1)
        XCTAssertEqual(avBackend.pauseCallCount, 1)
        XCTAssertEqual(avBackend.seekTimes, [12.5])
        XCTAssertEqual(avBackend.stopCallCount, 1)
        XCTAssertEqual(ffBackend.playCallCount, 1)
        XCTAssertEqual(ffBackend.replaceCallCount, 1)
        XCTAssertEqual(coordinator.activeKind, .ffmpeg)
    }

    func testReplacementTransactionStopsThenPreparesThenReplaces() {
        let avBackend = PlaybackBackendSpy(kind: .avFoundation)
        let ffBackend = PlaybackBackendSpy(kind: .ffmpeg)
        let coordinator = makeCoordinator(
            avBackend: avBackend,
            ffBackend: ffBackend
        )
        var events: [String] = []
        avBackend.onStop = { events.append("stop") }
        ffBackend.onReplace = { events.append("replace") }
        coordinator.replace(with: .avFoundation)
        events.removeAll()

        coordinator.replace(with: .ffmpeg) {
            events.append("prepare")
        }

        XCTAssertEqual(events, ["stop", "prepare", "replace"])
    }

    func testEmptyReplacementStopsActiveBackendAndClearsSnapshot() {
        let avBackend = PlaybackBackendSpy(kind: .avFoundation)
        let ffBackend = PlaybackBackendSpy(kind: .ffmpeg)
        let coordinator = makeCoordinator(avBackend: avBackend, ffBackend: ffBackend)

        coordinator.replace(with: .avFoundation)
        coordinator.replace(with: .ffmpeg)
        coordinator.replace(with: nil)

        XCTAssertNil(coordinator.activeKind)
        XCTAssertEqual(coordinator.snapshot, .empty)
        XCTAssertEqual(avBackend.stopCallCount, 1)
        XCTAssertEqual(ffBackend.stopCallCount, 1)

        coordinator.reset()

        XCTAssertEqual(avBackend.stopCallCount, 2)
        XCTAssertEqual(ffBackend.stopCallCount, 2)
    }

    func testSnapshotReadsOnlyActiveBackend() {
        let avBackend = PlaybackBackendSpy(kind: .avFoundation)
        avBackend.state = .playing
        avBackend.presentationSize = CGSize(width: 1920, height: 1080)
        avBackend.bitrate = 4_000_000
        avBackend.progress = 12
        avBackend.duration = 60
        avBackend.playableTime = 30
        avBackend.seeking = true
        let coordinator = makeCoordinator(avBackend: avBackend, ffBackend: PlaybackBackendSpy(kind: .ffmpeg))

        coordinator.replace(with: .avFoundation)

        XCTAssertEqual(
            coordinator.snapshot,
            IRPlaybackBackendSnapshot(
                state: .playing,
                presentationSize: CGSize(width: 1920, height: 1080),
                bitrate: 4_000_000,
                progress: 12,
                duration: 60,
                playableTime: 30,
                isSeeking: true
            )
        )
    }

    func testConfigurationRefreshesReachEveryConstructedBackend() {
        let avBackend = PlaybackBackendSpy(kind: .avFoundation)
        let ffBackend = PlaybackBackendSpy(kind: .ffmpeg)
        let coordinator = makeCoordinator(avBackend: avBackend, ffBackend: ffBackend)
        coordinator.replace(with: .avFoundation)
        coordinator.replace(with: .ffmpeg)

        coordinator.reloadVolume()
        coordinator.reloadPlayableBufferInterval()

        XCTAssertEqual(avBackend.reloadVolumeCallCount, 1)
        XCTAssertEqual(ffBackend.reloadVolumeCallCount, 1)
        XCTAssertEqual(avBackend.reloadBufferCallCount, 1)
        XCTAssertEqual(ffBackend.reloadBufferCallCount, 1)
    }

    func testDiagnosticsCountOneGenerationPerTransaction() {
        let backend = PlaybackBackendSpy(kind: .avFoundation)
        let coordinator = IRPlaybackBackendCoordinator { _ in backend }

        coordinator.replace(with: .avFoundation)
        coordinator.play()
        coordinator.pause()
        coordinator.seek(to: 1)
        coordinator.replace(with: nil)
        coordinator.reset()

        let diagnostics = coordinator.diagnostics
        XCTAssertEqual(diagnostics.replacementGeneration, 3)
        XCTAssertEqual(diagnostics.replaceCount, 2)
        XCTAssertEqual(diagnostics.resetCount, 1)
        XCTAssertEqual(diagnostics.commandCount, 3)
        XCTAssertEqual(diagnostics.backendCount, 0)
    }

    func testConcurrentReplacementAndCommandsRemainSerialized() {
        let avBackend = LockedCoordinatorBackend(kind: .avFoundation)
        let ffBackend = LockedCoordinatorBackend(kind: .ffmpeg)
        let coordinator = IRPlaybackBackendCoordinator { kind in
            kind == .avFoundation ? avBackend : ffBackend
        }

        DispatchQueue.concurrentPerform(iterations: 500) { index in
            switch index % 4 {
            case 0:
                coordinator.replace(with: .avFoundation)
            case 1:
                coordinator.replace(with: .ffmpeg)
            case 2:
                coordinator.play()
            default:
                coordinator.pause()
            }
        }
        coordinator.reset()

        XCTAssertNil(coordinator.activeKind)
        XCTAssertEqual(coordinator.diagnostics.backendCount, 0)
        XCTAssertGreaterThan(
            avBackend.stopCount + ffBackend.stopCount,
            0
        )
    }

    func testResetStopsAndReleasesEveryBackend() {
        let avBackend = PlaybackBackendSpy(kind: .avFoundation)
        let ffBackend = PlaybackBackendSpy(kind: .ffmpeg)
        let coordinator = makeCoordinator(avBackend: avBackend, ffBackend: ffBackend)
        coordinator.replace(with: .avFoundation)
        coordinator.replace(with: .ffmpeg)

        coordinator.reset()

        XCTAssertFalse(coordinator.hasBackend(for: .avFoundation))
        XCTAssertFalse(coordinator.hasBackend(for: .ffmpeg))
        XCTAssertNil(coordinator.activeBackend)
        XCTAssertEqual(avBackend.stopCallCount, 2)
        XCTAssertEqual(ffBackend.stopCallCount, 1)
    }

    private func makeCoordinator(
        avBackend: PlaybackBackendSpy,
        ffBackend: PlaybackBackendSpy
    ) -> IRPlaybackBackendCoordinator {
        IRPlaybackBackendCoordinator { kind in
            switch kind {
            case .avFoundation:
                return avBackend
            case .ffmpeg:
                return ffBackend
            }
        }
    }
}

private final class PlaybackBackendSpy: IRPlaybackBackend {
    let kind: IRPlaybackBackendKind
    var state: IRPlayerState = .none
    var presentationSize: CGSize = .zero
    var bitrate: TimeInterval = 0
    var progress: TimeInterval = 0
    var duration: TimeInterval = 0
    var playableTime: TimeInterval = 0
    var seeking = false
    var decoderVideoOutput: IRFFDecoderVideoOutput?

    private(set) var playCallCount = 0
    private(set) var pauseCallCount = 0
    private(set) var stopCallCount = 0
    private(set) var replaceCallCount = 0
    private(set) var reloadVolumeCallCount = 0
    private(set) var reloadBufferCallCount = 0
    private(set) var seekTimes: [TimeInterval] = []
    var onReplace: (() -> Void)?
    var onStop: (() -> Void)?

    init(kind: IRPlaybackBackendKind) {
        self.kind = kind
    }

    func play() { playCallCount += 1 }
    func pause() { pauseCallCount += 1 }
    func stop() {
        stopCallCount += 1
        onStop?()
    }

    func seek(to time: TimeInterval, completionHandler: ((Bool) -> Void)?) {
        seekTimes.append(time)
        completionHandler?(true)
    }

    func replaceVideo() {
        replaceCallCount += 1
        onReplace?()
    }

    func reloadVolume() { reloadVolumeCallCount += 1 }
    func reloadPlayableBufferInterval() { reloadBufferCallCount += 1 }
}

private final class LockedCoordinatorBackend:
    IRPlaybackBackend,
    @unchecked Sendable
{
    let kind: IRPlaybackBackendKind
    private let lock = NSLock()
    private var storedStopCount = 0

    init(kind: IRPlaybackBackendKind) {
        self.kind = kind
    }

    var state: IRPlayerState { .none }
    var presentationSize: CGSize { .zero }
    var bitrate: TimeInterval { 0 }
    var progress: TimeInterval { 0 }
    var duration: TimeInterval { 0 }
    var playableTime: TimeInterval { 0 }
    var seeking: Bool { false }
    var decoderVideoOutput: IRFFDecoderVideoOutput? { nil }

    var stopCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return storedStopCount
    }

    func play() {}
    func pause() {}

    func stop() {
        lock.lock()
        storedStopCount += 1
        lock.unlock()
    }

    func seek(
        to time: TimeInterval,
        completionHandler: ((Bool) -> Void)?
    ) {
        completionHandler?(true)
    }

    func replaceVideo() {}
    func reloadVolume() {}
    func reloadPlayableBufferInterval() {}
}
