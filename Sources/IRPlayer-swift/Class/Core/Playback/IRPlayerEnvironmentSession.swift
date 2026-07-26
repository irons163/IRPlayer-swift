import Foundation
import UIKit

protocol IRPlayerIdleTimerControlling: AnyObject {
    func setDisabled(_ disabled: Bool)
}

final class IRSystemIdleTimerController: IRPlayerIdleTimerControlling {
    func setDisabled(_ disabled: Bool) {
        IRMainThreadExecutor.execute {
            UIApplication.shared.isIdleTimerDisabled = disabled
        }
    }
}

private final class IRPlayerIdleTimerIntentController:
    @unchecked Sendable
{
    struct Diagnostics {
        let generation: UInt64
        let expectedActivation: IRPlaybackBackendActivation?
        let isDisabled: Bool
        let isClosed: Bool
    }

    private let lock = NSRecursiveLock()
    private let idleTimer: any IRPlayerIdleTimerControlling
    private var generation: UInt64 = 0
    private var expectedActivation: IRPlaybackBackendActivation?
    private var desiredDisabled = false
    private var appliedDisabled = false
    private var closed = false

    init(idleTimer: any IRPlayerIdleTimerControlling) {
        self.idleTimer = idleTimer
    }

    var diagnostics: Diagnostics {
        lock.lock()
        defer { lock.unlock() }
        return Diagnostics(
            generation: generation,
            expectedActivation: expectedActivation,
            isDisabled: desiredDisabled,
            isClosed: closed
        )
    }

    func activate(
        _ activation: IRPlaybackBackendActivation?,
        force: Bool = false
    ) {
        lock.lock()
        guard !closed else {
            lock.unlock()
            return
        }
        guard force || expectedActivation != activation else {
            lock.unlock()
            return
        }
        expectedActivation = activation
        desiredDisabled = false
        generation &+= 1
        let admittedGeneration = generation
        lock.unlock()
        applyOnMain(generation: admittedGeneration)
    }

    func playbackDidStart(
        activation: IRPlaybackBackendActivation?
    ) {
        setDisabled(true, activation: activation)
    }

    func playbackDidPauseOrStop(
        activation: IRPlaybackBackendActivation?
    ) {
        setDisabled(false, activation: activation)
    }

    @discardableResult
    func close() -> Bool {
        lock.lock()
        guard !closed else {
            lock.unlock()
            return false
        }
        closed = true
        expectedActivation = nil
        desiredDisabled = false
        generation &+= 1
        let admittedGeneration = generation
        lock.unlock()
        applyOnMain(generation: admittedGeneration)
        return true
    }

    private func setDisabled(
        _ disabled: Bool,
        activation: IRPlaybackBackendActivation?
    ) {
        lock.lock()
        guard !closed,
              activation == expectedActivation else {
            lock.unlock()
            return
        }
        guard desiredDisabled != disabled else {
            lock.unlock()
            return
        }
        desiredDisabled = disabled
        generation &+= 1
        let admittedGeneration = generation
        lock.unlock()
        applyOnMain(generation: admittedGeneration)
    }

    private func applyOnMain(generation: UInt64) {
        IRMainThreadExecutor.execute { [self] in
            lock.lock()
            defer { lock.unlock() }
            guard self.generation == generation,
                  appliedDisabled != desiredDisabled else {
                return
            }
            appliedDisabled = desiredDisabled
            idleTimer.setDisabled(desiredDisabled)
        }
    }
}

struct IRPlayerEnvironmentDependencies {
    typealias CommandDispatcher = (@escaping () -> Void) -> Void

    let notificationCenter: NotificationCenter
    let clock: () -> TimeInterval
    let commandDispatcher: CommandDispatcher
    let idleTimer: any IRPlayerIdleTimerControlling
    let audioManagerFactory: () -> IRAudioManager?

