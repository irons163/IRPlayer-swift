//
//  IRFFDecoderCollaboratorSession.swift
//  IRPlayer-swift
//
//  Created by Codex on 2026/7/24.
//

import Foundation

final class IRFFDecoderCollaboratorSession:
    @unchecked Sendable
{
    enum Phase: Equatable {
        case active
        case revoked
    }

    struct Configuration {
        let delegate: IRFFDecoderDelegate?
        let source: IRFFVideoDecoderDataSource?
        let videoOutput: IRFFDecoderVideoOutput?
        let audioOutput: IRFFDecoderAudioOutput?
    }

    struct Snapshot {
        let delegate: IRFFDecoderDelegate?
        let source: IRFFVideoDecoderDataSource?
        let videoOutput: IRFFDecoderVideoOutput?
        let audioOutput: IRFFDecoderAudioOutput?
    }

    struct Diagnostics: Equatable {
        let phase: Phase
        let generation: UInt64
        let hasDelegate: Bool
        let hasSource: Bool
        let hasVideoOutput: Bool
        let hasAudioOutput: Bool
        let installCount: Int
        let revokeCount: Int
        let acceptedVideoDeliveryCount: Int
        let rejectedVideoDeliveryCount: Int
        let rejectedUpdateCount: Int
    }

    private let lock = NSRecursiveLock()
    private var phase: Phase = .active
    private var generation: UInt64 = 1
    private weak var delegate: IRFFDecoderDelegate?
    private weak var source: IRFFVideoDecoderDataSource?
    private weak var videoOutput: IRFFDecoderVideoOutput?
    private weak var audioOutput: IRFFDecoderAudioOutput?
    private var installCount = 1
    private var revokeCount = 0
    private var acceptedVideoDeliveryCount = 0
    private var rejectedVideoDeliveryCount = 0
    private var rejectedUpdateCount = 0

    init(configuration: Configuration) {
        let delegate = configuration.delegate
        let source = configuration.source
        let videoOutput = configuration.videoOutput
        let audioOutput = configuration.audioOutput
        self.delegate = delegate
        self.source = source
        self.videoOutput = videoOutput
        self.audioOutput = audioOutput
        // A temporary configuration may contain protocol existential
        // containers. Keep them alive through weak publication under WMO.
        withExtendedLifetime(
            (delegate, source, videoOutput, audioOutput)
        ) {}
    }

    var diagnostics: Diagnostics {
        lock.lock()
        defer { lock.unlock() }
        return Diagnostics(
            phase: phase,
            generation: generation,
            hasDelegate: delegate != nil,
            hasSource: source != nil,
            hasVideoOutput: videoOutput != nil,
            hasAudioOutput: audioOutput != nil,
            installCount: installCount,
            revokeCount: revokeCount,
            acceptedVideoDeliveryCount:
                acceptedVideoDeliveryCount,
            rejectedVideoDeliveryCount:
                rejectedVideoDeliveryCount,
            rejectedUpdateCount: rejectedUpdateCount
        )
    }

    var snapshot: Snapshot {
        lock.lock()
        defer { lock.unlock() }
        return Snapshot(
            delegate: phase == .active ? delegate : nil,
            source: phase == .active ? source : nil,
            videoOutput: phase == .active
                ? videoOutput
                : nil,
            audioOutput: phase == .active
                ? audioOutput
                : nil
        )
    }

    @discardableResult
    func install(
        _ configuration: Configuration,
        didInstall: (Snapshot) -> Void = { _ in }
    ) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard phase == .active else {
            rejectedUpdateCount += 1
            return false
        }
        let delegate = configuration.delegate
        let source = configuration.source
        let videoOutput = configuration.videoOutput
        let audioOutput = configuration.audioOutput
        generation &+= 1
        self.delegate = delegate
        self.source = source
        self.videoOutput = videoOutput
        self.audioOutput = audioOutput
        installCount += 1
        didInstall(makeSnapshotLocked())
        // Match initializer publication when the caller passes a temporary.
        withExtendedLifetime(
            (delegate, source, videoOutput, audioOutput)
        ) {}
        return true
    }

    @discardableResult
    func installDelegatePreservingCollaborators(
        _ delegate: IRFFDecoderDelegate,
        didInstall: (Snapshot) -> Void = { _ in }
    ) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard phase == .active else {
            rejectedUpdateCount += 1
            return false
        }
        generation &+= 1
        self.delegate = delegate
        installCount += 1
        didInstall(makeSnapshotLocked())
        return true
    }

    @discardableResult
    func updateDelegate(
        _ delegate: IRFFDecoderDelegate?
    ) -> Bool {
        update {
            self.delegate = delegate
        }
    }

    @discardableResult
    func updateSource(
        _ source: IRFFVideoDecoderDataSource?,
        didUpdate: (IRFFVideoDecoderDataSource?) -> Void = { _ in }
    ) -> Bool {
        update {
            self.source = source
            didUpdate(source)
        }
    }

    @discardableResult
    func updateVideoOutput(
        _ videoOutput: IRFFDecoderVideoOutput?
    ) -> Bool {
        update {
            self.videoOutput = videoOutput
        }
    }

    @discardableResult
    func updateAudioOutput(
        _ audioOutput: IRFFDecoderAudioOutput?
    ) -> Bool {
        update {
            self.audioOutput = audioOutput
        }
    }

    @discardableResult
    func revoke(
        didRevoke: () -> Void = {}
    ) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard phase == .active else { return false }
        phase = .revoked
        generation &+= 1
        delegate = nil
        source = nil
        videoOutput = nil
        audioOutput = nil
        revokeCount += 1
        didRevoke()
        return true
    }

    func withSnapshot<Result>(
        default defaultValue: Result,
        _ body: (Snapshot) -> Result
    ) -> Result {
        lock.lock()
        defer { lock.unlock() }
        guard phase == .active else { return defaultValue }
        return body(makeSnapshotLocked())
    }

    func withDelegate<Result>(
        default defaultValue: Result,
        _ body: (IRFFDecoderDelegate) -> Result
    ) -> Result {
        lock.lock()
        guard phase == .active, let delegate else {
            lock.unlock()
            return defaultValue
        }
        lock.unlock()
        return body(delegate)
    }

    @discardableResult
    func deliverVideoFrame(_ frame: IRFFVideoFrame) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard phase == .active, let videoOutput else {
            rejectedVideoDeliveryCount += 1
            return false
        }
        acceptedVideoDeliveryCount += 1
        videoOutput.send?(videoFrame: frame)
        return true
    }

    func withAudioOutput<Result>(
        default defaultValue: Result,
        _ body: (IRFFDecoderAudioOutput) -> Result
    ) -> Result {
        lock.lock()
        guard phase == .active, let audioOutput else {
            lock.unlock()
            return defaultValue
        }
        lock.unlock()
        return body(audioOutput)
    }

    private func update(_ mutation: () -> Void) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard phase == .active else {
            rejectedUpdateCount += 1
            return false
        }
        mutation()
        return true
    }

    private func makeSnapshotLocked() -> Snapshot {
        Snapshot(
            delegate: delegate,
            source: source,
            videoOutput: videoOutput,
            audioOutput: audioOutput
        )
    }
}
