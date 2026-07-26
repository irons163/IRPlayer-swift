import AVFoundation
import UIKit
import XCTest
#if SWIFT_PACKAGE
@testable import IRPlayerSwift
#else
@testable import IRPlayer_swift
#endif

final class IRPlayerEnvironmentSessionTests: XCTestCase {
    func testOwnsExactApplicationObserversUntilClose() {
        let center = NotificationCenter()
        let state = EnvironmentStateBox(.playing)
        let commands = EnvironmentCommandRecorder()
        let idleTimer = EnvironmentIdleTimerProbe()
        let session = makeSession(
            center: center,
            state: state,
            commands: commands,
            idleTimer: idleTimer
        )

        XCTAssertEqual(session.diagnostics.observerCount, 2)
        center.post(
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
        XCTAssertEqual(commands.values, [.pause])

        XCTAssertTrue(session.close())
        XCTAssertFalse(session.close())
        center.post(
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )

        XCTAssertEqual(commands.values, [.pause])
        XCTAssertEqual(session.diagnostics.observerCount, 0)
        XCTAssertTrue(session.diagnostics.isClosed)
    }

    func testBackgroundForegroundRoundTripOwnsResumeIntent() {
        let center = NotificationCenter()
        let state = EnvironmentStateBox(.playing)
        let commands = EnvironmentCommandRecorder()
        let clock = EnvironmentClockBox(10)
        let session = makeSession(
            center: center,
            state: state,
            commands: commands,
            clock: clock
        )

        center.post(
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
        XCTAssertTrue(session.diagnostics.needsForegroundResume)

        state.value = .suspend
        clock.value = 12
        center.post(
            name: UIApplication.willEnterForegroundNotification,
            object: nil
        )

        XCTAssertEqual(commands.values, [.pause, .play])
        XCTAssertFalse(session.diagnostics.needsForegroundResume)
        XCTAssertEqual(session.diagnostics.lastForegroundTime, 12)
    }

    func testContinuingModeSuppressesLifecycleCommands() {
        let center = NotificationCenter()
        let state = EnvironmentStateBox(.playing)
        let commands = EnvironmentCommandRecorder()
        let session = makeSession(
            center: center,
            state: state,
            commands: commands
        )
        session.mode = .continuing

        center.post(
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
        state.value = .suspend
        center.post(
            name: UIApplication.willEnterForegroundNotification,
            object: nil
        )

        XCTAssertEqual(commands.values, [])
        XCTAssertEqual(session.diagnostics.mode, .continuing)
    }

    func testIdleTimerTracksPlaybackAndClose() {
        let idleTimer = EnvironmentIdleTimerProbe()
        let session = makeSession(idleTimer: idleTimer)

        session.playbackDidStart()
        session.playbackDidPauseOrStop()
        session.playbackDidStart()
        session.close()
        session.playbackDidStart()

        XCTAssertEqual(idleTimer.values, [true, false, true, false])
    }

    func testQueuedStaleStartCannotReenableAfterLifecycleReset() {
        let idleTimer = EnvironmentIdleTimerProbe()
        let session = makeSession(idleTimer: idleTimer)
        let scheduled = DispatchSemaphore(value: 0)

        DispatchQueue.global(qos: .userInitiated).async {
            session.playbackDidStart()
            scheduled.signal()
        }
        XCTAssertEqual(
            scheduled.wait(timeout: .now() + 1),
            .success
        )

        session.resetLifecycle()
        let drained = expectation(
            description: "main idle intent queue drained"
        )
        DispatchQueue.main.async {
            drained.fulfill()
        }
        wait(for: [drained], timeout: 1)

        XCTAssertEqual(idleTimer.values, [])
        XCTAssertFalse(
            session.diagnostics.isIdleTimerDisabled
        )
    }

    func testIdleTimerRejectsSupersededActivationCallbacks() {
        let idleTimer = EnvironmentIdleTimerProbe()
        let session = makeSession(idleTimer: idleTimer)
        let first = IRPlaybackBackendActivation(
            generation: 1,
            kind: .avFoundation
        )
        let second = IRPlaybackBackendActivation(
            generation: 2,
            kind: .ffmpeg
        )

        session.activatePlayback(first)
        session.playbackDidStart(activation: first)
        session.activatePlayback(second)
        session.playbackDidStart(activation: first)
        session.playbackDidStart(activation: second)
        session.playbackDidPauseOrStop(activation: first)

        XCTAssertEqual(idleTimer.values, [true, false, true])
        XCTAssertEqual(
            session.diagnostics.idleTimerActivation,
            second
        )
        XCTAssertTrue(
            session.diagnostics.isIdleTimerDisabled
        )
    }

    func testActivationChangeRevokesStaleLifecycleCommandsAndResume() {
        let applicationCenter = NotificationCenter()
        let audioCenter = NotificationCenter()
        let state = EnvironmentStateBox(.playing)
        let commands = EnvironmentCommandRecorder()
        let dispatcher = EnvironmentDeferredDispatcher()
        let session = makeSession(
            center: applicationCenter,
            state: state,
            commands: commands,
            commandDispatcher: dispatcher.enqueue,
            audioManagerFactory: {
                makeTestAudioManager(
                    notificationCenter: audioCenter
                )
            }
        )
        let first = IRPlaybackBackendActivation(
            generation: 1,
            kind: .avFoundation
        )
        let second = IRPlaybackBackendActivation(
            generation: 2,
            kind: .ffmpeg
        )
        session.activatePlayback(first)

        applicationCenter.post(
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
        postInterruption(to: audioCenter)
        postOldDeviceUnavailable(to: audioCenter)
        XCTAssertTrue(
            session.diagnostics.needsForegroundResume
        )
        XCTAssertEqual(dispatcher.count, 3)
        let firstGeneration =
            session.diagnostics.lifecycleGeneration

        session.activatePlayback(second)
        state.value = .suspend
        session.willEnterForeground()
        dispatcher.runAll()

        XCTAssertGreaterThan(
            session.diagnostics.lifecycleGeneration,
            firstGeneration
        )
        XCTAssertEqual(
            session.diagnostics.lifecycleActivation,
            second
        )
        XCTAssertFalse(
            session.diagnostics.needsForegroundResume
        )
        XCTAssertEqual(commands.values, [])
    }

    func testRepeatedActivationIdentityIsLifecycleNoOp() {
        let session = makeSession()
        let activation = IRPlaybackBackendActivation(
            generation: 1,
            kind: .avFoundation
        )
        session.activatePlayback(activation)
        let generation =
            session.diagnostics.lifecycleGeneration

        session.activatePlayback(activation)

        XCTAssertEqual(
            session.diagnostics.lifecycleGeneration,
            generation
        )
    }

    func testReplacingAudioManagerDetachesOldEventRoute() {
        let firstCenter = NotificationCenter()
        let secondCenter = NotificationCenter()
        let firstManager = makeTestAudioManager(
            notificationCenter: firstCenter
        )
        let secondManager = makeTestAudioManager(
            notificationCenter: secondCenter
        )
        let state = EnvironmentStateBox(.playing)
        let commands = EnvironmentCommandRecorder()
        let clock = EnvironmentClockBox(100)
        let session = makeSession(
            state: state,
            commands: commands,
            clock: clock,
            audioManagerFactory: { firstManager }
        )

        session.replaceAudioManager(secondManager)
        postInterruption(to: firstCenter)
        XCTAssertEqual(commands.values, [])

        postInterruption(to: secondCenter)
        XCTAssertEqual(commands.values, [.pause])
        XCTAssertTrue(session.audioManager === secondManager)
    }

    func testReplacingAudioManagerRevokesQueuedOldManagerCommand() {
        let firstCenter = NotificationCenter()
        let secondCenter = NotificationCenter()
        let firstManager = makeTestAudioManager(
            notificationCenter: firstCenter
        )
        let secondManager = makeTestAudioManager(
            notificationCenter: secondCenter
        )
        let state = EnvironmentStateBox(.playing)
        let commands = EnvironmentCommandRecorder()
        let dispatcher = EnvironmentDeferredDispatcher()
        let session = makeSession(
            state: state,
            commands: commands,
            commandDispatcher: dispatcher.enqueue,
            audioManagerFactory: { firstManager }
        )

        postInterruption(to: firstCenter)
        XCTAssertEqual(dispatcher.count, 1)
        let firstGeneration =
            session.diagnostics.audioManagerGeneration

        session.replaceAudioManager(secondManager)
        session.replaceAudioManager(firstManager)
        dispatcher.runAll()

        XCTAssertGreaterThan(
            session.diagnostics.audioManagerGeneration,
            firstGeneration
        )
        XCTAssertTrue(session.audioManager === firstManager)
        XCTAssertEqual(commands.values, [])
    }

    func testCloseCancelsAlreadyDispatchedCommands() {
        let center = NotificationCenter()
        let state = EnvironmentStateBox(.playing)
        let commands = EnvironmentCommandRecorder()
        let dispatcher = EnvironmentDeferredDispatcher()
        let session = makeSession(
            center: center,
            state: state,
            commands: commands,
            commandDispatcher: dispatcher.enqueue
        )

        center.post(
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
        XCTAssertEqual(dispatcher.count, 1)
        session.close()
        dispatcher.runAll()

        XCTAssertEqual(commands.values, [])
    }

    func testLifecycleResetCancelsQueuedCommandAndResumeIntent() {
        let center = NotificationCenter()
        let state = EnvironmentStateBox(.playing)
        let commands = EnvironmentCommandRecorder()
        let dispatcher = EnvironmentDeferredDispatcher()
        let session = makeSession(
            center: center,
            state: state,
            commands: commands,
            commandDispatcher: dispatcher.enqueue
        )

        center.post(
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
        let previousGeneration =
            session.diagnostics.lifecycleGeneration
        XCTAssertTrue(session.diagnostics.needsForegroundResume)
        XCTAssertEqual(dispatcher.count, 1)

        session.resetLifecycle()
        dispatcher.runAll()

        XCTAssertGreaterThan(
            session.diagnostics.lifecycleGeneration,
            previousGeneration
        )
        XCTAssertFalse(session.diagnostics.needsForegroundResume)
        XCTAssertEqual(commands.values, [])
    }

    func testChangingModeInvalidatesResumeIntent() {
        let center = NotificationCenter()
        let state = EnvironmentStateBox(.playing)
        let session = makeSession(center: center, state: state)
        center.post(
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
        XCTAssertTrue(session.diagnostics.needsForegroundResume)

        session.mode = .continuing

        XCTAssertFalse(session.diagnostics.needsForegroundResume)
        XCTAssertEqual(session.diagnostics.mode, .continuing)
    }

    func testLifecycleResetDuringStateReadRejectsStaleDecision() {
        let commands = EnvironmentCommandRecorder()
        let stateProvider = EnvironmentReentrantStateProvider()
        let session = IRPlayerEnvironmentSession(
            dependencies: IRPlayerEnvironmentDependencies(
                notificationCenter: NotificationCenter(),
                clock: { 100 },
                commandDispatcher: { $0() },
                idleTimer: EnvironmentIdleTimerProbe(),
                audioManagerFactory: { nil }
            ),
            stateProvider: stateProvider.read,
            commandHandler: { commands.append($0) }
        )
        stateProvider.session = session

        session.didEnterBackground()

        XCTAssertEqual(commands.values, [])
        XCTAssertFalse(session.diagnostics.needsForegroundResume)
    }

    func testConcurrentManagerReplacementAndCloseAreRaceFree() {
        let managers = (0..<40).map { _ in
            makeTestAudioManager(
                notificationCenter: NotificationCenter()
            )
        }
        let session = makeSession()

        DispatchQueue.concurrentPerform(iterations: managers.count) { index in
            session.replaceAudioManager(managers[index])
        }
        session.close()

        XCTAssertTrue(session.diagnostics.isClosed)
        XCTAssertFalse(session.diagnostics.hasAudioManager)
    }

    private func makeSession(
        center: NotificationCenter = NotificationCenter(),
        state: EnvironmentStateBox = EnvironmentStateBox(.none),
        commands: EnvironmentCommandRecorder =
            EnvironmentCommandRecorder(),
        idleTimer: EnvironmentIdleTimerProbe =
            EnvironmentIdleTimerProbe(),
        clock: EnvironmentClockBox = EnvironmentClockBox(100),
        commandDispatcher:
            @escaping IRPlayerEnvironmentDependencies.CommandDispatcher =
                { $0() },
        audioManagerFactory: @escaping () -> IRAudioManager? = { nil }
    ) -> IRPlayerEnvironmentSession {
        IRPlayerEnvironmentSession(
            dependencies: IRPlayerEnvironmentDependencies(
                notificationCenter: center,
                clock: { clock.value },
                commandDispatcher: commandDispatcher,
                idleTimer: idleTimer,
                audioManagerFactory: audioManagerFactory
            ),
            stateProvider: { state.value },
            commandHandler: { commands.append($0) }
        )
    }

    private func postInterruption(to center: NotificationCenter) {
        center.post(
            name: AVAudioSession.interruptionNotification,
            object: nil,
            userInfo: [
                AVAudioSessionInterruptionTypeKey:
                    AVAudioSession.InterruptionType.began.rawValue
            ]
        )
    }

    private func postOldDeviceUnavailable(
        to center: NotificationCenter
    ) {
        center.post(
            name: AVAudioSession.routeChangeNotification,
            object: nil,
            userInfo: [
                AVAudioSessionRouteChangeReasonKey:
                    AVAudioSession.RouteChangeReason
                    .oldDeviceUnavailable.rawValue
            ]
        )
    }
}

private final class EnvironmentStateBox: @unchecked Sendable {
    private let lock = NSLock()
    private var storedValue: IRPlayerState

    init(_ value: IRPlayerState) {
        storedValue = value
    }

    var value: IRPlayerState {
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

private final class EnvironmentClockBox: @unchecked Sendable {
    private let lock = NSLock()
    private var storedValue: TimeInterval

    init(_ value: TimeInterval) {
        storedValue = value
    }

    var value: TimeInterval {
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

private final class EnvironmentCommandRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storedValues: [IRPlayerLifecycleController.Command] = []

    var values: [IRPlayerLifecycleController.Command] {
        lock.lock()
        defer { lock.unlock() }
        return storedValues
    }

    func append(_ command: IRPlayerLifecycleController.Command) {
        lock.lock()
        storedValues.append(command)
        lock.unlock()
    }
}

private final class EnvironmentIdleTimerProbe:
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

private final class EnvironmentDeferredDispatcher:
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
        let current = blocks
        blocks = []
        lock.unlock()
        current.forEach { $0() }
    }
}

private final class EnvironmentReentrantStateProvider {
    weak var session: IRPlayerEnvironmentSession?

    func read() -> IRPlayerState {
        session?.resetLifecycle()
        return .playing
    }
}
