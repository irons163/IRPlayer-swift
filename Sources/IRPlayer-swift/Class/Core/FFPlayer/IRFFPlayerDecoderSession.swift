import Foundation

final class IRFFPlayerDecoderSession: @unchecked Sendable {
    enum Phase: Equatable {
        case idle
        case active
        case closed
    }

    struct Token: Hashable, Sendable {
        fileprivate let generation: UInt64
    }

    enum Event {
        case willOpenInput
        case prepared
        case endOfFile
        case playbackFinished
        case failed(NSError)
        case bufferingChanged(Bool)
        case bufferedDurationChanged(TimeInterval)
        case progressChanged(TimeInterval)
    }

    private enum EventFence {
        // Opening and preparation describe the installed decoder lifetime.
        // A committed error is also terminal for that lifetime because
        // IRFFDecoder rejects seek admission while the error remains stored.
        case decoderLifetime
        case decodeGeneration(UInt64)
    }

    private struct EventEnvelope {
        let event: Event
        let fence: EventFence

        func isCurrent(for decoder: IRFFDecoder) -> Bool {
            switch fence {
            case .decoderLifetime:
                return true
            case .decodeGeneration(let origin):
                return decoder.decodeGeneration == origin
            }
        }
    }

    struct Configuration {
        let contentURL: URL
        let videoFormat: IRVideoFormat
        let contentHeaders:
            [String: String]
        let videoOutput: (any IRFFDecoderVideoOutput)?
        let audioOutput: (any IRFFDecoderAudioOutput)?
        let source: IRFFVideoInput?
        let hardwareDecoderEnabled: Bool
        let isLiveStream: Bool
        let minimumBufferedDuration: TimeInterval

        init(
            contentURL: URL,
            videoFormat: IRVideoFormat,
            contentHeaders:
                [String: String] = [:],
            videoOutput:
                (any IRFFDecoderVideoOutput)?,
            audioOutput:
                (any IRFFDecoderAudioOutput)?,
            source: IRFFVideoInput?,
            hardwareDecoderEnabled: Bool,
            isLiveStream: Bool,
            minimumBufferedDuration:
                TimeInterval
        ) {
            self.contentURL = contentURL
            self.videoFormat = videoFormat
            self.contentHeaders =
                contentHeaders
            self.videoOutput = videoOutput
            self.audioOutput = audioOutput
            self.source = source
            self.hardwareDecoderEnabled =
                hardwareDecoderEnabled
            self.isLiveStream = isLiveStream
            self.minimumBufferedDuration =
                minimumBufferedDuration
        }
    }

    struct Diagnostics: Equatable {
        let phase: Phase
        let generation: UInt64?
        let hasDecoder: Bool
        let pendingSeekCount: Int
        let activationCount: Int
        let adoptionCount: Int
        let resetCount: Int
        let closeCount: Int
        let acceptedEventCount: Int
        let rejectedEventCount: Int
        let rejectedCommandCount: Int
    }

    typealias DecoderFactory = (
        URL,
        IRVideoFormat,
        [String: String],
        (any IRFFDecoderVideoOutput)?,
        (any IRFFDecoderAudioOutput)?
    ) -> IRFFDecoder
    typealias EventHandler = (Event) -> Void
    typealias ActivationHandler = (IRFFDecoder) -> Void

    private final class SeekTicket: @unchecked Sendable {
        private let lock = NSLock()
        private var completion: ((Bool) -> Void)?

        init(completion: ((Bool) -> Void)?) {
            self.completion = completion
        }

        func finish(_ finished: Bool) {
            lock.lock()
            let completion = completion
            self.completion = nil
            lock.unlock()
            completion?(finished)
        }
    }

    private final class DelegateBridge: IRFFDecoderDelegate {
        weak var session: IRFFPlayerDecoderSession?
        let token: Token

        init(session: IRFFPlayerDecoderSession, token: Token) {
            self.session = session
            self.token = token
        }

