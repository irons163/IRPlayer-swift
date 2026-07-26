//
//  IRFFFormatContext.swift
//  IRPlayer-swift
//
//  Created by irons on 2024/7/12.
//

import CoreGraphics
import Darwin
import Foundation
#if SWIFT_PACKAGE || DEBUG
internal import IRFFMpeg
internal import IRPlayerObjc
#else
@_implementationOnly import IRFFMpeg
@_implementationOnly import IRPlayerObjc
#endif

public protocol IRFFFormatContextDelegate: AnyObject {
    func formatContextNeedInterrupt(_ formatContext: IRFFFormatContext) -> Bool
}

struct IRFFFormatContextRuntime {
    let makeGeneration: (
        URL,
        IRVideoFormat,
        [String: String],
        IRFFFormatContextInterruptState
    ) -> Result<IRFFFormatContextGeneration, NSError>
    let seekFrame: (
        UnsafeMutablePointer<AVFormatContext>,
        Int64
    ) -> Int32
    let readFrame: (
        UnsafeMutablePointer<AVFormatContext>,
        UnsafeMutablePointer<AVPacket>
    ) -> Int32

    static let live = IRFFFormatContextRuntime(
        makeGeneration: {
            contentURL,
            videoFormat,
            contentHeaders,
            interruptState in
            IRFFFormatContextBuilder.makeGeneration(
                contentURL: contentURL,
                videoFormat: videoFormat,
                contentHeaders:
                    contentHeaders,
                interruptState: interruptState
            )
        },
        seekFrame: { formatContext, timestamp in
            av_seek_frame(
                formatContext,
                -1,
                timestamp,
                AVSEEK_FLAG_BACKWARD
            )
        },
        readFrame: { formatContext, packet in
            av_read_frame(formatContext, packet)
        }
    )
}

public final class IRFFFormatContext: @unchecked Sendable {
    enum Phase: Equatable {
        case idle
        case opening
        case active
        case failed
        case closing
        case closed
    }

    enum AudioTrackSelectionAction: Equatable {
        case noChange
        case select
    }

    struct AudioTrackSelectionResult {
        let error: NSError?
        let didChangeTrack: Bool
    }

    struct Diagnostics: Equatable {
        let phase: Phase
        let hasGeneration: Bool
        let hasFormatContext: Bool
        let hasVideoCodecContext: Bool
        let hasAudioCodecContext: Bool
        let interruptCloseRequested: Bool
    }

    private enum OperationKind: Equatable {
        case setup
        case read
        case seek
        case selectAudioTrack
        case destroyAudioTrack
        case destroyVideoTrack
    }

    private struct OperationTicket {
        let identifier: UInt64
        let owner: UInt32
        let kind: OperationKind
    }

    private struct GenerationOperation {
        let ticket: OperationTicket
        let generation: IRFFFormatContextGeneration
    }

    private struct ResourcePresence {
        var hasFormatContext = false
        var hasVideoCodecContext = false
        var hasAudioCodecContext = false

        init() {}

        init(_ diagnostics: IRFFFormatContextGeneration.Diagnostics) {
            hasFormatContext = diagnostics.hasFormatContext
            hasVideoCodecContext =
                diagnostics.hasVideoCodecContext
            hasAudioCodecContext =
                diagnostics.hasAudioCodecContext
        }
    }

    private struct PublishedSnapshot {
        var metadata: [AnyHashable: Any] = [:]
        var bitrate: TimeInterval = 0
        var duration: TimeInterval = 0
        var videoTrack: IRFFTrack?
        var audioTrack: IRFFTrack?
        var videoTracks: [IRFFTrack] = []
        var audioTracks: [IRFFTrack] = []
        var videoTimebase: TimeInterval = 0
        var videoFPS: TimeInterval = 0
        var videoPresentationSize: CGSize = .zero
        var videoAspect: CGFloat = 0
        var audioTimebase: TimeInterval = 0
        var videoCodecContext:
            UnsafeMutablePointer<AVCodecContext>?
        var audioCodecContext:
            UnsafeMutablePointer<AVCodecContext>?
        var resourcePresence = ResourcePresence()

        init() {}

        init(generation: IRFFFormatContextGeneration) {
            metadata = generation.metadata
            videoTrack = generation.videoTrack
            audioTrack = generation.audioTrack
            videoTracks = generation.videoTracks
            audioTracks = generation.audioTracks
            videoTimebase = generation.videoTimebase
            videoFPS = generation.videoFPS
            videoPresentationSize =
                generation.videoPresentationSize
            videoAspect = generation.videoAspect
            audioTimebase = generation.audioTimebase
            videoCodecContext = generation.videoCodecContext
            audioCodecContext = generation.audioCodecContext
            resourcePresence = ResourcePresence(
                generation.diagnostics
            )

            if let formatContext = generation.formatContext {
                bitrate = IRFFFormatContext.bitrateKbps(
                    from: formatContext.pointee.bit_rate
                )
                duration = IRFFFormatContext.durationSeconds(
                    from: formatContext.pointee.duration
                )
            }
        }
    }

