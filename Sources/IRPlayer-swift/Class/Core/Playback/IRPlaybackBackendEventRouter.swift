import CoreGraphics
import Foundation

protocol IRPlaybackBackendContext: AnyObject {
    var contentURL: NSURL? { get }
    var contentHeaders: [String: String]? { get }
    var videoType: IRVideoType { get }
    var videoInput: IRFFVideoInput? { get }
    var decoder: IRPlayerDecoder { get }
    var displayView: IRGLView? { get }
    var manager: IRAudioManager? { get }
    var error: IRError? { get set }
    var volume: CGFloat { get }
    var playableBufferInterval: TimeInterval { get }
    var isLiveStream: Bool { get }
}

protocol IRPlaybackBackendEventSink: AnyObject {
    func receiveBackendState(
        previous: IRPlayerState,
        current: IRPlayerState
    )
    func receiveBackendProgress(current: TimeInterval, total: TimeInterval)
    func receiveBackendPlayableTime(
        current: TimeInterval,
        total: TimeInterval
    )
    func receiveBackendFailure(_ error: IRError)
}

protocol IRPlaybackBackendSourceUpdating: AnyObject {
    func updateContentHeaders(_ headers: [String: String]?)
}

final class IRPlaybackBackendEventRouter: @unchecked Sendable {
    struct Diagnostics {
        let activeKind: IRPlaybackBackendKind?
        let generation: UInt64
        let acceptedEventCount: Int
        let rejectedEventCount: Int
    }

    private let lock = NSRecursiveLock()
    private weak var sink: (any IRPlaybackBackendEventSink)?
    private var activeActivation: IRPlaybackBackendActivation?
    private var generation: UInt64 = 0
    private var acceptedEventCount = 0
    private var rejectedEventCount = 0

    init(sink: (any IRPlaybackBackendEventSink)? = nil) {
        self.sink = sink
    }

    var diagnostics: Diagnostics {
        lock.lock()
        defer { lock.unlock() }
        return Diagnostics(
            activeKind: activeActivation?.kind,
            generation: generation,
            acceptedEventCount: acceptedEventCount,
            rejectedEventCount: rejectedEventCount
        )
    }

    func setSink(_ sink: (any IRPlaybackBackendEventSink)?) {
        lock.lock()
        self.sink = sink
        lock.unlock()
    }

    func activate(_ activation: IRPlaybackBackendActivation?) {
        lock.lock()
        activeActivation = activation
        generation &+= 1
        lock.unlock()
    }

    func isActive(_ activation: IRPlaybackBackendActivation) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return activeActivation == activation
    }

    func deliverState(
        from activation: IRPlaybackBackendActivation,
        previous: IRPlayerState,
        current: IRPlayerState
    ) {
        deliver(from: activation) {
            $0.receiveBackendState(previous: previous, current: current)
        }
    }

    func deliverProgress(
        from activation: IRPlaybackBackendActivation,
        current: TimeInterval,
        total: TimeInterval
    ) {
        deliver(from: activation) {
            $0.receiveBackendProgress(current: current, total: total)
        }
    }

    func deliverPlayableTime(
        from activation: IRPlaybackBackendActivation,
        current: TimeInterval,
        total: TimeInterval
    ) {
        deliver(from: activation) {
            $0.receiveBackendPlayableTime(current: current, total: total)
        }
    }

    func deliverFailure(
        from activation: IRPlaybackBackendActivation,
        error: IRError
    ) {
        deliver(from: activation) { $0.receiveBackendFailure(error) }
    }

    private func deliver(
        from activation: IRPlaybackBackendActivation,
        action:
            @escaping (any IRPlaybackBackendEventSink) -> Void
    ) {
        IRMainThreadExecutor.execute { [weak self] in
            guard let self else { return }
            self.lock.lock()
            defer { self.lock.unlock() }
            guard self.activeActivation == activation,
                  let sink = self.sink else {
                self.rejectedEventCount += 1
                return
            }
            self.acceptedEventCount += 1
            action(sink)
        }
    }
}

final class IRPlaybackBackendHostAdapter: IRPlaybackBackendHost {
    let kind: IRPlaybackBackendKind
    let activation: IRPlaybackBackendActivation

