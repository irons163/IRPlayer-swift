import Foundation

enum IRFFDecoderOperationPolicy {

    static func needsScheduling(_ operation: Operation?) -> Bool {
        return operation?.isFinished ?? true
    }

    @discardableResult
    static func addDependency(_ dependency: Operation?, to operation: Operation?) -> Bool {
        guard let dependency, let operation else { return false }
        operation.addDependency(dependency)
        return true
    }

    @discardableResult
    static func enqueue(_ operation: Operation?, on queue: OperationQueue?) -> Bool {
        guard let operation, let queue else { return false }
        queue.addOperation(operation)
        return true
    }

    static func shouldNotifyError(closed: Bool, hasError: Bool) -> Bool {
        return hasError && !closed
    }
}
