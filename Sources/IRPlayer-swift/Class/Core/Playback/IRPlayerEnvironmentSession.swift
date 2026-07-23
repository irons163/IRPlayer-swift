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
        let mode: IRPlayerBackgroundMode
        let needsForegroundResume: Bool
        let lastForegroundTime: TimeInterval?
    }

    private let mutationLock = NSRecursiveLock()
    private let lock = NSLock()
    private let dependencies: IRPlayerEnvironmentDependencies
    private let stateProvider: () -> IRPlayerState
    private let commandHandler: (Command) -> Void
    private let lifecycleController: IRPlayerLifecycleController

    private var observerTokens: [NSObjectProtocol] = []
    private var storedAudioManager: IRAudioManager?
    private var closed = false

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
        installObservers()
        replaceAudioManager(dependencies.audioManagerFactory())
    }

    deinit {
        close()
    }

    var diagnostics: Diagnostics {
        lock.lock()
        defer { lock.unlock() }
        return Diagnostics(
            isClosed: closed,
            observerCount: observerTokens.count,
            hasAudioManager: storedAudioManager != nil,
            mode: lifecycleController.mode,
            needsForegroundResume:
                lifecycleController.needsForegroundResume,
            lastForegroundTime: lifecycleController.lastForegroundTime
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
            lifecycleController.mode = newValue
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
        lock.unlock()

        previous?.removeHandlerTarget(self)
        audioManager?.setHandlerTarget(
            self,
            interruption: { [weak self] _, _, type, _ in
                self?.handleAudioInterruption(type)
            },
            routeChange: { [weak self] _, _, reason in
                self?.handleAudioRouteChange(reason)
            }
        )
    }

    func playbackDidStart() {
        guard acceptsSideEffects else { return }
        dependencies.idleTimer.setDisabled(true)
    }

    func playbackDidPauseOrStop() {
        dependencies.idleTimer.setDisabled(false)
    }

    func didEnterBackground() {
        let state = stateProvider()
        lock.lock()
        let command = closed
            ? Command.none
            : lifecycleController.didEnterBackground(state: state)
        lock.unlock()
        dispatch(command)
    }

    func willEnterForeground() {
        let state = stateProvider()
        let now = dependencies.clock()
        lock.lock()
        let command = closed
            ? Command.none
            : lifecycleController.willEnterForeground(
                state: state,
                now: now
            )
        lock.unlock()
        dispatch(command)
    }

    func resetLifecycle() {
        lock.lock()
        lifecycleController.reset()
        lock.unlock()
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
        lifecycleController.reset()
        lock.unlock()

        resources.0.forEach(
            dependencies.notificationCenter.removeObserver
        )
        resources.1?.removeHandlerTarget(self)
        dependencies.idleTimer.setDisabled(false)
        return true
    }

    private var acceptsSideEffects: Bool {
        lock.lock()
        defer { lock.unlock() }
        return !closed
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
        _ type: IRAudioManagerInterruptionType
    ) {
        let state = stateProvider()
        let now = dependencies.clock()
        lock.lock()
        let command = closed
            ? Command.none
            : lifecycleController.audioInterruption(
                type: type,
                state: state,
                now: now
            )
        lock.unlock()
        dispatch(command)
    }

    private func handleAudioRouteChange(
        _ reason: IRAudioManagerRouteChangeReason
    ) {
        let state = stateProvider()
        lock.lock()
        let command = closed
            ? Command.none
            : lifecycleController.audioRouteChanged(
                reason: reason,
                state: state
            )
        lock.unlock()
        dispatch(command)
    }

    private func dispatch(_ command: Command) {
        guard command != .none else { return }
        dependencies.commandDispatcher { [weak self] in
            guard let self, self.acceptsSideEffects else { return }
            self.commandHandler(command)
        }
    }
}
