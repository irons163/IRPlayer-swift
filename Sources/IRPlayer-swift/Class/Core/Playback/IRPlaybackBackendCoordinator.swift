import Foundation

struct IRPlaybackBackendProduct {
    let backend: any IRPlaybackBackend
    let retainedHost: AnyObject?

    init(
        backend: any IRPlaybackBackend,
        retaining retainedHost: AnyObject? = nil
    ) {
        self.backend = backend
        self.retainedHost = retainedHost
    }
}

enum IRPlaybackBackendReplacementResult {
    case activated(
        activation: IRPlaybackBackendActivation,
        backend: any IRPlaybackBackend
    )
    case unavailable(IRPlaybackBackendActivation)
    case superseded(IRPlaybackBackendActivation)

    var activeBackend: (any IRPlaybackBackend)? {
        guard case let .activated(_, backend) = self else { return nil }
        return backend
    }
}

final class IRPlaybackBackendCoordinator: @unchecked Sendable {
    typealias Factory = (
        IRPlaybackBackendActivation
    ) -> IRPlaybackBackendProduct?
    typealias ActivationHandler = (
        IRPlaybackBackendActivation?
    ) -> Void

    struct Diagnostics {
        let activeKind: IRPlaybackBackendKind?
        let backendCount: Int
        let replacementGeneration: UInt64
        let replaceCount: Int
        let resetCount: Int
        let commandCount: Int
    }

    private struct ActiveRecord {
        let activation: IRPlaybackBackendActivation
        let product: IRPlaybackBackendProduct

        var backend: any IRPlaybackBackend { product.backend }
    }

    private struct CommandExecution {
        let wasDispatched: Bool
        let currentActivation: IRPlaybackBackendActivation?
    }

    private let mutationLock = NSRecursiveLock()
    private let stateLock = NSLock()
    private let factory: Factory
    private let didChangeActiveActivation: ActivationHandler

    private var activeRecord: ActiveRecord?
    private var replacementGeneration: UInt64 = 0
    private var replaceCount = 0
    private var resetCount = 0
    private var commandCount = 0

    init(
        factory: @escaping Factory,
        didChangeActiveActivation:
            @escaping ActivationHandler = { _ in }
    ) {
        self.factory = factory
        self.didChangeActiveActivation = didChangeActiveActivation
    }

    var diagnostics: Diagnostics {
        stateLock.lock()
        defer { stateLock.unlock() }
        return Diagnostics(
            activeKind: activeRecord?.activation.kind,
            backendCount: activeRecord == nil ? 0 : 1,
            replacementGeneration: replacementGeneration,
            replaceCount: replaceCount,
            resetCount: resetCount,
            commandCount: commandCount
        )
    }

    var snapshot: IRPlaybackBackendSnapshot {
        for _ in 0..<3 {
            guard let record = currentRecord else { return .empty }
            let snapshot = record.backend.snapshot
            if isCurrent(record) {
                return snapshot
            }
        }
        return .empty
    }

    var activeActivation: IRPlaybackBackendActivation? {
        stateLock.lock()
        defer { stateLock.unlock() }
        return activeRecord?.activation
    }

    var activeKind: IRPlaybackBackendKind? {
        activeActivation?.kind
    }

    var currentTransactionGeneration: UInt64 {
        stateLock.lock()
        defer { stateLock.unlock() }
        return replacementGeneration
    }

    var activeBackend: (any IRPlaybackBackend)? {
        currentRecord?.backend
    }

    @discardableResult
    func replace(
        with kind: IRPlaybackBackendKind,
        prepare: () -> Void = {}
    ) -> IRPlaybackBackendReplacementResult {
        mutationLock.lock()
        defer { mutationLock.unlock() }

        let activation = beginReplacement(kind: kind)
        guard isLatestTransaction(activation) else {
            return .superseded(activation)
        }
        prepare()
        guard isLatestTransaction(activation) else {
            return .superseded(activation)
        }

        let product = factory(activation)
        guard isLatestTransaction(activation) else {
            return .superseded(activation)
        }
        guard let product,
              product.backend.kind == kind else {
            return .unavailable(activation)
        }

        stateLock.lock()
        activeRecord = ActiveRecord(
            activation: activation,
            product: product
        )
        stateLock.unlock()
        didChangeActiveActivation(activation)
        guard isCurrent(
            activation: activation,
            backend: product.backend
        ) else {
            return .superseded(activation)
        }

        product.backend.replaceVideo()
        guard isCurrent(
            activation: activation,
            backend: product.backend
        ) else {
            return .superseded(activation)
        }
        return .activated(
            activation: activation,
            backend: product.backend
        )
    }