    private let contentURL: URL
    private let videoFormat: IRVideoFormat
    private let contentHeaders:
        [String: String]
    private let runtime: IRFFFormatContextRuntime
    private let stateCondition = NSCondition()
    private let interruptState = IRFFFormatContextInterruptState()

    private var phase: Phase = .idle
    private var generation: IRFFFormatContextGeneration?
    private var storedError: NSError?
    private var snapshot = PublishedSnapshot()
    private var resourcePresence = ResourcePresence()
    private var activeOperation: OperationTicket?
    private var nextOperationIdentifier: UInt64 = 0
    private var closeRequested = false
    private var teardownInProgress = false
    private var teardownOwner: UInt32?

    var delegate: IRFFFormatContextDelegate? {
        get { interruptState.currentDelegate }
        set { interruptState.setDelegate(newValue) }
    }

    var diagnostics: Diagnostics {
        let state = withState {
            (
                phase: phase,
                hasGeneration: generation != nil,
                resourcePresence: resourcePresence
            )
        }
        let interruptDiagnostics = interruptState.diagnostics
        return Diagnostics(
            phase: state.phase,
            hasGeneration: state.hasGeneration,
            hasFormatContext:
                state.resourcePresence.hasFormatContext,
            hasVideoCodecContext:
                state.resourcePresence.hasVideoCodecContext,
            hasAudioCodecContext:
                state.resourcePresence.hasAudioCodecContext,
            interruptCloseRequested:
                interruptDiagnostics.closeRequested
        )
    }

    var error: NSError? {
        withState { storedError }
    }

    var metadata: [AnyHashable: Any] {
        withState { snapshot.metadata }
    }

    var bitrate: TimeInterval {
        withState { snapshot.bitrate }
    }

    var duration: TimeInterval {
        withState { snapshot.duration }
    }

    var videoEnable: Bool {
        withState { snapshot.videoCodecContext != nil }
    }

    var audioEnable: Bool {
        withState { snapshot.audioCodecContext != nil }
    }

    var videoTrack: IRFFTrack? {
        withState { snapshot.videoTrack }
    }

    var audioTrack: IRFFTrack? {
        withState { snapshot.audioTrack }
    }

    var videoTracks: [IRFFTrack] {
        withState { snapshot.videoTracks }
    }

    var audioTracks: [IRFFTrack] {
        withState { snapshot.audioTracks }
    }

    var videoTimebase: TimeInterval {
        withState { snapshot.videoTimebase }
    }

    var videoFPS: TimeInterval {
        withState { snapshot.videoFPS }
    }

    var videoPresentationSize: CGSize {
        withState { snapshot.videoPresentationSize }
    }

    var videoAspect: CGFloat {
        withState { snapshot.videoAspect }
    }

    var audioTimebase: TimeInterval {
        withState { snapshot.audioTimebase }
    }

    var videoCodecContext: UnsafeMutablePointer<AVCodecContext>? {
        withState { snapshot.videoCodecContext }
    }

    var audioCodecContext: UnsafeMutablePointer<AVCodecContext>? {
        withState { snapshot.audioCodecContext }
    }

    init(
        contentURL: URL,
        videoFormat: IRVideoFormat,
        contentHeaders:
            [String: String] = [:],
        runtime: IRFFFormatContextRuntime = .live
    ) {
        self.contentURL = contentURL
        self.videoFormat = videoFormat
        self.contentHeaders =
            contentHeaders
        self.runtime = runtime
        interruptState.bind(context: self)
    }

    func setupSync() {
        guard interruptState.prepareForSetup(),
              let ticket = beginSetupOperation() else {
            return
        }

        let result = runtime.makeGeneration(
            contentURL,
            videoFormat,
            contentHeaders,
            interruptState
        )
        finishSetupOperation(ticket, result: result)
    }

    @discardableResult
    func seekFile(withFFTimebase time: TimeInterval) -> Bool {
        guard let timestamp = Self.seekTimestamp(for: time),
              let operation = beginGenerationOperation(.seek) else {
            return false
        }
        guard let formatContext =
                operation.generation.formatContext else {
            finishGenerationOperation(operation)
            return false
        }

        let result = runtime.seekFrame(formatContext, timestamp)
        finishGenerationOperation(operation)
        return result >= 0
    }

    func readFrame(_ packet: UnsafeMutablePointer<AVPacket>) -> Int32 {
        guard let operation = beginGenerationOperation(.read) else {
            return -1
        }
        guard let formatContext =
                operation.generation.formatContext else {
            finishGenerationOperation(operation)
            return -1
        }

        let result = runtime.readFrame(formatContext, packet)
        finishGenerationOperation(operation)
        return result
    }

