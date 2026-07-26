import Foundation

final class IRFFDecoderSession: @unchecked Sendable {
    private enum OperationRole: String {
        case open
        case read
        case decode
        case display
        case audioMonitor

        var qualityOfService: QualityOfService {
            switch self {
            case .decode, .display, .audioMonitor:
                // Decode waits for packets and display waits for decoded
                // frames. Keeping both consumers at default QoS avoids
                // priority inversion when upstream completion arrives on a
                // default-QoS thread.
                return .default
            case .open, .read:
                return .userInitiated
            }
        }
    }

    enum Phase: Equatable {
        case idle
        case opening
        case active
        case failed
        case closing
        case closed
    }

    struct Resources {
        let formatContext: IRFFFormatContext?
        let audioDecoder: IRFFAudioDecoder?
        let videoDecoder: IRFFVideoDecoder?
    }

    struct Diagnostics: Equatable {
        let phase: Phase
        let hasOperationQueue: Bool
        let hasOpenOperation: Bool
        let hasReadOperation: Bool
        let hasDecodeOperation: Bool
        let hasDisplayOperation: Bool
        let hasAudioMonitorOperation: Bool
        let hasFormatContext: Bool
        let hasAudioDecoder: Bool
        let hasVideoDecoder: Bool
        let externalLeaseCount: Int
        let openScheduleCount: Int
        let readScheduleCount: Int
        let decodeScheduleCount: Int
        let displayScheduleCount: Int
        let audioMonitorScheduleCount: Int
    }

    private let condition = NSCondition()
    private var phase: Phase = .idle
    private var operationQueue: OperationQueue?
    private var openOperation: Operation?
    private var readOperation: Operation?
    private var decodeOperation: Operation?
    private var displayOperation: Operation?
    private var audioMonitorOperation: Operation?
    private var formatContext: IRFFFormatContext?
    private var audioDecoder: IRFFAudioDecoder?
    private var videoDecoder: IRFFVideoDecoder?
    private var externalLeaseCount = 0
    private var openScheduleCount = 0
    private var readScheduleCount = 0
    private var decodeScheduleCount = 0
    private var displayScheduleCount = 0
    private var audioMonitorScheduleCount = 0
    private let renderAudioLock = NSLock()
    private var renderAudioDecoder: IRFFAudioDecoder?
    private let workerContextKey =
        "IRFFDecoderSession.worker.\(UUID().uuidString)"
    private var deferredRead: (() -> Void)?
    private var deferredDecode: (() -> Void)?
    private var deferredDisplay: (() -> Void)?

    init(operationQueue: OperationQueue = OperationQueue()) {
        operationQueue.maxConcurrentOperationCount = 4
        operationQueue.qualityOfService = .default
        self.operationQueue = operationQueue
    }

    var diagnostics: Diagnostics {
        condition.lock()
        defer { condition.unlock() }
        return Diagnostics(
            phase: phase,
            hasOperationQueue: operationQueue != nil,
            hasOpenOperation: openOperation != nil,
            hasReadOperation: readOperation != nil,
            hasDecodeOperation: decodeOperation != nil,
            hasDisplayOperation: displayOperation != nil,
            hasAudioMonitorOperation:
                audioMonitorOperation != nil,
            hasFormatContext: formatContext != nil,
            hasAudioDecoder: audioDecoder != nil,
            hasVideoDecoder: videoDecoder != nil,
            externalLeaseCount: externalLeaseCount,
            openScheduleCount: openScheduleCount,
            readScheduleCount: readScheduleCount,
            decodeScheduleCount: decodeScheduleCount,
            displayScheduleCount: displayScheduleCount,
            audioMonitorScheduleCount:
                audioMonitorScheduleCount
        )
    }

    var workerResources: Resources {
        condition.lock()
        defer { condition.unlock() }
        return resourcesLocked()
    }

    @discardableResult
    func start(open: @escaping () -> Void) -> Bool {
        condition.lock()
        defer { condition.unlock() }
        guard phase == .idle, let operationQueue else { return false }

        let operation = configuredOperation(role: .open, block: open)
        phase = .opening
        openOperation = operation
        openScheduleCount += 1
        operationQueue.addOperation(operation)
        return true
    }

    @discardableResult
    func installFormatContext(_ formatContext: IRFFFormatContext) -> Bool {
        condition.lock()
        defer { condition.unlock() }
        guard acceptsResourceInstallation, self.formatContext == nil else {
            return false
        }
        self.formatContext = formatContext
        return true
    }

