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
            releaseSamples()
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
        releaseSamples()
    }

    private func releaseSamples() {
        if bufferSize > 0, let samples = samples {
            samples.deallocate()
        }
        samples = nil
        bufferSize = 0
    }

    static func sampleCapacity(forByteLength byteLength: Int) -> Int? {
        return IRFFAudioFramePolicy.sampleCapacity(forByteLength: byteLength)
    }

    static func shouldAllocateSampleBuffer(currentCapacity: Int, requiredCapacity: Int) -> Bool {
        return IRFFAudioFramePolicy.shouldAllocateSampleBuffer(currentCapacity: currentCapacity, requiredCapacity: requiredCapacity)
    }
}