    func containAudioTrack(_ audioTrackIndex: Int) -> Bool {
        withState {
            snapshot.audioTracks.contains {
                $0.index == audioTrackIndex
            }
        }
    }

    func selectAudioTrackIndexResult(
        _ audioTrackIndex: Int
    ) -> AudioTrackSelectionResult {
        guard let operation = beginGenerationOperation(
            .selectAudioTrack
        ) else {
            return AudioTrackSelectionResult(
                error: nil,
                didChangeTrack: false
            )
        }
        let generation = operation.generation

        let containsRequestedTrack = generation.audioTracks.contains {
            $0.index == audioTrackIndex
        }
        guard Self.audioTrackSelectionAction(
            requestedIndex: audioTrackIndex,
            currentIndex: generation.audioTrack?.index,
            containsRequestedTrack: containsRequestedTrack
        ) == .select else {
            finishGenerationOperation(operation)
            return AudioTrackSelectionResult(
                error: nil,
                didChangeTrack: false
            )
        }

        let candidate = IRFFFormatContextBuilder.makeCodecContext(
            trackIndex: audioTrackIndex,
            in: generation.formatContext,
            domain: "audio select"
        )
        switch candidate {
        case let .success(codecContext):
            generation.replaceAudioCodecContext(
                with: codecContext
            )
            generation.audioTrack = generation.audioTracks.first {
                $0.index == audioTrackIndex
            }
            if let stream = Self.stream(
                at: audioTrackIndex,
                in: generation.formatContext
            ) {
                generation.audioTimebase = IRFFStreamGetTimebase(
                    stream,
                    defaultTimebase: 0.000025
                )
            }
            finishGenerationOperation(
                operation,
                refreshSnapshot: true
            )
            return AudioTrackSelectionResult(
                error: nil,
                didChangeTrack: true
            )
        case let .failure(error):
            IRFFRuntimeDebugOutput.write(
                "select audio track error: \(error)"
            )
            finishGenerationOperation(operation)
            return AudioTrackSelectionResult(
                error: error,
                didChangeTrack: false
            )
        }
    }

    func selectAudioTrackIndex(_ audioTrackIndex: Int) -> NSError? {
        selectAudioTrackIndexResult(audioTrackIndex).error
    }

    var contentURLString: String {
        contentURL.isFileURL
            ? contentURL.path
            : contentURL.absoluteString
    }

    @discardableResult
    func destroyAudioTrack() -> Bool {
        guard let operation = beginGenerationOperation(
            .destroyAudioTrack
        ) else {
            return false
        }
        operation.generation.destroyAudioTrack()
        finishGenerationOperation(
            operation,
            refreshSnapshot: true
        )
        return true
    }

    @discardableResult
    func destroyVideoTrack() -> Bool {
        guard let operation = beginGenerationOperation(
            .destroyVideoTrack
        ) else {
            return false
        }
        operation.generation.destroyVideoTrack()
        finishGenerationOperation(
            operation,
            refreshSnapshot: true
        )
        return true
    }

    func destroy() {
        interruptState.requestClose()
        let owner = Self.currentOperationOwner
        var generationToClose: IRFFFormatContextGeneration?

        stateCondition.lock()
        guard phase != .closed else {
            stateCondition.unlock()
            return
        }

        closeRequested = true
        phase = .closing
        snapshot = PublishedSnapshot()
        stateCondition.broadcast()

        if activeOperation?.owner == owner {
            stateCondition.unlock()
            return
        }

        while activeOperation != nil {
            stateCondition.wait()
            if phase == .closed {
                stateCondition.unlock()
                return
            }
        }

        if teardownInProgress {
            if teardownOwner == owner {
                stateCondition.unlock()
                return
            }
            while phase != .closed {
                stateCondition.wait()
            }
            stateCondition.unlock()
            return
        }

        generationToClose = beginTeardownLocked(owner: owner)
        stateCondition.unlock()
        finishTeardown(generationToClose, owner: owner)
    }

    private func beginSetupOperation() -> OperationTicket? {
        stateCondition.lock()
        defer { stateCondition.unlock() }
        guard phase == .idle,
              !closeRequested,
              activeOperation == nil else {
            return nil
        }

        let ticket = makeOperationTicketLocked(.setup)
        activeOperation = ticket
        phase = .opening
        storedError = nil
        return ticket
    }