    @discardableResult
    func installAudioDecoder(_ audioDecoder: IRFFAudioDecoder) -> Bool {
        condition.lock()
        defer { condition.unlock() }
        guard acceptsResourceInstallation, self.audioDecoder == nil else {
            return false
        }
        self.audioDecoder = audioDecoder
        renderAudioLock.lock()
        renderAudioDecoder = audioDecoder
        renderAudioLock.unlock()
        return true
    }

    @discardableResult
    func installVideoDecoder(_ videoDecoder: IRFFVideoDecoder) -> Bool {
        condition.lock()
        defer { condition.unlock() }
        guard acceptsResourceInstallation, self.videoDecoder == nil else {
            return false
        }
        self.videoDecoder = videoDecoder
        return true
    }

    func updateVideoDecoderSource(
        _ source: IRFFVideoDecoderDataSource?
    ) {
        condition.lock()
        let videoDecoder = videoDecoder
        condition.unlock()
        videoDecoder?.source = source
    }

    @discardableResult
    func markOpenFailed() -> Bool {
        condition.lock()
        defer { condition.unlock() }
        guard phase == .opening else { return false }
        phase = .failed
        return true
    }

    @discardableResult
    func markOpenSucceeded() -> Bool {
        condition.lock()
        defer { condition.unlock() }
        guard phase == .opening else { return false }
        phase = .active
        return true
    }

    @discardableResult
    func scheduleWorkers(
        includeRead: Bool = true,
        includeVideo: Bool,
        read: @escaping () -> Void,
        decode: @escaping () -> Void,
        display: @escaping () -> Void,
        deferIfRunning: Bool = false
    ) -> Bool {
        condition.lock()
        defer { condition.unlock() }
        guard phase == .opening || phase == .active,
              let operationQueue,
              let openOperation else {
            return false
        }

        var scheduled = false
        if includeRead,
           needsScheduling(readOperation) {
            deferredRead = nil
            enqueueLocked(
                role: .read,
                block: read,
                dependency: openOperation,
                operationQueue: operationQueue
            )
            scheduled = true
        } else if includeRead,
                  deferIfRunning {
            deferredRead = read
            scheduled = true
        }

        if includeVideo, needsScheduling(decodeOperation) {
            deferredDecode = nil
            enqueueLocked(
                role: .decode,
                block: decode,
                dependency: openOperation,
                operationQueue: operationQueue
            )
            scheduled = true
        } else if includeVideo, deferIfRunning {
            deferredDecode = decode
            scheduled = true
        }

        if includeVideo, needsScheduling(displayOperation) {
            deferredDisplay = nil
            enqueueLocked(
                role: .display,
                block: display,
                dependency: openOperation,
                operationQueue: operationQueue
            )
            scheduled = true
        } else if includeVideo, deferIfRunning {
            deferredDisplay = display
            scheduled = true
        }

        phase = .active
        return scheduled
    }

    @discardableResult
    func scheduleAudioMonitor(
        _ monitor: @escaping () -> Void
    ) -> Bool {
        condition.lock()
        defer { condition.unlock() }
        guard phase == .opening || phase == .active,
              let operationQueue,
              let openOperation,
              needsScheduling(audioMonitorOperation) else {
            return false
        }

        let operation = configuredOperation(
            role: .audioMonitor,
            block: monitor
        )
        operation.addDependency(openOperation)
        audioMonitorOperation = operation
        audioMonitorScheduleCount += 1
        operationQueue.addOperation(operation)
        phase = .active
        return true
    }

    func tryDequeueAudioFrame() -> IRFFAudioFrameTransfer? {
        guard renderAudioLock.try() else { return nil }
        let decoder = renderAudioDecoder
        renderAudioLock.unlock()
        return decoder?.tryDequeueFrame()
    }

    func withResources<Result>(
        default defaultValue: Result,
        _ body: (Resources) -> Result
    ) -> Result {
        condition.lock()
        guard phase == .active || phase == .failed else {
            condition.unlock()
            return defaultValue
        }
        externalLeaseCount += 1
        let resources = resourcesLocked()
        condition.unlock()

        defer { releaseExternalLease() }
        return body(resources)
    }

