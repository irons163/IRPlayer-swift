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
        case rejectedEndOfStream
        case rejectedClosed
    }

    enum CapacityClass:
        Equatable,
        Hashable,
        Sendable
    {
        case pooled
        case nonPooled
    }

    struct Diagnostics:
        Equatable,
        Hashable,
        Sendable
    {
        let phase: Phase
        let count: Int
        let nonPooledCount: Int
        let duration: TimeInterval
        let size: Int
        let revision: UInt64
    }

    struct Transfer {
        let frame: IRFFFrame
        let position: TimeInterval
        let duration: TimeInterval
        let size: Int
    }

    private struct Entry {
        let identifier: ObjectIdentifier
        let frame: IRFFFrame
        let position: TimeInterval
        let duration: TimeInterval
        let size: Int
        let capacityClass: CapacityClass
        let insertionSequence: UInt64
    }

    private enum Ordering {
        case fifo
        case position
    }

    private static let emptyCondition = 0
    private static let readyCondition = 1

    private let condition = NSConditionLock(
        condition: emptyCondition
    )
    private let willRemoveEntryObserver:
        (() -> Void)?
    private var phase: Phase = .open
    private var endOfStream = false
    // A circular buffer keeps callback-side FIFO removal O(1). Array's
    // `removeFirst()` shifts every queued element and is not suitable for a
    // real-time audio render path.
    private var entries: [Entry?] = []
    private var headIndex = 0
    private var entryCount = 0
    private var enqueuedIDs:
        Set<ObjectIdentifier> = []
    private var storedSize = 0
    private var storedDuration: TimeInterval = 0
    private var storedNonPooledCount = 0
    private var nextInsertionSequence: UInt64 = 0
    private var revision: UInt64 = 0

    init(
        willRemoveEntryObserver:
            (() -> Void)? = nil
    ) {
        self.willRemoveEntryObserver =
            willRemoveEntryObserver
    }

    var diagnostics: Diagnostics {
        condition.lock()
        defer {
            condition.unlock(
                withCondition: conditionValueLocked
            )
        }
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
        _ frame: IRFFFrame?,
        capacityClass:
            CapacityClass = .pooled
    ) -> Admission {
        admit(
            frame,
            ordering: .fifo,
            capacityClass: capacityClass
        )
    }

    @discardableResult
    func enqueueSorted(
        _ frame: IRFFFrame?,
        capacityClass:
            CapacityClass = .pooled
    ) -> Admission {
        admit(
            frame,
            ordering: .position,
            capacityClass: capacityClass
        )
    }

    func waitForFrame() -> IRFFFrame? {
        condition.lock(
            whenCondition: Self.readyCondition
        )
        guard phase == .open,
              entryCount > 0 else {
            condition.unlock(
                withCondition:
                    phase == .closed || endOfStream
                    ? Self.readyCondition
                    : Self.emptyCondition
            )
            return nil
        }
        let transfer = removeFirstLocked()
        condition.unlock(
            withCondition: conditionValueLocked
        )
        return transfer.frame
    }

    func dequeue() -> IRFFFrame? {
        condition.lock()
        guard phase == .open,
              entryCount > 0 else {
            condition.unlock(
                withCondition: conditionValueLocked
            )
            return nil
        }
        let transfer = removeFirstLocked()
        condition.unlock(
            withCondition: conditionValueLocked
        )
        return transfer.frame
    }

    /// Attempts one dequeue without waiting for data or queue ownership.
    /// Real-time audio rendering must use this path.
    func tryDequeue() -> IRFFFrame? {
        tryDequeueTransfer()?.frame
    }

    /// Returns the immutable metadata captured when the frame entered the queue.
    /// This avoids taking the frame's transport lock on a real-time callback.
    func tryDequeueTransfer() -> Transfer? {
        guard condition.try() else { return nil }
        guard phase == .open,
              entryCount > 0 else {
            condition.unlock(
                withCondition: conditionValueLocked
            )
            return nil
        }
        let transfer = removeFirstLocked()
        condition.unlock(
            withCondition: conditionValueLocked
        )
        return transfer
    }

    @discardableResult
    func flush() -> Int {
        condition.lock()
        guard phase == .open else {
            condition.unlock(
                withCondition: conditionValueLocked
            )
            return 0
        }
        endOfStream = false
        let drainedFrames = drainLocked()
        advanceRevisionLocked()
        condition.unlock(
            withCondition: Self.readyCondition
        )

        cancel(drainedFrames)
        return drainedFrames.count
    }

    @discardableResult
    func finish() -> Bool {
        condition.lock()
        guard phase == .open,
              !endOfStream else {
            condition.unlock(
                withCondition: conditionValueLocked
            )
            return false
        }
        endOfStream = true
        advanceRevisionLocked()
        condition.unlock(
            withCondition: Self.readyCondition
        )
        return true
    }

    @discardableResult
    func resume() -> Bool {
        condition.lock()
        guard phase == .open,
              endOfStream else {
            condition.unlock(
                withCondition: conditionValueLocked
            )
            return false
        }
        endOfStream = false
        advanceRevisionLocked()
        condition.unlock(
            withCondition: conditionValueLocked
        )
        return true
    }

    @discardableResult
    func close() -> Bool {
        condition.lock()
        guard phase == .open else {
            condition.unlock(
                withCondition: Self.readyCondition
            )
            return false
        }
        phase = .closed
        endOfStream = true
        let drainedFrames = drainLocked()
        advanceRevisionLocked()
        condition.unlock(
            withCondition: Self.readyCondition
        )

        cancel(drainedFrames)
        return true
    }

    deinit {
        close()
    }

    private func admit(
        _ frame: IRFFFrame?,
        ordering: Ordering,
        capacityClass: CapacityClass
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
        } else if endOfStream {
            shouldCancel = true
            result = .rejectedEndOfStream
        } else if enqueuedIDs.contains(identifier) {
            result = .rejectedDuplicate
        } else {
            let (newEntryCount, countOverflow) =
                entryCount
                    .addingReportingOverflow(1)
            let (newSize, sizeOverflow) =
                storedSize.addingReportingOverflow(size)
            let newDuration = storedDuration + duration
            let durationLost =
                duration > 0
                && newDuration <= storedDuration
            let nonPooledIncrement =
                capacityClass == .nonPooled
                ? 1
                : 0
            let (
                newNonPooledCount,
                nonPooledOverflow
            ) = storedNonPooledCount
                .addingReportingOverflow(
                    nonPooledIncrement
                )
            guard !countOverflow,
                  newEntryCount > entryCount,
                  !sizeOverflow,
                  newSize >= storedSize,
                  newDuration.isFinite,
                  !durationLost,
                  !nonPooledOverflow,
                  newNonPooledCount >=
                    storedNonPooledCount else {
                condition.unlock(
                    withCondition: conditionValueLocked
                )
                frame.cancel()
                return .rejectedAccountingOverflow
            }

            let entry = Entry(
                identifier: identifier,
                frame: frame,
                position: transport.position,
                duration: duration,
                size: size,
                capacityClass:
                    capacityClass,
                insertionSequence:
                    nextInsertionSequence
            )
            nextInsertionSequence &+= 1
            ensureCapacityLocked(
                for: newEntryCount
            )
            switch ordering {
            case .fifo:
                setEntryLocked(
                    entry,
                    atLogicalIndex: entryCount
                )
                entryCount = newEntryCount
            case .position:
                let index =
                    insertionIndexLocked(for: entry)
                insertLocked(
                    entry,
                    atLogicalIndex: index
                )
            }
            enqueuedIDs.insert(identifier)
            storedSize = newSize
            storedDuration = newDuration
            storedNonPooledCount =
                newNonPooledCount
            advanceRevisionLocked()
            result = .accepted
        }
        condition.unlock(
            withCondition: conditionValueLocked
        )

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
        guard entryCount > 0 else { return 0 }
        for index in stride(
            from: entryCount - 1,
            through: 0,
            by: -1
        ) {
            guard let existing =
                    entryLocked(atLogicalIndex: index) else {
                continue
            }
            if shouldInsert(
                entry,
                after: existing
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

    private func removeFirstLocked() -> Transfer {
        precondition(entryCount > 0)
        let index = physicalIndexLocked(
            forLogicalIndex: 0
        )
        guard let entry = entries[index] else {
            preconditionFailure(
                "Frame queue circular-buffer invariant failed"
            )
        }
        // Capacity metadata is removed in the same queue transaction as the
        // entry. A same-identity re-admission must wait for this lock, so it
        // cannot erase or inherit an earlier admission's credit (ABA).
        willRemoveEntryObserver?()
        entries[index] = nil
        entryCount -= 1
        if entryCount == 0 {
            headIndex = 0
        } else {
            headIndex = (headIndex + 1) % entries.count
        }
        enqueuedIDs.remove(entry.identifier)
        if entry.capacityClass == .nonPooled {
            precondition(
                storedNonPooledCount > 0
            )
            storedNonPooledCount -= 1
        }
        storedDuration =
            max(0, storedDuration - entry.duration)
        storedSize = max(0, storedSize - entry.size)
        if entryCount == 0 {
            storedDuration = 0
            storedSize = 0
        }
        advanceRevisionLocked()
        return Transfer(
            frame: entry.frame,
            position: entry.position,
            duration: entry.duration,
            size: entry.size
        )
    }

    private func drainLocked() -> [IRFFFrame] {
        var frames: [IRFFFrame] = []
        frames.reserveCapacity(entryCount)
        for logicalIndex in 0..<entryCount {
            if let entry = entryLocked(
                atLogicalIndex: logicalIndex
            ) {
                frames.append(entry.frame)
            }
        }
        for index in entries.indices {
            entries[index] = nil
        }
        headIndex = 0
        entryCount = 0
        enqueuedIDs.removeAll(keepingCapacity: true)
        storedNonPooledCount = 0
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
            count: entryCount,
            nonPooledCount:
                storedNonPooledCount,
            duration: storedDuration,
            size: storedSize,
            revision: revision
        )
    }

    private var conditionValueLocked: Int {
        if phase == .closed {
            return Self.readyCondition
        }
        return entryCount == 0 &&
            !endOfStream
            ? Self.emptyCondition
            : Self.readyCondition
    }

    private func ensureCapacityLocked(
        for requiredCount: Int
    ) {
        guard requiredCount > entries.count else {
            return
        }
        let doubledCapacity = entries.count
            .multipliedReportingOverflow(by: 2)
        let growthCandidate = doubledCapacity.overflow
            ? requiredCount
            : doubledCapacity.partialValue
        let newCapacity = max(
            16,
            requiredCount,
            growthCandidate
        )
        var expanded = [Entry?](
            repeating: nil,
            count: newCapacity
        )
        for logicalIndex in 0..<entryCount {
            expanded[logicalIndex] = entryLocked(
                atLogicalIndex: logicalIndex
            )
        }
        entries = expanded
        headIndex = 0
    }

    private func insertLocked(
        _ entry: Entry,
        atLogicalIndex insertionIndex: Int
    ) {
        precondition(
            insertionIndex >= 0
                && insertionIndex <= entryCount
        )
        precondition(entryCount < entries.count)
        if insertionIndex < entryCount {
            for logicalIndex in stride(
                from: entryCount,
                to: insertionIndex,
                by: -1
            ) {
                setEntryLocked(
                    entryLocked(
                        atLogicalIndex:
                            logicalIndex - 1
                    ),
                    atLogicalIndex: logicalIndex
                )
            }
        }
        setEntryLocked(
            entry,
            atLogicalIndex: insertionIndex
        )
        entryCount += 1
    }

    private func entryLocked(
        atLogicalIndex logicalIndex: Int
    ) -> Entry? {
        guard logicalIndex >= 0,
              logicalIndex < entryCount,
              !entries.isEmpty else {
            return nil
        }
        return entries[
            physicalIndexLocked(
                forLogicalIndex: logicalIndex
            )
        ]
    }

    private func setEntryLocked(
        _ entry: Entry?,
        atLogicalIndex logicalIndex: Int
    ) {
        precondition(
            logicalIndex >= 0
                && logicalIndex < entries.count
        )
        entries[
            physicalIndexLocked(
                forLogicalIndex: logicalIndex
            )
        ] = entry
    }

    private func physicalIndexLocked(
        forLogicalIndex logicalIndex: Int
    ) -> Int {
        precondition(!entries.isEmpty)
        return (headIndex + logicalIndex)
            % entries.count
    }

    private func advanceRevisionLocked() {
        revision &+= 1
    }
}