        func decoderWillOpenInputStream(_ decoder: IRFFDecoder) {
            session?.deliver(
                .willOpenInput,
                from: decoder,
                token: token,
                fence: .decoderLifetime
            )
        }

        func decoderDidPrepareToDecodeFrames(_ decoder: IRFFDecoder) {
            session?.deliver(
                .prepared,
                from: decoder,
                token: token,
                fence: .decoderLifetime
            )
        }

        func decoderDidEndOfFile(
            _ decoder: IRFFDecoder,
            generation: UInt64
        ) {
            session?.deliver(
                .endOfFile,
                from: decoder,
                token: token,
                fence: .decodeGeneration(generation)
            )
        }

        func decoderDidPlaybackFinished(
            _ decoder: IRFFDecoder,
            generation: UInt64
        ) {
            session?.deliver(
                .playbackFinished,
                from: decoder,
                token: token,
                fence: .decodeGeneration(generation)
            )
        }

        func decoder(
            _ decoder: IRFFDecoder,
            didError error: Error,
            generation: UInt64
        ) {
            session?.deliver(
                .failed(error as NSError),
                from: decoder,
                token: token,
                fence: .decoderLifetime
            )
        }

        func decoder(
            _ decoder: IRFFDecoder,
            didChangeValueOfBuffering buffering: Bool,
            generation: UInt64
        ) {
            session?.deliver(
                .bufferingChanged(buffering),
                from: decoder,
                token: token,
                fence: .decodeGeneration(generation)
            )
        }

        func decoder(
            _ decoder: IRFFDecoder,
            didChangeValueOfBufferedDuration bufferedDuration: TimeInterval,
            generation: UInt64
        ) {
            session?.deliver(
                .bufferedDurationChanged(bufferedDuration),
                from: decoder,
                token: token,
                fence: .decodeGeneration(generation)
            )
        }

        func decoder(
            _ decoder: IRFFDecoder,
            didChangeValueOfProgress progress: TimeInterval,
            generation: UInt64
        ) {
            session?.deliver(
                .progressChanged(progress),
                from: decoder,
                token: token,
                fence: .decodeGeneration(generation)
            )
        }
    }

    private final class OwnedGeneration {
        let token: Token
        let decoder: IRFFDecoder
        let bridge: DelegateBridge
        let eventHandler: EventHandler
        var pendingSeeks: [UUID: SeekTicket] = [:]

        init(
            token: Token,
            decoder: IRFFDecoder,
            bridge: DelegateBridge,
            eventHandler: @escaping EventHandler
        ) {
            self.token = token
            self.decoder = decoder
            self.bridge = bridge
            self.eventHandler = eventHandler
        }
    }

    let executor: IRFFPlayerExecutor
    private let decoderFactory: DecoderFactory

    private var phase: Phase = .idle
    private var generationCounter: UInt64 = 0
    private var generation: OwnedGeneration?
    private var activationCount = 0
    private var adoptionCount = 0
    private var resetCount = 0
    private var closeCount = 0
    private var acceptedEventCount = 0
    private var rejectedEventCount = 0
    private var rejectedCommandCount = 0

    init(
        executor: IRFFPlayerExecutor = IRFFPlayerExecutor(),
        decoderFactory: @escaping DecoderFactory = {
            IRFFDecoder(
                contentURL: $0,
                videoFormat: $1,
                contentHeaders: $2,
                videoOutput: $3,
                audioOutput: $4
            )
        }
    ) {
        self.executor = executor
        self.decoderFactory = decoderFactory
    }

    var diagnostics: Diagnostics {
        executor.sync {
            Diagnostics(
                phase: phase,
                generation: generation?.token.generation,
                hasDecoder: generation != nil,
                pendingSeekCount: generation?.pendingSeeks.count ?? 0,
                activationCount: activationCount,
                adoptionCount: adoptionCount,
                resetCount: resetCount,
                closeCount: closeCount,
                acceptedEventCount: acceptedEventCount,
                rejectedEventCount: rejectedEventCount,
                rejectedCommandCount: rejectedCommandCount
            )
        }
    }

