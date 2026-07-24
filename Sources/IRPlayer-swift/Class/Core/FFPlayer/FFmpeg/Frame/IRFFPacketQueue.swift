//
//  IRFFPacketQueue.swift
//  IRPlayer-swift
//
//  Created by irons on 2024/7/30.
//

import Foundation

enum IRFFPacketQueueItem: Sendable {
    case packet(IRFFPacket)
    case flush
    case closed
}

class IRFFPacketQueue: NSObject {
    private let timebase: TimeInterval
    private let condition = NSCondition()
    private var packets = [IRFFPacketQueueEntry]()
    private var storedSize: Int = 0
    private var storedDuration: TimeInterval = 0
    private var destroyToken = false

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
        if destroyToken {
            condition.unlock()
            packet.close()
            return false
        }
        packets.append(
            IRFFPacketQueueEntry(
                item: .packet(packet),
                size: packetSize,
                duration: packetDuration
            )
        )
        storedSize += packetSize
        storedDuration += packetDuration
        condition.signal()
        condition.unlock()
        return true
    }

    @discardableResult
    func putFlush() -> Bool {
        condition.lock()
        guard !destroyToken else {
            condition.unlock()
            return false
        }
        packets.append(
            IRFFPacketQueueEntry(
                item: .flush,
                size: 0,
                duration: 0
            )
        )
        condition.signal()
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
            condition.wait()
        }
        let entry = packets.removeFirst()
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
        flushLocked()
        condition.unlock()
    }

    func destroy() {
        condition.lock()
        flushLocked()
        destroyToken = true
        condition.broadcast()
        condition.unlock()
    }

    private func flushLocked() {
        for entry in packets {
            if case let .packet(packet) = entry.item {
                packet.close()
            }
        }
        packets.removeAll()
        storedSize = 0
        storedDuration = 0
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

    deinit {
        destroy()
    }
}

private struct IRFFPacketQueueEntry {
    let item: IRFFPacketQueueItem
    let size: Int
    let duration: TimeInterval
}