    private func finishSetupOperation(
        _ ticket: OperationTicket,
        result: Result<IRFFFormatContextGeneration, NSError>
    ) {
        var generationToClose: IRFFFormatContextGeneration?

        stateCondition.lock()
        guard activeOperation?.identifier == ticket.identifier,
              activeOperation?.kind == ticket.kind else {
            stateCondition.unlock()
            if case let .success(generation) = result {
                generation.close()
            }
            return
        }

        activeOperation = nil
        if closeRequested {
            if case let .success(generation) = result {
                generationToClose = generation
            }
            beginTeardownWithoutStoredGenerationLocked(
                owner: ticket.owner
            )
        } else {
            switch result {
            case let .success(generation):
                self.generation = generation
                publishSnapshotLocked(for: generation)
                phase = .active
            case let .failure(error):
                storedError = error
                snapshot = PublishedSnapshot()
                resourcePresence = ResourcePresence()
                phase = .failed
            }
        }
        stateCondition.broadcast()
        let shouldFinishTeardown = teardownInProgress
            && teardownOwner == ticket.owner
        stateCondition.unlock()

        if shouldFinishTeardown {
            finishTeardown(
                generationToClose,
                owner: ticket.owner
            )
        }
    }

    private func beginGenerationOperation(
        _ kind: OperationKind
    ) -> GenerationOperation? {
        let owner = Self.currentOperationOwner
        stateCondition.lock()
        while phase == .active, activeOperation != nil {
            if activeOperation?.owner == owner {
                stateCondition.unlock()
                return nil
            }
            stateCondition.wait()
        }
        guard phase == .active,
              !closeRequested,
              activeOperation == nil,
              let generation else {
            stateCondition.unlock()
            return nil
        }

        let ticket = makeOperationTicketLocked(kind, owner: owner)
        activeOperation = ticket
        stateCondition.unlock()
        return GenerationOperation(
            ticket: ticket,
            generation: generation
        )
    }

    private func finishGenerationOperation(
        _ operation: GenerationOperation,
        refreshSnapshot: Bool = false
    ) {
        var generationToClose: IRFFFormatContextGeneration?

        stateCondition.lock()
        guard activeOperation?.identifier
                == operation.ticket.identifier,
              activeOperation?.kind
                == operation.ticket.kind else {
            stateCondition.unlock()
            return
        }

        if refreshSnapshot, !closeRequested, phase == .active {
            publishSnapshotLocked(for: operation.generation)
        }
        activeOperation = nil
        if closeRequested {
            generationToClose = beginTeardownLocked(
                owner: operation.ticket.owner
            )
        }
        stateCondition.broadcast()
        let shouldFinishTeardown = teardownInProgress
            && teardownOwner == operation.ticket.owner
        stateCondition.unlock()

        if shouldFinishTeardown {
            finishTeardown(
                generationToClose,
                owner: operation.ticket.owner
            )
        }
    }

    private func publishSnapshotLocked(
        for generation: IRFFFormatContextGeneration
    ) {
        let snapshot = PublishedSnapshot(generation: generation)
        self.snapshot = snapshot
        resourcePresence = snapshot.resourcePresence
    }

    private func beginTeardownLocked(
        owner: UInt32
    ) -> IRFFFormatContextGeneration? {
        guard !teardownInProgress else { return nil }
        teardownInProgress = true
        teardownOwner = owner
        return generation
    }

    private func beginTeardownWithoutStoredGenerationLocked(
        owner: UInt32
    ) {
        guard !teardownInProgress else { return }
        teardownInProgress = true
        teardownOwner = owner
        generation = nil
    }

    private func finishTeardown(
        _ generation: IRFFFormatContextGeneration?,
        owner: UInt32
    ) {
        generation?.close()

        stateCondition.lock()
        guard teardownInProgress,
              teardownOwner == owner else {
            stateCondition.unlock()
            return
        }
        self.generation = nil
        snapshot = PublishedSnapshot()
        resourcePresence = ResourcePresence()
        phase = .closed
        teardownInProgress = false
        teardownOwner = nil
        stateCondition.broadcast()
        stateCondition.unlock()
    }

    private func makeOperationTicketLocked(
        _ kind: OperationKind,
        owner: UInt32 =
            IRFFFormatContext.currentOperationOwner
    ) -> OperationTicket {
        nextOperationIdentifier &+= 1
        return OperationTicket(
            identifier: nextOperationIdentifier,
            owner: owner,
            kind: kind
        )
    }

    private func withState<Result>(
        _ body: () throws -> Result
    ) rethrows -> Result {
        stateCondition.lock()
        defer { stateCondition.unlock() }
        return try body()
    }

    private static var currentOperationOwner: UInt32 {
        pthread_mach_thread_np(pthread_self())
    }

    deinit {
        destroy()
    }
}

func ffmpeg_interrupt_callback(
    ctx: UnsafeMutableRawPointer?
) -> Int32 {
    guard let ctx else { return 0 }
    let interruptState =
        Unmanaged<IRFFFormatContextInterruptState>
            .fromOpaque(ctx)
            .takeUnretainedValue()
    return interruptState.shouldInterrupt() ? 1 : 0
}
