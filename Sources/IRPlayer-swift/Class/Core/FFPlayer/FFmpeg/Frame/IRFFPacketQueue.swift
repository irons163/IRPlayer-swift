//
//  IRFFPacketQueue.swift
//  IRPlayer-swift
//
//  Created by irons on 2024/7/30.
//

import Foundation

enum IRFFPacketQueueItem: Sendable {
    case packet(
        IRFFPacket,
        generation: UInt64
    )
    case flush(generation: UInt64)
    case endOfStream(generation: UInt64)
    case interrupted(generation: UInt64)
    case closed
}

class IRFFPacketQueue: NSObject {
    static let minimumStorageCapacity = 16
    static let maximumStorageCapacity =
        Int.max /
        max(
            1,
            MemoryLayout<
                IRFFPacketQueueEntry?
            >.stride
        )

    struct Accounting: Equatable {
        let size: Int
        let duration: TimeInterval
    }

    private let timebase: TimeInterval
    private let condition = NSCondition()
    private var packets = IRFFPacketQueueStorage()
    private var storedSize: Int = 0
    private var storedDuration: TimeInterval = 0
    private var destroyToken = false
    private var storedGeneration: UInt64 = 0
    private var terminalGeneration: UInt64?
    private var interruptedGeneration: UInt64?
    private var waitingConsumers = 0

    var size: Int {
        condition.lock()
        defer { condition.unlock() }
        return storedSize
    }

    @objc dynamic var duration: TimeInterval {
        condition.lock()
        defer { condition.unlock() }
        return storedDuration
    }

    var count: Int {
        condition.lock()
        defer { condition.unlock() }
        return packets.count
    }

    var generation: UInt64 {
        condition.lock()
        defer { condition.unlock() }
        return storedGeneration
    }

    var waitingConsumerCount: Int {
        condition.lock()
        defer { condition.unlock() }
        return waitingConsumers
    }

    init(timebase: TimeInterval) {
        self.timebase = timebase
        super.init()
    }

    static func packetQueue(withTimebase timebase: TimeInterval) -> IRFFPacketQueue {
        return IRFFPacketQueue(timebase: timebase)
    }

    @discardableResult
    func putPacket(
        _ packet: IRFFPacket,
        duration fallbackDuration: TimeInterval
    ) -> Bool {
        condition.lock()
        let generation = storedGeneration
        condition.unlock()
        return putPacket(
            packet,
            duration: fallbackDuration,
            generation: generation
        )
    }

    @discardableResult
    func putPacket(
        _ packet: IRFFPacket,
        duration fallbackDuration: TimeInterval,
        generation: UInt64
    ) -> Bool {
        guard let snapshot = packet.snapshot else {
            packet.close()
            return false
        }
        let packetDuration = Self.accountedDuration(
            for: snapshot,
            fallbackDuration: fallbackDuration,
            timebase: timebase
        )
        let packetSize = Self.accountedSize(for: snapshot)

        condition.lock()
        if destroyToken ||
            generation != storedGeneration ||
            terminalGeneration == generation ||
            interruptedGeneration ==
                generation {
            condition.unlock()
            packet.close()
            return false
        }
        guard let accounting =
                Self.accumulatedAccounting(
                    currentSize: storedSize,
                    currentDuration:
                        storedDuration,
                    packetSize: packetSize,
                    packetDuration:
                        packetDuration
                ) else {
            condition.unlock()
            packet.close()
            return false
        }
        guard packets.append(
            IRFFPacketQueueEntry(
                item: .packet(
                    packet,
                    generation: generation
                ),
                size: packetSize,
                duration: packetDuration
            )
        ) else {
            condition.unlock()
            packet.close()
            return false
        }
        storedSize = accounting.size
        storedDuration = accounting.duration
        condition.signal()
        condition.unlock()
        return true
    }

    @discardableResult
    func putFlush() -> Bool {
        condition.lock()
        let generation = storedGeneration
        condition.unlock()
        return putFlush(generation: generation)
    }

    @discardableResult
    func putFlush(generation: UInt64) -> Bool {
        condition.lock()
        guard !destroyToken,
              generation == storedGeneration,
              terminalGeneration != generation,
              interruptedGeneration !=
                generation else {
            condition.unlock()
            return false
        }
        guard packets.append(
            IRFFPacketQueueEntry(
                item: .flush(
                    generation: generation
                ),
                size: 0,
                duration: 0
            )
        ) else {
            condition.unlock()
            return false
        }
        condition.signal()
        condition.unlock()
        return true
    }

