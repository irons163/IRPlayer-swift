import Foundation

final class IRFFPlayerExecutor: @unchecked Sendable {
    struct Diagnostics: Equatable {
        let entryCount: Int
        let queuedEntryCount: Int
        let reentrantEntryCount: Int
        let isCurrentExecutor: Bool
    }

    private let queue: DispatchQueue
    private let identityKey = DispatchSpecificKey<UInt8>()
    private let identity: UInt8 = 1
    private let diagnosticsLock = NSLock()
    private var entryCount = 0
    private var queuedEntryCount = 0
    private var reentrantEntryCount = 0

    init(label: String = "com.irons163.IRPlayer.ffplayer") {
        queue = DispatchQueue(label: label)
        queue.setSpecific(key: identityKey, value: identity)
    }

    var isCurrentExecutor: Bool {
        DispatchQueue.getSpecific(key: identityKey) == identity
    }

    var diagnostics: Diagnostics {
        diagnosticsLock.lock()
        let snapshot = Diagnostics(
            entryCount: entryCount,
            queuedEntryCount: queuedEntryCount,
            reentrantEntryCount: reentrantEntryCount,
            isCurrentExecutor: isCurrentExecutor
        )
        diagnosticsLock.unlock()
        return snapshot
    }

    func sync<Result>(_ operation: () throws -> Result) rethrows -> Result {
        let isReentrant = isCurrentExecutor
        recordEntry(isReentrant: isReentrant)
        if isReentrant {
            return try operation()
        }
        return try queue.sync(execute: operation)
    }

    func async(_ operation: @escaping @Sendable () -> Void) {
        recordEntry(isReentrant: false)
        queue.async(execute: operation)
    }

    private func recordEntry(isReentrant: Bool) {
        diagnosticsLock.lock()
        entryCount += 1
        if isReentrant {
            reentrantEntryCount += 1
        } else {
            queuedEntryCount += 1
        }
        diagnosticsLock.unlock()
    }
}