    static var system: IRPlayerEnvironmentDependencies {
        IRPlayerEnvironmentDependencies(
            notificationCenter: .default,
            clock: { Date().timeIntervalSince1970 },
            commandDispatcher: { IRMainThreadExecutor.execute($0) },
            idleTimer: IRSystemIdleTimerController(),
            audioManagerFactory: { IRAudioManager() }
        )
    }
}

final class IRPlayerEnvironmentSession: @unchecked Sendable {
    typealias Command = IRPlayerLifecycleController.Command

    struct Diagnostics {
        let isClosed: Bool
        let observerCount: Int
        let hasAudioManager: Bool
        let audioManagerGeneration: UInt64
        let mode: IRPlayerBackgroundMode
        let lifecycleGeneration: UInt64
        let lifecycleActivation: IRPlaybackBackendActivation?
        let idleTimerGeneration: UInt64
        let idleTimerActivation: IRPlaybackBackendActivation?
        let isIdleTimerDisabled: Bool
        let needsForegroundResume: Bool
        let lastForegroundTime: TimeInterval?
    }

    private let mutationLock = NSRecursiveLock()
    private let lock = NSLock()
    private let dependencies: IRPlayerEnvironmentDependencies
    private let stateProvider: () -> IRPlayerState
    private let commandHandler: (Command) -> Void
    private let lifecycleController: IRPlayerLifecycleController
    private let idleTimerIntentController:
        IRPlayerIdleTimerIntentController

    private var observerTokens: [NSObjectProtocol] = []
    private var storedAudioManager: IRAudioManager?
    private var audioManagerGeneration: UInt64 = 0
    private var closed = false
    private var lifecycleGeneration: UInt64 = 0
    private var lifecycleActivation:
        IRPlaybackBackendActivation?

    init(
        mode: IRPlayerBackgroundMode = .autoPlayAndPause,
        dependencies: IRPlayerEnvironmentDependencies = .system,
        stateProvider: @escaping () -> IRPlayerState,
        commandHandler: @escaping (Command) -> Void
    ) {
        self.dependencies = dependencies
        self.stateProvider = stateProvider
        self.commandHandler = commandHandler
        lifecycleController = IRPlayerLifecycleController(mode: mode)
        idleTimerIntentController =
            IRPlayerIdleTimerIntentController(
                idleTimer: dependencies.idleTimer
            )
        installObservers()
        replaceAudioManager(dependencies.audioManagerFactory())
    }

    deinit {
        close()
    }

    var diagnostics: Diagnostics {
        lock.lock()
        let environmentDiagnostics = (
            isClosed: closed,
            observerCount: observerTokens.count,
            hasAudioManager: storedAudioManager != nil,
            audioManagerGeneration: audioManagerGeneration,
            mode: lifecycleController.mode,
            lifecycleGeneration: lifecycleGeneration,
            lifecycleActivation: lifecycleActivation,
            needsForegroundResume:
                lifecycleController.needsForegroundResume,
            lastForegroundTime:
                lifecycleController.lastForegroundTime
        )
        lock.unlock()
        let idleTimerDiagnostics =
            idleTimerIntentController.diagnostics
        return Diagnostics(
            isClosed: environmentDiagnostics.isClosed,
            observerCount:
                environmentDiagnostics.observerCount,
            hasAudioManager:
                environmentDiagnostics.hasAudioManager,
            audioManagerGeneration:
                environmentDiagnostics.audioManagerGeneration,
            mode: environmentDiagnostics.mode,
            lifecycleGeneration:
                environmentDiagnostics.lifecycleGeneration,
            lifecycleActivation:
                environmentDiagnostics.lifecycleActivation,
            idleTimerGeneration:
                idleTimerDiagnostics.generation,
            idleTimerActivation:
                idleTimerDiagnostics.expectedActivation,
            isIdleTimerDisabled:
                idleTimerDiagnostics.isDisabled,
            needsForegroundResume:
                environmentDiagnostics.needsForegroundResume,
            lastForegroundTime:
                environmentDiagnostics.lastForegroundTime
        )
    }

