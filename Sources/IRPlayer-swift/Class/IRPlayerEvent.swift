import Foundation

public struct IRPlayerTimeSnapshot: Equatable, Sendable {
    public let current: TimeInterval
    public let total: TimeInterval
    public let fraction: Double

    public init(current: TimeInterval, total: TimeInterval, fraction: Double) {
        self.current = current
        self.total = total
        self.fraction = fraction
    }
}

public enum IRPlayerEvent {
    case stateChanged(previous: IRPlayerState, current: IRPlayerState)
    case progress(IRPlayerTimeSnapshot)
    case playable(IRPlayerTimeSnapshot)
    case failure(IRError)
}

public final class IRPlayerObservation {
    private let lock = NSLock()
    private var cancellation: (() -> Void)?

    init(cancellation: @escaping () -> Void) {
        self.cancellation = cancellation
    }

    public func cancel() {
        let action: (() -> Void)?
        lock.lock()
        action = cancellation
        cancellation = nil
        lock.unlock()
        action?()
    }

    deinit {
        cancel()
    }
}

final class IRPlayerEventEmitter {
    typealias Handler = (IRPlayerEvent) -> Void

    private let lock = NSLock()
    private var handlers: [UUID: Handler] = [:]

    func observe(_ handler: @escaping Handler) -> IRPlayerObservation {
        let id = UUID()
        lock.lock()
        handlers[id] = handler
        lock.unlock()

        return IRPlayerObservation { [weak self] in
            self?.removeHandler(id: id)
        }
    }

    func emit(_ event: IRPlayerEvent) {
        if Thread.isMainThread {
            deliver(event)
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.deliver(event)
            }
        }
    }

    private func deliver(_ event: IRPlayerEvent) {
        lock.lock()
        let currentHandlers = Array(handlers.values)
        lock.unlock()
        currentHandlers.forEach { $0(event) }
    }

    private func removeHandler(id: UUID) {
        lock.lock()
        handlers[id] = nil
        lock.unlock()
    }
}