    @discardableResult
    func close() -> Bool {
        condition.lock()
        guard phase != .closing, phase != .closed else {
            condition.unlock()
            return false
        }

        phase = .closing
        let queue = operationQueue
        queue?.cancelAllOperations()
        let resourcesToUnblock = resourcesLocked()
        condition.unlock()

        renderAudioLock.lock()
        renderAudioDecoder = nil
        renderAudioLock.unlock()
        resourcesToUnblock.videoDecoder?.destroy()
        resourcesToUnblock.audioDecoder?.destroy()
        if isCurrentWorker {
            DispatchQueue.global(
                qos: .userInitiated
            ).async { [self] in
                finishClose(queue: queue)
            }
            return true
        }
        finishClose(queue: queue)
        return true
    }

    private func finishClose(
        queue: OperationQueue?
    ) {
        queue?.waitUntilAllOperationsAreFinished()
        condition.lock()
        while externalLeaseCount > 0 {
            condition.wait()
        }
        let resourcesToDestroy = resourcesLocked()
        formatContext = nil
        audioDecoder = nil
        videoDecoder = nil
        openOperation = nil
        readOperation = nil
        decodeOperation = nil
        displayOperation = nil
        audioMonitorOperation = nil
        deferredRead = nil
        deferredDecode = nil
        deferredDisplay = nil
        operationQueue = nil
        phase = .closed
        condition.broadcast()
        condition.unlock()

        resourcesToDestroy.formatContext?.destroy()
    }

    private var acceptsResourceInstallation: Bool {
        phase == .opening || phase == .active
    }

    private func configuredOperation(
        role: OperationRole,
        block: @escaping () -> Void
    ) -> BlockOperation {
        let workerContextKey = workerContextKey
        let operation = BlockOperation {
            let dictionary =
                Thread.current.threadDictionary
            dictionary[workerContextKey] = true
            defer {
                dictionary.removeObject(
                    forKey: workerContextKey
                )
            }
            block()
        }
        operation.name = "IRFFDecoderSession.\(role.rawValue)"
        operation.queuePriority = .veryHigh
        operation.qualityOfService = role.qualityOfService
        operation.completionBlock = {
            [weak self, weak operation] in
            guard let self,
                  let operation else {
                return
            }
            self.operationDidFinish(
                role: role,
                operation: operation
            )
        }
        return operation
    }

    private var isCurrentWorker: Bool {
        Thread.current.threadDictionary[
            workerContextKey
        ] as? Bool == true
    }

    private func enqueueLocked(
        role: OperationRole,
        block: @escaping () -> Void,
        dependency: Operation,
        operationQueue: OperationQueue
    ) {
        let operation = configuredOperation(
            role: role,
            block: block
        )
        operation.addDependency(dependency)
        switch role {
        case .open:
            openOperation = operation
            openScheduleCount += 1
        case .read:
            readOperation = operation
            readScheduleCount += 1
        case .decode:
            decodeOperation = operation
            decodeScheduleCount += 1
        case .display:
            displayOperation = operation
            displayScheduleCount += 1
        case .audioMonitor:
            audioMonitorOperation = operation
            audioMonitorScheduleCount += 1
        }
        operationQueue.addOperation(operation)
    }

    private func operationDidFinish(
        role: OperationRole,
        operation: Operation
    ) {
        condition.lock()
        defer { condition.unlock() }
        guard phase == .opening || phase == .active,
              operationLocked(for: role) === operation,
              let operationQueue,
              let openOperation,
              let deferred =
                takeDeferredLocked(for: role) else {
            return
        }
        enqueueLocked(
            role: role,
            block: deferred,
            dependency: openOperation,
            operationQueue: operationQueue
        )
    }

    private func operationLocked(
        for role: OperationRole
    ) -> Operation? {
        switch role {
        case .open:
            return openOperation
        case .read:
            return readOperation
        case .decode:
            return decodeOperation
        case .display:
            return displayOperation
        case .audioMonitor:
            return audioMonitorOperation
        }
    }

    private func takeDeferredLocked(
        for role: OperationRole
    ) -> (() -> Void)? {
        switch role {
        case .read:
            defer { deferredRead = nil }
            return deferredRead
        case .decode:
            defer { deferredDecode = nil }
            return deferredDecode
        case .display:
            defer { deferredDisplay = nil }
            return deferredDisplay
        case .open, .audioMonitor:
            return nil
        }
    }

    private func needsScheduling(_ operation: Operation?) -> Bool {
        operation?.isFinished ?? true
    }

    private func resourcesLocked() -> Resources {
        Resources(
            formatContext: formatContext,
            audioDecoder: audioDecoder,
            videoDecoder: videoDecoder
        )
    }

    private func releaseExternalLease() {
        condition.lock()
        externalLeaseCount -= 1
        if externalLeaseCount == 0 {
            condition.broadcast()
        }
        condition.unlock()
    }
}
