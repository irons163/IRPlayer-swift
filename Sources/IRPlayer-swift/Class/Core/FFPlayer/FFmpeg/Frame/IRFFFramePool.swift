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
        let availableCount: Int
        let leasedCount: Int
        let hasPlayingFrame: Bool
        let totalCount: Int
        let revision: UInt64
    }

    private let frameClassName: AnyClass
    private let frameFactory: () -> IRFFFrame?
    private let factoryLock = NSLock()
    private let lock = NSLock()
    private var phase: Phase = .open
    private var ownedFrames:
        [ObjectIdentifier: IRFFFrame] = [:]
    private var availableIDs:
        Set<ObjectIdentifier> = []
    private var leasedIDs:
        Set<ObjectIdentifier> = []
    private var playingID: ObjectIdentifier?
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
        super.init()

        let reserveCapacity = max(0, capacity)
        ownedFrames.reserveCapacity(reserveCapacity)
        availableIDs.reserveCapacity(reserveCapacity)
        leasedIDs.reserveCapacity(reserveCapacity)
    }

    static func videoPool() -> IRFFFramePool {
        IRFFFramePool(
            capacity: 60,
            frameClassName: IRFFAVYUVVideoFrame.self
        ) {
            IRFFAVYUVVideoFrame()
        }
    }

    static func audioPool() -> IRFFFramePool {
        IRFFFramePool(
            capacity: 500,
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
        lock.unlock()

        factoryLock.lock()
        let createdFrame = frameFactory()
        factoryLock.unlock()

        guard let frame = createdFrame,
              isCompatible(frame) else {
            return nil
        }
        let identifier = ObjectIdentifier(frame)

        lock.lock()
        guard phase == .open,
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
        guard phase == .open else {
            lock.unlock()
            return 0
        }

        let leased = leasedIDs
        let playing = playingID
        let returnedCount =
            leased.count + (playing == nil ? 0 : 1)
        guard returnedCount > 0 else {
            lock.unlock()
            return 0
        }

        for identifier in leased {
            ownedFrames[identifier]?.prepareForReuse()
            availableIDs.insert(identifier)
        }
        leasedIDs.removeAll(keepingCapacity: true)
        if let playing,
           let frame = ownedFrames[playing] {
            frame.prepareForReuse()
            availableIDs.insert(playing)
            playingID = nil
        }
        advanceRevisionLocked()
        lock.unlock()
        return returnedCount
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
            frame.prepareForReuse()
            frame.clearDelegate(ifOwnedBy: self)
        }
        ownedFrames.removeAll()
        availableIDs.removeAll()
        leasedIDs.removeAll()
        playingID = nil
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

        if let previousID = playingID,
           previousID != identifier,
           let previousFrame =
               ownedFrames[previousID] {
            previousFrame.prepareForReuse()
            availableIDs.insert(previousID)
        }
        leasedIDs.remove(identifier)
        availableIDs.remove(identifier)
        playingID = identifier
        advanceRevisionLocked()
        lock.unlock()
    }

    private func stopPlaying(_ frame: IRFFFrame) {
        let identifier = ObjectIdentifier(frame)

        lock.lock()
        guard phase == .open,
              ownedFrames[identifier] === frame,
              playingID == identifier else {
            lock.unlock()
            return
        }
        frame.prepareForReuse()
        availableIDs.insert(identifier)
        playingID = nil
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
                || playingID == identifier else {
            return
        }

        frame.prepareForReuse()
        leasedIDs.remove(identifier)
        if playingID == identifier {
            playingID = nil
        }
        availableIDs.insert(identifier)
        advanceRevisionLocked()
    }

    private func diagnosticsLocked() -> Diagnostics {
        Diagnostics(
            phase: phase,
            availableCount: availableIDs.count,
            leasedCount: leasedIDs.count,
            hasPlayingFrame: playingID != nil,
            totalCount: ownedFrames.count,
            revision: revision
        )
    }

    private func advanceRevisionLocked() {
        revision &+= 1
    }
}
