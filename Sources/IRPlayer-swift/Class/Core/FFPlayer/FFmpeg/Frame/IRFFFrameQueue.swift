//
//  IRFFFrameQueue.swift
//  IRPlayer-swift
//
//  Created by irons on 2024/7/30.
//

import Foundation

final class IRFFFrameQueue:
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

    enum Admission:
        Equatable,
        Hashable,
        Sendable
    {
        case accepted
        case rejectedNil
        case rejectedDuplicate
        case rejectedAccountingOverflow
        case rejectedClosed
    }

    struct Diagnostics:
        Equatable,
        Hashable,
        Sendable
    {
        let phase: Phase
        let count: Int
        let duration: TimeInterval
        let size: Int
        let revision: UInt64
    }

    private struct Entry {
        let identifier: ObjectIdentifier
        let frame: IRFFFrame
        let position: TimeInterval
        let duration: TimeInterval
        let size: Int
        let insertionSequence: UInt64
    }

    private enum Ordering {
        case fifo
        case position
    }

    private let condition = NSCondition()
    private var phase: Phase = .open
    private var entries: [Entry] = []
    private var enqueuedIDs:
        Set<ObjectIdentifier> = []
    private var storedSize = 0
    private var storedDuration: TimeInterval = 0
    private var nextInsertionSequence: UInt64 = 0
    private var revision: UInt64 = 0

    var diagnostics: Diagnostics {
        condition.lock()
        defer { condition.unlock() }
        return diagnosticsLocked()
    }

    var size: Int {
        diagnostics.size
    }

    var count: Int {
        diagnostics.count
    }

    var duration: TimeInterval {
        diagnostics.duration
    }

    @discardableResult
    func enqueue(
        _ frame: IRFFFrame?
    ) -> Admission {
        admit(frame, ordering: .fifo)
    }

    @discardableResult
    func enqueueSorted(
        _ frame: IRFFFrame?
    ) -> Admission {
        admit(frame, ordering: .position)
    }

    func waitForFrame() -> IRFFFrame? {
        condition.lock()
        while phase == .open,
              entries.isEmpty {
            condition.wait()
        }
        guard phase == .open else {
            condition.unlock()
            return nil
        }
        let frame = removeFirstLocked()
        condition.unlock()
        return frame
    }

    func dequeue() -> IRFFFrame? {
        condition.lock()
        guard phase == .open,
              !entries.isEmpty else {
            condition.unlock()
            return nil
        }
        let frame = removeFirstLocked()
        condition.unlock()
        return frame
    }

    @discardableResult
    func flush() -> Int {
        condition.lock()
        guard phase == .open else {
            condition.unlock()
            return 0
        }
        let drainedFrames = drainLocked()
        guard !drainedFrames.isEmpty else {
            condition.unlock()
            return 0
        }
        advanceRevisionLocked()
        condition.unlock()

        cancel(drainedFrames)
        return drainedFrames.count
    }

    @discardableResult
    func close() -> Bool {
        condition.lock()
        guard phase == .open else {
            condition.unlock()
            return false
        }
        phase = .closed
        let drainedFrames = drainLocked()
        advanceRevisionLocked()
        condition.broadcast()
        condition.unlock()

        cancel(drainedFrames)
        return true
    }

    deinit {
        close()
    }

    private func admit(
        _ frame: IRFFFrame?,
        ordering: Ordering
    ) -> Admission {
        guard let frame else {
            return .rejectedNil
        }

        let transport = frame.transportSnapshot()
        let duration =
            Self.accountedDuration(
                transport.duration
            )
        let size = max(0, transport.size)
        let identifier = ObjectIdentifier(frame)
        var shouldCancel = false
        let result: Admission

        condition.lock()
        if phase == .closed {
            shouldCancel = true
            result = .rejectedClosed
        } else if enqueuedIDs.contains(identifier) {
            result = .rejectedDuplicate
        } else {
            let (newSize, sizeOverflow) =
                storedSize.addingReportingOverflow(size)
            let newDuration = storedDuration + duration
            let durationLost =
                duration > 0
                && newDuration <= storedDuration
            guard !sizeOverflow,
                  newSize >= storedSize,
                  newDuration.isFinite,
                  !durationLost else {
                condition.unlock()
                frame.cancel()
                return .rejectedAccountingOverflow
            }

            let entry = Entry(
                identifier: identifier,
                frame: frame,
                position: transport.position,
                duration: duration,
                size: size,
                insertionSequence:
                    nextInsertionSequence
            )
            nextInsertionSequence &+= 1
            switch ordering {
            case .fifo:
                entries.append(entry)
            case .position:
                let index =
                    insertionIndexLocked(for: entry)
                entries.insert(entry, at: index)
            }
            enqueuedIDs.insert(identifier)
            storedSize = newSize
            storedDuration = newDuration
            advanceRevisionLocked()
            condition.signal()
            result = .accepted
        }
        condition.unlock()

        if shouldCancel {
            frame.cancel()
        }
        return result
    }

    private static func accountedDuration(
        _ duration: TimeInterval
    ) -> TimeInterval {
        guard duration.isFinite,
              duration > 0 else {
            return 0
        }
        return duration
    }

    private func insertionIndexLocked(
        for entry: Entry
    ) -> Int {
        guard !entries.isEmpty else { return 0 }
        for index in entries.indices.reversed() {
            if shouldInsert(
                entry,
                after: entries[index]
            ) {
                return index + 1
            }
        }
        return 0
    }

    private func shouldInsert(
        _ entry: Entry,
        after existing: Entry
    ) -> Bool {
        if entry.position.isFinite,
           existing.position.isFinite {
            if entry.position == existing.position {
                return entry.insertionSequence
                    > existing.insertionSequence
            }
            return entry.position > existing.position
        }
        if !entry.position.isFinite {
            return true
        }
        return false
    }

    private func removeFirstLocked() -> IRFFFrame {
        let entry = entries.removeFirst()
        enqueuedIDs.remove(entry.identifier)
        storedDuration =
            max(0, storedDuration - entry.duration)
        storedSize = max(0, storedSize - entry.size)
        if entries.isEmpty {
            storedDuration = 0
            storedSize = 0
        }
        advanceRevisionLocked()
        return entry.frame
    }

    private func drainLocked() -> [IRFFFrame] {
        let frames = entries.map(\.frame)
        entries.removeAll(keepingCapacity: true)
        enqueuedIDs.removeAll(keepingCapacity: true)
        storedDuration = 0
        storedSize = 0
        return frames
    }

    private func cancel(
        _ frames: [IRFFFrame]
    ) {
        for frame in frames {
            frame.cancel()
        }
    }

    private func diagnosticsLocked() -> Diagnostics {
        Diagnostics(
            phase: phase,
            count: entries.count,
            duration: storedDuration,
            size: storedSize,
            revision: revision
        )
    }

    private func advanceRevisionLocked() {
        revision &+= 1
    }
}