    @discardableResult
    func putEndOfStream(
        generation: UInt64
    ) -> Bool {
        condition.lock()
        guard !destroyToken,
              generation == storedGeneration,
              interruptedGeneration !=
                generation else {
            condition.unlock()
            return false
        }
        guard terminalGeneration != generation else {
            condition.unlock()
            return true
        }
        guard packets.append(
            IRFFPacketQueueEntry(
                item: .endOfStream(
                    generation: generation
                ),
                size: 0,
                duration: 0
            )
        ) else {
            condition.unlock()
            return false
        }
        terminalGeneration = generation
        condition.broadcast()
        condition.unlock()
        return true
    }

    func getItem() -> IRFFPacketQueueItem {
        condition.lock()
        while packets.isEmpty {
            if destroyToken {
                condition.unlock()
                return .closed
            }
            if let interruptedGeneration {
                condition.unlock()
                return .interrupted(
                    generation:
                        interruptedGeneration
                )
            }
            waitingConsumers += 1
            condition.wait()
            waitingConsumers -= 1
        }
        if let interruptedGeneration {
            condition.unlock()
            return .interrupted(
                generation:
                    interruptedGeneration
            )
        }
        guard let entry = packets.popFirst() else {
            condition.unlock()
            return .closed
        }
        storedSize -= entry.size
        if storedSize < 0 || packets.isEmpty {
            storedSize = 0
        }
        storedDuration -= entry.duration
        if storedDuration < 0 || packets.isEmpty {
            storedDuration = 0
        }
        condition.unlock()
        return entry.item
    }

    func flush() {
        condition.lock()
        let packetsToClose = flushLocked()
        terminalGeneration = nil
        condition.unlock()
        close(packetsToClose)
    }

    /// Terminates the current generation without permanently closing the
    /// queue. The persistent token wakes an empty-queue waiter without relying
    /// on allocating a control entry and rejects new work until `reset`.
    @discardableResult
    func interrupt(
        generation: UInt64
    ) -> Bool {
        condition.lock()
        guard !destroyToken,
              generation == storedGeneration else {
            condition.unlock()
            return false
        }
        if interruptedGeneration ==
                generation {
            condition.broadcast()
            condition.unlock()
            return true
        }
        let packetsToClose = flushLocked()
        terminalGeneration = generation
        interruptedGeneration = generation
        condition.broadcast()
        condition.unlock()
        close(packetsToClose)
        return true
    }

    @discardableResult
    func reset(
        to generation: UInt64
    ) -> Bool {
        condition.lock()
        guard !destroyToken,
              generation >= storedGeneration else {
            condition.unlock()
            return false
        }
        let packetsToClose = flushLocked()
        storedGeneration = generation
        terminalGeneration = nil
        interruptedGeneration = nil
        guard packets.append(
            IRFFPacketQueueEntry(
                item: .flush(
                    generation: generation
                ),
                size: 0,
                duration: 0
            )
        ) else {
            condition.unlock()
            close(packetsToClose)
            return false
        }
        condition.broadcast()
        condition.unlock()
        close(packetsToClose)
        return true
    }

    @discardableResult
    func advanceGeneration() -> UInt64 {
        condition.lock()
        guard !destroyToken else {
            let generation = storedGeneration
            condition.unlock()
            return generation
        }
        let nextGeneration =
            storedGeneration &+ 1
        let packetsToClose = flushLocked()
        storedGeneration = nextGeneration
        terminalGeneration = nil
        interruptedGeneration = nil
        _ = packets.append(
            IRFFPacketQueueEntry(
                item: .flush(
                    generation: nextGeneration
                ),
                size: 0,
                duration: 0
            )
        )
        condition.broadcast()
        condition.unlock()
        close(packetsToClose)
        return nextGeneration
    }

    func destroy() {
        condition.lock()
        let packetsToClose = flushLocked()
        destroyToken = true
        terminalGeneration = nil
        interruptedGeneration = nil
        condition.broadcast()
        condition.unlock()
        close(packetsToClose)
    }

    private func flushLocked() -> [IRFFPacket] {
        let packetsToClose = packets.drain().compactMap {
            entry -> IRFFPacket? in
            guard case let .packet(
                packet,
                generation: _
            ) = entry.item else {
                return nil
            }
            return packet
        }
        storedSize = 0
        storedDuration = 0
        return packetsToClose
    }

    private func close(
        _ packets: [IRFFPacket]
    ) {
        for entry in packets {
            entry.close()
        }
    }

    static func accountedDuration(
        for packet: IRFFPacket.Snapshot,
        fallbackDuration: TimeInterval,
        timebase: TimeInterval
    ) -> TimeInterval {
        if packet.duration > 0,
           timebase.isFinite,
           timebase > 0 {
            let duration =
                Double(packet.duration) * timebase
            guard duration.isFinite, duration > 0 else {
                return 0
            }
            return duration
        }
        guard fallbackDuration.isFinite,
              fallbackDuration > 0 else {
            return 0
        }
        return fallbackDuration
    }

