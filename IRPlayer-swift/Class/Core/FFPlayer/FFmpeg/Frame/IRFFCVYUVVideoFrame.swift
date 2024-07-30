//
//  IRFFCVYUVVideoFrame.swift
//  IRPlayer-swift
//
//  Created by irons on 2024/7/26.
//

import Foundation
import CoreVideo

@objcMembers public class IRFFCVYUVVideoFrame: IRFFVideoFrame {
    public let pixelBuffer: CVPixelBuffer

    init(pixelBuffer: CVPixelBuffer) {
        self.pixelBuffer = pixelBuffer
        super.init()
        width = CVPixelBufferGetWidth(pixelBuffer)
        height = CVPixelBufferGetHeight(pixelBuffer)
    }

    override var type: IRFFFrameType {
        return .cvyuvVideo
    }

//    override var width: Int {
//        return CVPixelBufferGetWidth(pixelBuffer)
//    }
//
//    override var height: Int {
//        return CVPixelBufferGetHeight(pixelBuffer)
//    }
}

