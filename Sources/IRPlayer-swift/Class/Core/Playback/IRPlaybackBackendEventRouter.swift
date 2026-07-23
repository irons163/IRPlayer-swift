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

final class IRPlaybackBackendEventRouter: @unchecked Sendable {
    struct Diagnostics {
        let activeKind: IRPlaybackBackendKind?
        let generation: UInt64
        let acceptedEventCount: Int
        let rejectedEventCount: Int
    }

    private let lock = NSLock()
    private weak var sink: (any IRPlaybackBackendEventSink)?
    private var activeKind: IRPlaybackBackendKind?
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
            activeKind: activeKind,
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

    func activate(_ kind: IRPlaybackBackendKind?) {
        lock.lock()
        activeKind = kind
        generation &+= 1
        lock.unlock()
    }

    func deliverState(
        from kind: IRPlaybackBackendKind,
        previous: IRPlayerState,
        current: IRPlayerState
    ) {
        guard let sink = admittedSink(for: kind) else { return }
        sink.receiveBackendState(previous: previous, current: current)
    }

    func deliverProgress(
        from kind: IRPlaybackBackendKind,
        current: TimeInterval,
        total: TimeInterval
    ) {
        guard let sink = admittedSink(for: kind) else { return }
        sink.receiveBackendProgress(current: current, total: total)
    }

    func deliverPlayableTime(
        from kind: IRPlaybackBackendKind,
        current: TimeInterval,
        total: TimeInterval
    ) {
        guard let sink = admittedSink(for: kind) else { return }
        sink.receiveBackendPlayableTime(current: current, total: total)
    }

    func deliverFailure(
        from kind: IRPlaybackBackendKind,
        error: IRError
    ) {
        guard let sink = admittedSink(for: kind) else { return }
        sink.receiveBackendFailure(error)
    }

    private func admittedSink(
        for kind: IRPlaybackBackendKind
    ) -> (any IRPlaybackBackendEventSink)? {
        lock.lock()
        defer { lock.unlock() }
        guard activeKind == kind, let sink else {
            rejectedEventCount += 1
            return nil
        }
        acceptedEventCount += 1
        return sink
    }
}

final class IRPlaybackBackendHostAdapter: IRPlaybackBackendHost {
    let kind: IRPlaybackBackendKind

    private weak var context: (any IRPlaybackBackendContext)?
    private let eventRouter: IRPlaybackBackendEventRouter
    private let fallbackDecoder = IRPlayerDecoder.defaultDecoder()

    init(
        kind: IRPlaybackBackendKind,
        context: any IRPlaybackBackendContext,
        eventRouter: IRPlaybackBackendEventRouter
    ) {
        self.kind = kind
        self.context = context
        self.eventRouter = eventRouter
    }

    var contentURL: NSURL? { context?.contentURL }
    var contentHeaders: [String: String]? { context?.contentHeaders }
    var videoType: IRVideoType { context?.videoType ?? .normal }
    var videoInput: IRFFVideoInput? { context?.videoInput }
    var decoder: IRPlayerDecoder { context?.decoder ?? fallbackDecoder }
    var displayView: IRGLView? { context?.displayView }
    var manager: IRAudioManager? { context?.manager }

    var error: IRError? {
        get { context?.error }
        set { context?.error = newValue }
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
        eventRouter.deliverState(
            from: kind,
            previous: previous,
            current: current
        )
    }

    func playbackBackendDidUpdateProgress(
        current: TimeInterval,
        total: TimeInterval
    ) {
        eventRouter.deliverProgress(
            from: kind,
            current: current,
            total: total
        )
    }

    func playbackBackendDidUpdatePlayableTime(
        current: TimeInterval,
        total: TimeInterval
    ) {
        eventRouter.deliverPlayableTime(
            from: kind,
            current: current,
            total: total
        )
    }

    func playbackBackendDidFail(_ error: IRError) {
        eventRouter.deliverFailure(from: kind, error: error)
    }
}
