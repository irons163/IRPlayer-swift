import Foundation

final class IRPlaybackBackendCoordinator: @unchecked Sendable {
    typealias Factory = (IRPlaybackBackendKind) -> (any IRPlaybackBackend)?
    typealias ActivationHandler = (IRPlaybackBackendKind?) -> Void

    struct Diagnostics {
        let activeKind: IRPlaybackBackendKind?
        let backendCount: Int
        let replacementGeneration: UInt64
        let replaceCount: Int
        let resetCount: Int
        let commandCount: Int
    }

    private let mutationLock = NSRecursiveLock()
    private let stateLock = NSLock()
    private let factory: Factory
    private let didChangeActiveKind: ActivationHandler

    private var backends: [IRPlaybackBackendKind: any IRPlaybackBackend] = [:]
    private var storedActiveKind: IRPlaybackBackendKind?
    private var replacementGeneration: UInt64 = 0
    private var replaceCount = 0
    private var resetCount = 0
    private var commandCount = 0

    init(
        factory: @escaping Factory,
        didChangeActiveKind: @escaping ActivationHandler = { _ in }
    ) {
        self.factory = factory
        self.didChangeActiveKind = didChangeActiveKind
    }

    var diagnostics: Diagnostics {
        stateLock.lock()
        defer { stateLock.unlock() }
        return Diagnostics(
            activeKind: storedActiveKind,
            backendCount: backends.count,
            replacementGeneration: replacementGeneration,
            replaceCount: replaceCount,
            resetCount: resetCount,
            commandCount: commandCount
        )
    }

    var snapshot: IRPlaybackBackendSnapshot {
        activeBackend?.snapshot ?? .empty
    }

    var activeKind: IRPlaybackBackendKind? {
        stateLock.lock()
        defer { stateLock.unlock() }
        return storedActiveKind
    }

    var activeBackend: (any IRPlaybackBackend)? {
        stateLock.lock()
        defer { stateLock.unlock() }
        guard let storedActiveKind else { return nil }
        return backends[storedActiveKind]
    }

    @discardableResult
    func replace(
        with kind: IRPlaybackBackendKind?,
        prepare: () -> Void = {}
    ) -> (any IRPlaybackBackend)? {
        mutationLock.lock()
        defer { mutationLock.unlock() }

        let previousBackend = deactivateLocked()
        previousBackend?.stop()
        prepare()

        guard let kind, let backend = backendLocked(for: kind) else {
            recordReplacement()
            return nil
        }

        stateLock.lock()
        storedActiveKind = kind
        replacementGeneration &+= 1
        replaceCount += 1
        stateLock.unlock()
        didChangeActiveKind(kind)

        backend.replaceVideo()
        return backend
    }

    func play() {
        performCommand { $0.play() }
    }

    func pause() {
        performCommand { $0.pause() }
    }

    func seek(
        to time: TimeInterval,
        completionHandler: ((Bool) -> Void)? = nil
    ) {
        guard performCommand({
            $0.seek(to: time, completionHandler: completionHandler)
        }) else {
            completionHandler?(false)
            return
        }
    }

    func reloadVolume() {
        performOnAllBackends { $0.reloadVolume() }
    }

    func reloadPlayableBufferInterval() {
        performOnAllBackends { $0.reloadPlayableBufferInterval() }
    }

    func reset() {
        mutationLock.lock()
        defer { mutationLock.unlock() }

        _ = deactivateLocked()
        let releasedBackends: [any IRPlaybackBackend]
        stateLock.lock()
        releasedBackends = Array(backends.values)
        backends.removeAll(keepingCapacity: false)
        replacementGeneration &+= 1
        resetCount += 1
        stateLock.unlock()

        releasedBackends.forEach { $0.stop() }
    }

    func hasBackend(for kind: IRPlaybackBackendKind) -> Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return backends[kind] != nil
    }

    func existingBackend(
        for kind: IRPlaybackBackendKind
    ) -> (any IRPlaybackBackend)? {
        stateLock.lock()
        defer { stateLock.unlock() }
        return backends[kind]
    }

    @discardableResult
    private func performCommand(
        _ command: (any IRPlaybackBackend) -> Void
    ) -> Bool {
        mutationLock.lock()
        defer { mutationLock.unlock() }
        guard let backend = activeBackend else { return false }
        recordCommand()
        command(backend)
        return true
    }

    private func performOnAllBackends(
        _ command: (any IRPlaybackBackend) -> Void
    ) {
        mutationLock.lock()
        defer { mutationLock.unlock() }
        let currentBackends: [any IRPlaybackBackend]
        stateLock.lock()
        currentBackends = Array(backends.values)
        commandCount += currentBackends.count
        stateLock.unlock()
        currentBackends.forEach(command)
    }

    private func backendLocked(
        for kind: IRPlaybackBackendKind
    ) -> (any IRPlaybackBackend)? {
        stateLock.lock()
        let existing = backends[kind]
        stateLock.unlock()
        if let existing {
            return existing
        }

        guard let backend = factory(kind), backend.kind == kind else {
            return nil
        }
        stateLock.lock()
        backends[kind] = backend
        stateLock.unlock()
        return backend
    }

    private func deactivateLocked() -> (any IRPlaybackBackend)? {
        stateLock.lock()
        let backend = storedActiveKind.flatMap { backends[$0] }
        storedActiveKind = nil
        stateLock.unlock()
        didChangeActiveKind(nil)
        return backend
    }

    private func recordReplacement() {
        stateLock.lock()
        replacementGeneration &+= 1
        replaceCount += 1
        stateLock.unlock()
    }

    private func recordCommand() {
        stateLock.lock()
        commandCount += 1
        stateLock.unlock()
    }
}