    @discardableResult
    func play() -> IRPlaybackBackendActivation? {
        performCommand { $0.play() }.currentActivation
    }

    @discardableResult
    func pause() -> IRPlaybackBackendActivation? {
        performCommand { $0.pause() }.currentActivation
    }

    func seek(
        to time: TimeInterval,
        completionHandler: ((Bool) -> Void)? = nil
    ) {
        let execution = performCommand {
            $0.seek(to: time, completionHandler: completionHandler)
        }
        guard execution.wasDispatched else {
            completionHandler?(false)
            return
        }
    }

    func reloadVolume() {
        performCommand { $0.reloadVolume() }
    }

    func reloadPlayableBufferInterval() {
        performCommand { $0.reloadPlayableBufferInterval() }
    }

    func updateActiveContentHeaders(
        _ headers: [String: String]?
    ) {
        mutationLock.lock()
        defer { mutationLock.unlock() }
        guard let record = currentRecord else { return }
        (
            record.product.retainedHost
                as? any IRPlaybackBackendSourceUpdating
        )?.updateContentHeaders(headers)
    }

    @discardableResult
    func reset() -> UInt64 {
        mutationLock.lock()
        defer { mutationLock.unlock() }

        let releasedRecord: ActiveRecord?
        let resetGeneration: UInt64
        stateLock.lock()
        releasedRecord = activeRecord
        activeRecord = nil
        replacementGeneration &+= 1
        resetGeneration = replacementGeneration
        resetCount += 1
        stateLock.unlock()
        didChangeActiveActivation(nil)
        releasedRecord?.backend.stop()
        return resetGeneration
    }

    func hasBackend(for kind: IRPlaybackBackendKind) -> Bool {
        activeKind == kind
    }

    func existingBackend(
        for kind: IRPlaybackBackendKind
    ) -> (any IRPlaybackBackend)? {
        guard let record = currentRecord,
              record.activation.kind == kind else {
            return nil
        }
        return record.backend
    }

    func isCurrent(_ activation: IRPlaybackBackendActivation) -> Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return activeRecord?.activation == activation
    }

    func isCurrentTransaction(_ generation: UInt64) -> Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return replacementGeneration == generation
    }

    func isCurrentResetTransaction(_ generation: UInt64) -> Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return replacementGeneration == generation
            && activeRecord == nil
    }

    @discardableResult
    private func performCommand(
        _ command: (any IRPlaybackBackend) -> Void
    ) -> CommandExecution {
        mutationLock.lock()
        defer { mutationLock.unlock() }
        guard let record = currentRecord else {
            return CommandExecution(
                wasDispatched: false,
                currentActivation: nil
            )
        }
        stateLock.lock()
        commandCount += 1
        stateLock.unlock()
        command(record.backend)
        return CommandExecution(
            wasDispatched: true,
            currentActivation:
                isCurrent(record) ? record.activation : nil
        )
    }

    private var currentRecord: ActiveRecord? {
        stateLock.lock()
        defer { stateLock.unlock() }
        return activeRecord
    }

    private func beginReplacement(
        kind: IRPlaybackBackendKind
    ) -> IRPlaybackBackendActivation {
        let previousRecord: ActiveRecord?
        let activation: IRPlaybackBackendActivation
        stateLock.lock()
        previousRecord = activeRecord
        activeRecord = nil
        replacementGeneration &+= 1
        replaceCount += 1
        activation = IRPlaybackBackendActivation(
            generation: replacementGeneration,
            kind: kind
        )
        stateLock.unlock()
        didChangeActiveActivation(nil)
        previousRecord?.backend.stop()
        return activation
    }

    private func isLatestTransaction(
        _ activation: IRPlaybackBackendActivation
    ) -> Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return replacementGeneration == activation.generation
            && activeRecord == nil
    }

    private func isCurrent(_ record: ActiveRecord) -> Bool {
        isCurrent(
            activation: record.activation,
            backend: record.backend
        )
    }

    private func isCurrent(
        activation: IRPlaybackBackendActivation,
        backend: any IRPlaybackBackend
    ) -> Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        guard let activeRecord else { return false }
        return activeRecord.activation == activation
            && activeRecord.backend === backend
    }
}