    var mode: IRPlayerBackgroundMode {
        get {
            lock.lock()
            defer { lock.unlock() }
            return lifecycleController.mode
        }
        set {
            lock.lock()
            guard !closed else {
                lock.unlock()
                return
            }
            guard lifecycleController.mode != newValue else {
                lock.unlock()
                return
            }
            lifecycleController.mode = newValue
            lifecycleController.reset()
            lifecycleGeneration &+= 1
            lock.unlock()
        }
    }

    var audioManager: IRAudioManager? {
        lock.lock()
        defer { lock.unlock() }
        return storedAudioManager
    }

    func replaceAudioManager(_ audioManager: IRAudioManager?) {
        mutationLock.lock()
        defer { mutationLock.unlock() }
        lock.lock()
        guard !closed else {
            lock.unlock()
            return
        }
        let previous = storedAudioManager
        guard previous !== audioManager else {
            lock.unlock()
            return
        }
        storedAudioManager = audioManager
        audioManagerGeneration &+= 1
        lock.unlock()

        previous?.removeHandlerTarget(self)
        audioManager?.setHandlerTarget(
            self,
            interruption: {
                [weak self] _, manager, type, _ in
                self?.handleAudioInterruption(
                    type,
                    manager: manager
                )
            },
            routeChange: {
                [weak self] _, manager, reason in
                self?.handleAudioRouteChange(
                    reason,
                    manager: manager
                )
            }
        )
    }

    func activatePlayback(
        _ activation: IRPlaybackBackendActivation?
    ) {
        lock.lock()
        guard !closed else {
            lock.unlock()
            return
        }
        guard lifecycleActivation != activation else {
            lock.unlock()
            return
        }
        lifecycleActivation = activation
        lifecycleController.reset()
        lifecycleGeneration &+= 1
        lock.unlock()
        idleTimerIntentController.activate(activation)
    }

    func playbackDidStart(
        activation: IRPlaybackBackendActivation? = nil
    ) {
        idleTimerIntentController.playbackDidStart(
            activation: activation
        )
    }

    func playbackDidPauseOrStop(
        activation: IRPlaybackBackendActivation? = nil
    ) {
        idleTimerIntentController.playbackDidPauseOrStop(
            activation: activation
        )
    }

    func didEnterBackground() {
        guard let generation = admittedLifecycleGeneration else { return }
        let state = stateProvider()
        lock.lock()
        guard !closed, lifecycleGeneration == generation else {
            lock.unlock()
            return
        }
        let command = lifecycleController.didEnterBackground(state: state)
        lock.unlock()
        dispatch(command, generation: generation)
    }

    func willEnterForeground() {
        guard let generation = admittedLifecycleGeneration else { return }
        let state = stateProvider()
        let now = dependencies.clock()
        lock.lock()
        guard !closed, lifecycleGeneration == generation else {
            lock.unlock()
            return
        }
        let command = lifecycleController.willEnterForeground(
            state: state,
            now: now
        )
        lock.unlock()
        dispatch(command, generation: generation)
    }

    func resetLifecycle() {
        lock.lock()
        guard !closed else {
            lock.unlock()
            return
        }
        lifecycleController.reset()
        lifecycleGeneration &+= 1
        lifecycleActivation = nil
        lock.unlock()
        idleTimerIntentController.activate(nil, force: true)
    }

    @discardableResult
    func close() -> Bool {
        mutationLock.lock()
        defer { mutationLock.unlock() }
        let resources: ([NSObjectProtocol], IRAudioManager?)
        lock.lock()
        guard !closed else {
            lock.unlock()
            return false
        }
        closed = true
        resources = (observerTokens, storedAudioManager)
        observerTokens = []
        storedAudioManager = nil
        audioManagerGeneration &+= 1
        lifecycleController.reset()
        lifecycleGeneration &+= 1
        lifecycleActivation = nil
        lock.unlock()

        resources.0.forEach(
            dependencies.notificationCenter.removeObserver
        )
        resources.1?.removeHandlerTarget(self)
        _ = idleTimerIntentController.close()
        return true
    }

