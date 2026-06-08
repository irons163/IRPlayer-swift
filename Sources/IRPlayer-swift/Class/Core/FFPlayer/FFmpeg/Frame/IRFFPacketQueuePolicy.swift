//
//  IRFFPacketQueuePolicy.swift
//  IRPlayer-swift
//
//  Created by Codex on 2026/6/2.
//

import Foundation
import IRFFMpeg

enum IRFFPacketQueuePolicy {
    static func accountedDuration(for packet: AVPacket,
                                  fallbackDuration: TimeInterval,
                                  timebase: TimeInterval) -> TimeInterval {
        if packet.duration > 0, timebase.isFinite, timebase > 0 {
            let duration = Double(packet.duration) * timebase
            guard duration.isFinite, duration > 0 else {
                return 0
            }
            return duration
        }
        guard fallbackDuration.isFinite, fallbackDuration > 0 else {
            return 0
        }
        return fallbackDuration
    }

    static func accountedSize(for packet: AVPacket) -> Int {
        return max(0, Int(packet.size))
    }
}
