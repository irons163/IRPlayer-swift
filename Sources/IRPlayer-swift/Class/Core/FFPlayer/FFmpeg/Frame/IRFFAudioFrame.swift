//
//  IRFFAudioFrame.swift
//  IRPlayer-swift
//
//  Created by irons on 2024/7/26.
//

import Foundation

@objcMembers public class IRFFAudioFrame: IRFFFrame {
    var samples: UnsafeMutablePointer<Float>?
    var outputOffset: Int = 0
    private var bufferSize: Int = 0

    override var type: IRFFFrameType {
        return .audio
    }

    func setSamplesLength(_ samplesLength: Int) {
        guard let sampleCapacity = Self.sampleCapacity(forByteLength: samplesLength) else {
            size = 0
            outputOffset = 0
            return
        }

        if Self.shouldAllocateSampleBuffer(currentCapacity: bufferSize, requiredCapacity: sampleCapacity) {
            if bufferSize > 0, let samples = samples {
                samples.deallocate()
            }
            bufferSize = sampleCapacity
            samples = UnsafeMutablePointer<Float>.allocate(capacity: sampleCapacity)
        }
        size = samplesLength
        outputOffset = 0
    }

    deinit {
        if bufferSize > 0, let samples = samples {
            samples.deallocate()
        }
    }

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