    private var admittedLifecycleGeneration: UInt64? {
        lock.lock()
        defer { lock.unlock() }
        return closed ? nil : lifecycleGeneration
    }

    private func installObservers() {
        let center = dependencies.notificationCenter
        let tokens = [
            center.addObserver(
                forName: UIApplication.didEnterBackgroundNotification,
                object: nil,
                queue: nil
            ) { [weak self] _ in
                self?.didEnterBackground()
            },
            center.addObserver(
                forName: UIApplication.willEnterForegroundNotification,
                object: nil,
                queue: nil
            ) { [weak self] _ in
                self?.willEnterForeground()
            }
        ]
        lock.lock()
        if closed {
            lock.unlock()
            tokens.forEach(center.removeObserver)
        } else {
            observerTokens = tokens
            lock.unlock()
        }
    }

    private func handleAudioInterruption(
        _ type: IRAudioManagerInterruptionType,
        manager: IRAudioManager
    ) {
        guard let admission = admittedAudioEvent(
            from: manager
        ) else {
            return
        }
        let state = stateProvider()
        let now = dependencies.clock()
        lock.lock()
        guard isCurrentAudioEvent(
            admission,
            from: manager
        ) else {
            lock.unlock()
            return
        }
        let command = lifecycleController.audioInterruption(
            type: type,
            state: state,
            now: now
        )
        lock.unlock()
        dispatch(
            command,
            generation: admission.lifecycleGeneration,
            audioManagerGeneration:
                admission.audioManagerGeneration
        )
    }

    private func handleAudioRouteChange(
        _ reason: IRAudioManagerRouteChangeReason,
        manager: IRAudioManager
    ) {
        guard let admission = admittedAudioEvent(
            from: manager
        ) else {
            return
        }
        let state = stateProvider()
        lock.lock()
        guard isCurrentAudioEvent(
            admission,
            from: manager
        ) else {
            lock.unlock()
            return
        }
        let command = lifecycleController.audioRouteChanged(
            reason: reason,
            state: state
        )
        lock.unlock()
        dispatch(
            command,
            generation: admission.lifecycleGeneration,
            audioManagerGeneration:
                admission.audioManagerGeneration
        )
    }

    private func dispatch(
        _ command: Command,
        generation: UInt64,
        audioManagerGeneration admittedAudioManagerGeneration:
            UInt64? = nil
    ) {
        guard command != .none else { return }
        dependencies.commandDispatcher { [weak self] in
            guard let self else { return }
            self.lock.lock()
            let isCurrentAudioManager =
                admittedAudioManagerGeneration.map {
                    self.audioManagerGeneration == $0
                } ?? true
            let isCurrent =
                !self.closed
                && self.lifecycleGeneration == generation
                && isCurrentAudioManager
            self.lock.unlock()
            guard isCurrent else { return }
            self.commandHandler(command)
        }
    }

    private struct AudioEventAdmission {
        let lifecycleGeneration: UInt64
        let audioManagerGeneration: UInt64
    }

    private func admittedAudioEvent(
        from manager: IRAudioManager
    ) -> AudioEventAdmission? {
        lock.lock()
        defer { lock.unlock() }
        guard !closed,
              storedAudioManager === manager else {
            return nil
        }
        return AudioEventAdmission(
            lifecycleGeneration: lifecycleGeneration,
            audioManagerGeneration: audioManagerGeneration
        )
    }

    private func isCurrentAudioEvent(
        _ admission: AudioEventAdmission,
        from manager: IRAudioManager
    ) -> Bool {
        !closed
            && storedAudioManager === manager
            && lifecycleGeneration
                == admission.lifecycleGeneration
            && audioManagerGeneration
                == admission.audioManagerGeneration
    }
}
