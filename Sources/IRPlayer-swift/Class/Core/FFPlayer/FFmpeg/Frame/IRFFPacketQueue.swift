//
//  IRFFPacketQueue.swift
//  IRPlayer-swift
//
//  Created by irons on 2024/7/30.
//

import Foundation
import IRFFMpeg

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

    func putPacket(_ packet: AVPacket, duration: TimeInterval) {
        condition.lock()
        if destroyToken {
            condition.unlock()
            return
        }
        let packetDuration = Self.accountedDuration(for: packet, fallbackDuration: duration, timebase: timebase)
        packets.append(IRFFPacketQueueEntry(packet: packet, duration: packetDuration))
        storedSize += Self.accountedSize(for: packet)
        storedDuration += packetDuration
        condition.signal()
        condition.unlock()
    }

    func getPacket() -> AVPacket {
        condition.lock()
        var packet = AVPacket()
        packet.stream_index = -2
        while packets.isEmpty {
            if destroyToken {
                condition.unlock()
                return packet
            }
            condition.wait()
        }
        let entry = packets.removeFirst()
        packet = entry.packet
        storedSize -= Self.accountedSize(for: packet)
        if storedSize < 0 || packets.isEmpty {
            storedSize = 0
        }
        storedDuration -= entry.duration
        if storedDuration < 0 || packets.isEmpty {
            storedDuration = 0
        }
        condition.unlock()
        return packet
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
        for i in packets.indices {
            av_packet_unref(&packets[i].packet)
        }
        packets.removeAll()
        storedSize = 0
        storedDuration = 0
    }

    static func accountedDuration(for packet: AVPacket,
                                  fallbackDuration: TimeInterval,
                                  timebase: TimeInterval) -> TimeInterval {
        return IRFFPacketQueuePolicy.accountedDuration(for: packet, fallbackDuration: fallbackDuration, timebase: timebase)
    }

    static func accountedSize(for packet: AVPacket) -> Int {
        return IRFFPacketQueuePolicy.accountedSize(for: packet)
    }
}

private struct IRFFPacketQueueEntry {
    var packet: AVPacket
    let duration: TimeInterval
}