    var currentDecoder: IRFFDecoder? {
        executor.sync {
            guard phase == .active else { return nil }
            return generation?.decoder
        }
    }

    var currentToken: Token? {
        executor.sync {
            guard phase == .active else { return nil }
            return generation?.token
        }
    }

    @discardableResult
    func activate(
        configuration: Configuration,
        eventHandler: @escaping EventHandler,
        didActivate: ActivationHandler = { _ in }
    ) -> Token? {
        executor.sync {
            guard phase != .closed else {
                rejectedCommandCount += 1
                return nil
            }
            drainGenerationLocked()
            guard phase != .closed, generation == nil else {
                rejectedCommandCount += 1
                return nil
            }

            generationCounter &+= 1
            let token = Token(generation: generationCounter)
            let decoder = decoderFactory(
                configuration.contentURL,
                configuration.videoFormat,
                configuration.contentHeaders,
                configuration.videoOutput,
                configuration.audioOutput
            )
            guard phase == .idle, generation == nil else {
                rejectedCommandCount += 1
                discardUnpublishedDecoderLocked(decoder)
                return nil
            }
            decoder.hardwareDecoderEnable =
                configuration.hardwareDecoderEnabled
            decoder.isLiveStream = configuration.isLiveStream
            decoder.minBufferedDuration =
                configuration.minimumBufferedDuration

            let bridge = DelegateBridge(session: self, token: token)
            guard decoder.installCollaborators(
                delegate: bridge,
                source: configuration.source,
                videoOutput: configuration.videoOutput,
                audioOutput: configuration.audioOutput
            ) else {
                rejectedCommandCount += 1
                discardUnpublishedDecoderLocked(decoder)
                return nil
            }
            generation = OwnedGeneration(
                token: token,
                decoder: decoder,
                bridge: bridge,
                eventHandler: eventHandler
            )
            phase = .active
            activationCount += 1

            didActivate(decoder)
            guard isCurrentLocked(token, decoder: decoder) else {
                return nil
            }
            decoder.open()
            guard isCurrentLocked(token, decoder: decoder) else {
                return nil
            }
            return token
        }
    }

    @discardableResult
    func adopt(
        _ decoder: IRFFDecoder,
        eventHandler: @escaping EventHandler,
        didActivate: ActivationHandler = { _ in }
    ) -> Token? {
        executor.sync {
            guard phase != .closed else {
                rejectedCommandCount += 1
                return nil
            }
            drainGenerationLocked()
            guard phase != .closed, generation == nil else {
                rejectedCommandCount += 1
                return nil
            }

            generationCounter &+= 1
            let token = Token(generation: generationCounter)
            let bridge = DelegateBridge(session: self, token: token)
            guard decoder.installDelegatePreservingCollaborators(
                bridge
            ) else {
                rejectedCommandCount += 1
                discardUnpublishedDecoderLocked(decoder)
                return nil
            }
            generation = OwnedGeneration(
                token: token,
                decoder: decoder,
                bridge: bridge,
                eventHandler: eventHandler
            )
            phase = .active
            adoptionCount += 1
            didActivate(decoder)
            return isCurrentLocked(token, decoder: decoder) ? token : nil
        }
    }

    @discardableResult
    func withCurrentDecoder<Result>(
        default defaultValue: Result,
        _ body: (IRFFDecoder) -> Result
    ) -> Result {
        executor.sync {
            guard phase == .active, let decoder = generation?.decoder else {
                return defaultValue
            }
            return body(decoder)
        }
    }