    private weak var context: (any IRPlaybackBackendContext)?
    private let eventRouter: IRPlaybackBackendEventRouter
    private let storedContentURL: NSURL?
    private let sourceLock = NSLock()
    private var storedContentHeaders: [String: String]?
    private let storedVideoType: IRVideoType
    private let storedVideoInput: IRFFVideoInput?
    private let storedDecoder: IRPlayerDecoder

    init(
        activation: IRPlaybackBackendActivation,
        context: any IRPlaybackBackendContext,
        eventRouter: IRPlaybackBackendEventRouter
    ) {
        self.kind = activation.kind
        self.activation = activation
        self.context = context
        self.eventRouter = eventRouter
        storedContentURL = context.contentURL
        storedContentHeaders = context.contentHeaders
        storedVideoType = context.videoType
        storedVideoInput = context.videoInput
        storedDecoder = context.decoder
    }

    var isCurrentActivation: Bool {
        eventRouter.isActive(activation)
    }

    var contentURL: NSURL? { storedContentURL }
    var contentHeaders: [String: String]? {
        sourceLock.lock()
        defer { sourceLock.unlock() }
        return storedContentHeaders
    }
    var videoType: IRVideoType { storedVideoType }
    var videoInput: IRFFVideoInput? { storedVideoInput }
    var decoder: IRPlayerDecoder { storedDecoder }
    var displayView: IRGLView? { context?.displayView }
    var manager: IRAudioManager? { context?.manager }

    var error: IRError? {
        get { context?.error }
        set {
            guard isCurrentActivation else { return }
            context?.error = newValue
        }
    }

    var volume: CGFloat { context?.volume ?? 0 }
    var playableBufferInterval: TimeInterval {
        context?.playableBufferInterval ?? 0
    }
    var isLiveStream: Bool { context?.isLiveStream ?? false }

    func playbackBackendDidChangeState(
        previous: IRPlayerState,
        current: IRPlayerState
    ) {
        playbackBackendDidChangeState(
            previous: previous,
            current: current,
            activation: activation
        )
    }

    func playbackBackendDidChangeState(
        previous: IRPlayerState,
        current: IRPlayerState,
        activation: IRPlaybackBackendActivation?
    ) {
        guard activation == self.activation else { return }
        eventRouter.deliverState(
            from: self.activation,
            previous: previous,
            current: current
        )
    }

    func playbackBackendDidUpdateProgress(
        current: TimeInterval,
        total: TimeInterval
    ) {
        playbackBackendDidUpdateProgress(
            current: current,
            total: total,
            activation: activation
        )
    }

    func playbackBackendDidUpdateProgress(
        current: TimeInterval,
        total: TimeInterval,
        activation: IRPlaybackBackendActivation?
    ) {
        guard activation == self.activation else { return }
        eventRouter.deliverProgress(
            from: self.activation,
            current: current,
            total: total
        )
    }

    func playbackBackendDidUpdatePlayableTime(
        current: TimeInterval,
        total: TimeInterval
    ) {
        playbackBackendDidUpdatePlayableTime(
            current: current,
            total: total,
            activation: activation
        )
    }

    func playbackBackendDidUpdatePlayableTime(
        current: TimeInterval,
        total: TimeInterval,
        activation: IRPlaybackBackendActivation?
    ) {
        guard activation == self.activation else { return }
        eventRouter.deliverPlayableTime(
            from: self.activation,
            current: current,
            total: total
        )
    }

    func playbackBackendDidFail(_ error: IRError) {
        playbackBackendDidFail(error, activation: activation)
    }

    func playbackBackendDidFail(
        _ error: IRError,
        activation: IRPlaybackBackendActivation?
    ) {
        guard activation == self.activation else { return }
        eventRouter.deliverFailure(
            from: self.activation,
            error: error
        )
    }
}

extension IRPlaybackBackendHostAdapter:
    IRPlaybackBackendSourceUpdating
{
    func updateContentHeaders(_ headers: [String: String]?) {
        sourceLock.lock()
        storedContentHeaders = headers
        sourceLock.unlock()
    }
}
