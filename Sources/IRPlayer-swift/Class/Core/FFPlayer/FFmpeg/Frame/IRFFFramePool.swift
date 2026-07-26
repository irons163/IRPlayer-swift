//
//  IRFFFramePool.swift
//  IRPlayer-swift
//
//  Created by irons on 2024/7/30.
//

import Foundation

final class IRFFFramePool:
    NSObject,
    IRFFFrameDelegate,
    @unchecked Sendable
{
    static let videoMaximumCapacity = 60
    static let audioMaximumCapacity = 500

    enum Phase:
        Equatable,
        Hashable,
        Sendable
    {
        case open
        case closed
    }

    struct Diagnostics:
        Equatable,
        Hashable,
        Sendable
    {
        let phase: Phase
        let maximumCapacity: Int
        let availableCount: Int
        let leasedCount: Int
        let hasPlayingFrame: Bool
        let playingCount: Int
        let totalCount: Int
        let revision: UInt64
    }

    private let frameClassName: AnyClass
    private let frameFactory: () -> IRFFFrame?
    private let maximumCapacity: Int
    private let factoryLock = NSLock()
    private let lock = NSLock()
    private var phase: Phase = .open
    private var ownedFrames:
        [ObjectIdentifier: IRFFFrame] = [:]
    private var availableIDs:
        Set<ObjectIdentifier> = []
    private var leasedIDs:
        Set<ObjectIdentifier> = []
    private var playingIDs:
        Set<ObjectIdentifier> = []
    private var revision: UInt64 = 0

    init(
        capacity: Int,
        frameClassName: AnyClass,
        frameFactory: (() -> IRFFFrame?)? = nil
    ) {
        self.frameClassName = frameClassName
        self.frameFactory =
            frameFactory
            ?? Self.makeFrameFactory(
                for: frameClassName
            )
        self.maximumCapacity = max(0, capacity)
        super.init()

        let reserveCapacity = maximumCapacity
        ownedFrames.reserveCapacity(reserveCapacity)
        availableIDs.reserveCapacity(reserveCapacity)
        leasedIDs.reserveCapacity(reserveCapacity)
        playingIDs.reserveCapacity(reserveCapacity)
    }

    static func videoPool() -> IRFFFramePool {
        IRFFFramePool(
            capacity: videoMaximumCapacity,
            frameClassName: IRFFAVYUVVideoFrame.self
        ) {
            IRFFAVYUVVideoFrame()
        }
    }

    static func audioPool() -> IRFFFramePool {
        IRFFFramePool(
            capacity: audioMaximumCapacity,
            frameClassName: IRFFAudioFrame.self
        ) {
            IRFFAudioFrame()
        }
    }

    var diagnostics: Diagnostics {
        lock.lock()
        defer { lock.unlock() }
        return diagnosticsLocked()
    }

    func leaseFrame() -> IRFFFrame? {
        lock.lock()
        guard phase == .open else {
            lock.unlock()
            return nil
        }
        if let identifier = availableIDs.popFirst(),
           let frame = ownedFrames[identifier] {
            leasedIDs.insert(identifier)
            advanceRevisionLocked()
            lock.unlock()
            return frame
        }
        guard ownedFrames.count < maximumCapacity else {
            lock.unlock()
            return nil
        }
        lock.unlock()

        factoryLock.lock()
        // Another lease may have created or returned a frame while this
        // caller waited for serialized factory access.
        lock.lock()
        guard phase == .open else {
            lock.unlock()
            factoryLock.unlock()
            return nil
        }
        if let identifier = availableIDs.popFirst(),
           let frame = ownedFrames[identifier] {
            leasedIDs.insert(identifier)
            advanceRevisionLocked()
            lock.unlock()
            factoryLock.unlock()
            return frame
        }
        guard ownedFrames.count < maximumCapacity else {
            lock.unlock()
            factoryLock.unlock()
            return nil
        }
        lock.unlock()
        let createdFrame = frameFactory()
        factoryLock.unlock()

        guard let frame = createdFrame,
              isCompatible(frame) else {
            return nil
        }
        let identifier = ObjectIdentifier(frame)

        lock.lock()
        guard phase == .open,
              ownedFrames.count < maximumCapacity,
              ownedFrames[identifier] == nil else {
            lock.unlock()
            return nil
        }
        frame.prepareForReuse()
        frame.delegate = self
        ownedFrames[identifier] = frame
        leasedIDs.insert(identifier)
        advanceRevisionLocked()
        lock.unlock()
        return frame
    }

    @discardableResult
    func flush() -> Int {
        lock.lock()
        lock.unlock()
        // A flush is not an ownership revocation. Queue drains and consumers
        // return their own leases through cancel/stop callbacks. Reclaiming
        // them here can let a decoder overwrite memory still being copied by
        // an audio callback or read by an in-flight GPU command.
        return 0
    }

    @discardableResult
    func close() -> Bool {
        lock.lock()
        guard phase == .open else {
            lock.unlock()
            return false
        }

        phase = .closed
        for frame in ownedFrames.values {
            frame.clearDelegate(ifOwnedBy: self)
        }
        ownedFrames.removeAll()
        availableIDs.removeAll()
        leasedIDs.removeAll()
        playingIDs.removeAll()
        advanceRevisionLocked()
        lock.unlock()
        return true
    }

    // MARK: - IRFFFrameDelegate

    func frameDidStartPlaying(_ frame: IRFFFrame) {
        startPlaying(frame)
    }

    func frameDidStopPlaying(_ frame: IRFFFrame) {
        stopPlaying(frame)
    }

    func frameDidCancel(_ frame: IRFFFrame) {
        returnFrame(frame)
    }

    deinit {
        close()
        IRPlayerImp.Logger.libraryLogger.debug(
            "IRFFFramePool release"
        )
    }

    private static func makeFrameFactory(
        for frameClassName: AnyClass
    ) -> () -> IRFFFrame? {
        {
            guard let frameClass =
                    frameClassName as? NSObject.Type else {
                return nil
            }
            return frameClass.init() as? IRFFFrame
        }
    }

    private func isCompatible(
        _ frame: IRFFFrame
    ) -> Bool {
        frame.isKind(of: frameClassName)
    }

    private func returnFrame(_ frame: IRFFFrame) {
        lock.lock()
        returnFrameLocked(frame)
        lock.unlock()
    }

    private func startPlaying(_ frame: IRFFFrame) {
        let identifier = ObjectIdentifier(frame)

        lock.lock()
        guard phase == .open,
              ownedFrames[identifier] === frame,
              leasedIDs.contains(identifier) else {
            if availableIDs.contains(identifier) {
                frame.prepareForReuse()
            }
            lock.unlock()
            return
        }

        leasedIDs.remove(identifier)
        availableIDs.remove(identifier)
        playingIDs.insert(identifier)
        advanceRevisionLocked()
        lock.unlock()
    }

    private func stopPlaying(_ frame: IRFFFrame) {
        let identifier = ObjectIdentifier(frame)

        lock.lock()
        guard phase == .open,
              ownedFrames[identifier] === frame,
              playingIDs.contains(identifier) else {
            lock.unlock()
            return
        }
        frame.prepareForReuse()
        availableIDs.insert(identifier)
        playingIDs.remove(identifier)
        advanceRevisionLocked()
        lock.unlock()
    }

    private func returnFrameLocked(
        _ frame: IRFFFrame
    ) {
        let identifier = ObjectIdentifier(frame)
        guard phase == .open,
              ownedFrames[identifier] === frame,
              leasedIDs.contains(identifier)
                || playingIDs.contains(identifier) else {
            return
        }

        frame.prepareForReuse()
        leasedIDs.remove(identifier)
        playingIDs.remove(identifier)
        availableIDs.insert(identifier)
        advanceRevisionLocked()
    }

    private func diagnosticsLocked() -> Diagnostics {
        Diagnostics(
            phase: phase,
            maximumCapacity: maximumCapacity,
            availableCount: availableIDs.count,
            leasedCount: leasedIDs.count,
            hasPlayingFrame: !playingIDs.isEmpty,
            playingCount: playingIDs.count,
            totalCount: ownedFrames.count,
            revision: revision
        )
    }

    private func advanceRevisionLocked() {
        revision &+= 1
    }
}
