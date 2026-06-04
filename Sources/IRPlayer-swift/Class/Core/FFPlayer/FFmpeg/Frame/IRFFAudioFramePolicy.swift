//
//  IRFFAudioFramePolicy.swift
//  IRPlayer-swift
//
//  Created by Codex on 2026/6/2.
//

import Foundation

enum IRFFAudioFramePolicy {
    static func sampleCapacity(forByteLength byteLength: Int) -> Int? {
        guard byteLength > 0 else { return nil }

        let floatSize = MemoryLayout<Float>.size
        let (adjustedByteLength, overflow) = byteLength.addingReportingOverflow(floatSize - 1)
        guard !overflow else { return nil }

        let capacity = adjustedByteLength / floatSize
        return capacity > 0 ? capacity : nil
    }

    static func shouldAllocateSampleBuffer(currentCapacity: Int, requiredCapacity: Int) -> Bool {
        return currentCapacity < requiredCapacity
    }
}
