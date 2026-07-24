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

    public init(pixelBuffer: CVPixelBuffer) {
        self.pixelBuffer = pixelBuffer
        super.init()
    }

    override var type: IRFFFrameType {
        return .cvyuvVideo
    }

    @nonobjc
    override func dimensionSnapshot() -> IRFFVideoDimensions {
        IRFFVideoDimensions.make(
            width: CVPixelBufferGetWidth(pixelBuffer),
            height: CVPixelBufferGetHeight(pixelBuffer)
        ) ?? .zero
    }

    @discardableResult
    public override func setDimensions(
        width: Int,
        height: Int
    ) -> Bool {
        guard let dimensions = IRFFVideoDimensions.make(
            width: width,
            height: height
        ) else {
            return false
        }
        return dimensions == dimensionSnapshot()
    }
}
