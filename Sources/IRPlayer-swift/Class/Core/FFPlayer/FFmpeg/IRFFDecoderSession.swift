import Foundation

final class IRFFDecoderSession: @unchecked Sendable {
    private enum OperationRole: String {
        case open
        case read
        case decode
        case display

        var qualityOfService: QualityOfService {
            switch self {
            case .decode, .display:
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
        let hasFormatContext: Bool
        let hasAudioDecoder: Bool
        let hasVideoDecoder: Bool
        let externalLeaseCount: Int
        let openScheduleCount: Int
        let readScheduleCount: Int
        let decodeScheduleCount: Int
        let displayScheduleCount: Int
    }

    private let condition = NSCondition()
    private var phase: Phase = .idle
    private var operationQueue: OperationQueue?
    private var openOperation: Operation?
    private var readOperation: Operation?
    private var decodeOperation: Operation?
    private var displayOperation: Operation?
    private var formatContext: IRFFFormatContext?
    private var audioDecoder: IRFFAudioDecoder?
    private var videoDecoder: IRFFVideoDecoder?
    private var externalLeaseCount = 0
    private var openScheduleCount = 0
    private var readScheduleCount = 0
    private var decodeScheduleCount = 0
    private var displayScheduleCount = 0

    init(operationQueue: OperationQueue = OperationQueue()) {
        operationQueue.maxConcurrentOperationCount = 3
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
            hasFormatContext: formatContext != nil,
            hasAudioDecoder: audioDecoder != nil,
            hasVideoDecoder: videoDecoder != nil,
            externalLeaseCount: externalLeaseCount,
            openScheduleCount: openScheduleCount,
            readScheduleCount: readScheduleCount,
            decodeScheduleCount: decodeScheduleCount,
            displayScheduleCount: displayScheduleCount
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
        includeVideo: Bool,
        read: @escaping () -> Void,
        decode: @escaping () -> Void,
        display: @escaping () -> Void
    ) -> Bool {
        condition.lock()
        defer { condition.unlock() }
        guard phase == .opening || phase == .active,
              let operationQueue,
              let openOperation else {
            return false
        }

        var scheduled = false
        if needsScheduling(readOperation) {
            let operation = configuredOperation(role: .read, block: read)
            operation.addDependency(openOperation)
            readOperation = operation
            readScheduleCount += 1
            operationQueue.addOperation(operation)
            scheduled = true
        }

        if includeVideo, needsScheduling(decodeOperation) {
            let operation = configuredOperation(role: .decode, block: decode)
            operation.addDependency(openOperation)
            decodeOperation = operation
            decodeScheduleCount += 1
            operationQueue.addOperation(operation)
            scheduled = true
        }

        if includeVideo, needsScheduling(displayOperation) {
            let operation = configuredOperation(role: .display, block: display)
            operation.addDependency(openOperation)
            displayOperation = operation
            displayScheduleCount += 1
            operationQueue.addOperation(operation)
            scheduled = true
        }

        phase = .active
        return scheduled
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

        resourcesToUnblock.videoDecoder?.destroy()
        resourcesToUnblock.audioDecoder?.destroy()
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
        operationQueue = nil
        phase = .closed
        condition.broadcast()
        condition.unlock()

        resourcesToDestroy.formatContext?.destroy()
        return true
    }

    private var acceptsResourceInstallation: Bool {
        phase == .opening || phase == .active
    }

    private func configuredOperation(
        role: OperationRole,
        block: @escaping () -> Void
    ) -> BlockOperation {
        let operation = BlockOperation(block: block)
        operation.name = "IRFFDecoderSession.\(role.rawValue)"
        operation.queuePriority = .veryHigh
        operation.qualityOfService = role.qualityOfService
        return operation
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
