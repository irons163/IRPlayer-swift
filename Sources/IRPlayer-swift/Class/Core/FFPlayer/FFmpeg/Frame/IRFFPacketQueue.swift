//
//  IRFFPacketQueue.swift
//  IRPlayer-swift
//
//  Created by irons on 2024/7/30.
//

import Foundation
import IRFFMpeg

class IRFFPacketQueue: NSObject {
    private(set) var size: Int = 0
    @objc dynamic private(set) var duration: TimeInterval = 0
    private(set) var timebase: TimeInterval
    private var condition = NSCondition()
    private var packets = [IRFFPacketQueueEntry]()
    private var destroyToken = false

    var count: Int {
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
        size += Int(packet.size)
        self.duration += packetDuration
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
        size -= Int(packet.size)
        if size < 0 || count <= 0 {
            size = 0
        }
        duration -= entry.duration
        if duration < 0 || count <= 0 {
            duration = 0
        }
        condition.unlock()
        return packet
    }

    func flush() {
        condition.lock()
        for i in packets.indices {
            av_packet_unref(&packets[i].packet)
        }
        packets.removeAll()
        size = 0
        duration = 0
        condition.unlock()
    }

    func destroy() {
        flush()
        condition.lock()
        destroyToken = true
        condition.broadcast()
        condition.unlock()
    }

    private static func accountedDuration(for packet: AVPacket,
                                           fallbackDuration: TimeInterval,
                                           timebase: TimeInterval) -> TimeInterval {
        if packet.duration > 0 {
            return Double(packet.duration) * timebase
        }
        return max(0, fallbackDuration)
    }
}

private struct IRFFPacketQueueEntry {
    var packet: AVPacket
    let duration: TimeInterval
}
