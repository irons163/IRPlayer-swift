//
//  IRFFAVYUVVideoFramePolicy.swift
//  IRPlayer-swift
//
//  Created by Codex on 2026/6/2.
//

import Foundation

enum IRFFAVYUVVideoFramePolicy {
    static func shouldAcceptFrameData(width: Int,
                                      height: Int,
                                      hasLuma: Bool,
                                      hasChromaB: Bool,
                                      hasChromaR: Bool,
                                      linesizeY: Int32,
                                      linesizeU: Int32,
                                      linesizeV: Int32) -> Bool {
        return width > 0
            && height > 0
            && hasLuma
            && hasChromaB
            && hasChromaR
            && linesizeY > 0
            && linesizeU > 0
            && linesizeV > 0
    }

    static func channelBufferSize(for channel: IRYUVChannel, capacities: [Int]) -> Int? {
        guard channel != .count,
              capacities.indices.contains(channel.rawValue) else {
            return nil
        }
        return capacities[channel.rawValue]
    }
}