    static func accountedSize(
        for packet: IRFFPacket.Snapshot
    ) -> Int {
        max(0, Int(packet.size))
    }

    static func accumulatedAccounting(
        currentSize: Int,
        currentDuration: TimeInterval,
        packetSize: Int,
        packetDuration: TimeInterval
    ) -> Accounting? {
        guard currentSize >= 0,
              packetSize >= 0,
              currentDuration.isFinite,
              currentDuration >= 0,
              packetDuration.isFinite,
              packetDuration >= 0 else {
            return nil
        }
        let (size, sizeOverflow) =
            currentSize.addingReportingOverflow(
                packetSize
            )
        guard !sizeOverflow,
              size >= currentSize else {
            return nil
        }
        let duration =
            currentDuration + packetDuration
        let durationLost =
            packetDuration > 0 &&
            duration <= currentDuration
        guard duration.isFinite,
              duration >= currentDuration,
              !durationLost else {
            return nil
        }
        return Accounting(
            size: size,
            duration: duration
        )
    }

    static func storageGrowthCapacity(
        currentCapacity: Int,
        requiredCount: Int
    ) -> Int? {
        guard currentCapacity >=
                minimumStorageCapacity,
              currentCapacity <=
                maximumStorageCapacity,
              requiredCount > currentCapacity,
              requiredCount <=
                maximumStorageCapacity
        else {
            return nil
        }
        let (doubledCapacity, overflow) =
            currentCapacity
                .multipliedReportingOverflow(
                    by: 2
                )
        let capacity =
            overflow ||
            doubledCapacity >
                maximumStorageCapacity
            ? requiredCount
            : max(
                requiredCount,
                doubledCapacity
            )
        guard capacity >= requiredCount,
              capacity > currentCapacity else {
            return nil
        }
        return capacity
    }

    deinit {
        destroy()
    }
}

private struct IRFFPacketQueueEntry {
    let item: IRFFPacketQueueItem
    let size: Int
    let duration: TimeInterval
}

private struct IRFFPacketQueueStorage {
    private var elements: [IRFFPacketQueueEntry?] =
        Array(
            repeating: nil,
            count:
                IRFFPacketQueue
                    .minimumStorageCapacity
        )
    private var headIndex = 0
    private(set) var count = 0

    var isEmpty: Bool {
        count == 0
    }

    @discardableResult
    mutating func append(
        _ entry: IRFFPacketQueueEntry
    ) -> Bool {
        guard ensureCapacityForAppend() else {
            return false
        }
        let index = Self.physicalIndex(
            headIndex: headIndex,
            offset: count,
            capacity: elements.count
        )
        elements[index] = entry
        count += 1
        return true
    }

    mutating func popFirst()
        -> IRFFPacketQueueEntry? {
        guard count > 0 else { return nil }
        let entry = elements[headIndex]
        elements[headIndex] = nil
        headIndex =
            headIndex == elements.count - 1
            ? 0
            : headIndex + 1
        count -= 1
        if count == 0 {
            headIndex = 0
        }
        return entry
    }

    mutating func drain()
        -> [IRFFPacketQueueEntry] {
        var drained: [IRFFPacketQueueEntry] = []
        drained.reserveCapacity(count)
        while let entry = popFirst() {
            drained.append(entry)
        }
        return drained
    }

    private mutating func ensureCapacityForAppend()
        -> Bool
    {
        guard count == elements.count else {
            return true
        }
        let (requiredCount, requiredOverflow) =
            count.addingReportingOverflow(1)
        guard !requiredOverflow,
              let newCapacity =
                IRFFPacketQueue
                    .storageGrowthCapacity(
                        currentCapacity:
                            elements.count,
                        requiredCount:
                            requiredCount
                    ) else {
            return false
        }
        var grown = [IRFFPacketQueueEntry?](
            repeating: nil,
            count: newCapacity
        )
        for offset in 0..<count {
            let oldIndex = Self.physicalIndex(
                headIndex: headIndex,
                offset: offset,
                capacity: elements.count
            )
            grown[offset] = elements[oldIndex]
        }
        elements = grown
        headIndex = 0
        return true
    }

    /// Maps a logical offset without evaluating `headIndex + offset`, which
    /// could overflow even when both values are valid ring-buffer indices.
    private static func physicalIndex(
        headIndex: Int,
        offset: Int,
        capacity: Int
    ) -> Int {
        let distanceToEnd =
            capacity - headIndex
        return offset < distanceToEnd
            ? headIndex + offset
            : offset - distanceToEnd
    }
}