    func seek(
        to time: TimeInterval,
        completion: ((Bool) -> Void)?
    ) {
        executor.sync {
            guard phase == .active, let generation else {
                rejectedCommandCount += 1
                completion?(false)
                return
            }

            let id = UUID()
            let ticket = SeekTicket(completion: completion)
            generation.pendingSeeks[id] = ticket
            let token = generation.token
            let decoder = generation.decoder
            decoder.seek(to: time) { [weak self, weak decoder] finished in
                guard let self, let decoder else {
                    ticket.finish(false)
                    return
                }
                self.executor.async { [weak self, weak decoder] in
                    guard let self, let decoder else {
                        ticket.finish(false)
                        return
                    }
                    self.finishSeek(
                        id: id,
                        token: token,
                        decoder: decoder,
                        finished: finished
                    )
                }
            }
        }
    }

    @discardableResult
    func reset() -> Bool {
        executor.sync {
            guard phase != .closed else {
                rejectedCommandCount += 1
                return false
            }
            guard generation != nil else { return false }
            drainGenerationLocked()
            resetCount += 1
            return true
        }
    }

    @discardableResult
    func close() -> Bool {
        executor.sync {
            guard phase != .closed else { return false }
            phase = .closed
            drainGenerationLocked()
            closeCount += 1
            return true
        }
    }

    func isCurrent(_ token: Token, decoder: IRFFDecoder) -> Bool {
        executor.sync {
            isCurrentLocked(token, decoder: decoder)
        }
    }

    private func deliver(
        _ event: Event,
        from decoder: IRFFDecoder,
        token: Token,
        fence: EventFence
    ) {
        let envelope = EventEnvelope(
            event: event,
            fence: fence
        )
        if executor.isCurrentExecutor {
            executor.sync {
                deliverLocked(
                    envelope,
                    from: decoder,
                    token: token
                )
            }
            return
        }

        // Decoder callbacks may be emitted while the decoder transition gate
        // is held. Never wait for the player executor from that domain: reset,
        // close, or a reentrant seek may need the same transition gate.
        // Identity and decode-generation checks run when the queued event is
        // admitted, after any command already executing on this executor.
        executor.async { [weak self, weak decoder] in
            guard let self else { return }
            guard let decoder else {
                self.rejectEventLocked()
                return
            }
            self.deliverLocked(
                envelope,
                from: decoder,
                token: token
            )
        }
    }

    private func deliverLocked(
        _ envelope: EventEnvelope,
        from decoder: IRFFDecoder,
        token: Token
    ) {
        guard isCurrentLocked(token, decoder: decoder),
              envelope.isCurrent(for: decoder),
              let generation else {
            rejectEventLocked()
            return
        }
        acceptedEventCount += 1
        generation.eventHandler(envelope.event)
    }

    private func rejectEventLocked() {
        rejectedEventCount += 1
    }

    private func finishSeek(
        id: UUID,
        token: Token,
        decoder: IRFFDecoder,
        finished: Bool
    ) {
        guard isCurrentLocked(token, decoder: decoder),
              let ticket = generation?.pendingSeeks.removeValue(forKey: id)
        else {
            return
        }
        ticket.finish(finished)
    }

    private func isCurrentLocked(
        _ token: Token,
        decoder: IRFFDecoder
    ) -> Bool {
        phase == .active &&
            generation?.token == token &&
            generation?.decoder === decoder
    }

    private func drainGenerationLocked() {
        guard let generation else {
            if phase != .closed {
                phase = .idle
            }
            return
        }

        self.generation = nil
        if phase != .closed {
            phase = .idle
        }

        let seekTickets = Array(generation.pendingSeeks.values)
        generation.pendingSeeks.removeAll()
        _ = generation.decoder.revokeCollaborators()
        seekTickets.forEach { $0.finish(false) }
        generation.decoder.closeFile()
    }

    private func discardUnpublishedDecoderLocked(_ decoder: IRFFDecoder) {
        guard generation?.decoder !== decoder else { return }
        _ = decoder.revokeCollaborators()
        decoder.closeFile()
    }

    deinit {
        close()
    }
}
