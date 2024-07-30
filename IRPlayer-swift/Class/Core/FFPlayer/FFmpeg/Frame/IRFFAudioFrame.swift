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
        if bufferSize < samplesLength {
            if bufferSize > 0, let samples = samples {
                free(samples)
            }
            bufferSize = samplesLength
            samples = UnsafeMutablePointer<Float>.allocate(capacity: bufferSize)
        }
        size = samplesLength
        outputOffset = 0
    }

    deinit {
        if bufferSize > 0, let samples = samples {
            free(samples)
        }
    }
}

