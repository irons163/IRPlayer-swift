//
//  IRVideoFrameRGB.swift
//  IRPlayer-swift
//
//  Created by irons on 2024/7/26.
//

import Foundation
import UIKit

enum IRFrameFormat {
    case RGB
}

@objcMembers public class IRVideoFrameRGB: IRFFVideoFrame {
    let linesize: UInt
    public let rgb: Data

    override var type: IRFFFrameType {
        return .video
    }

    var format: IRFrameFormat {
        return .RGB
    }

    public init(linesize: UInt, rgb: Data) {
        self.linesize = linesize
        self.rgb = rgb
    }

    func asImage() -> UIImage? {
        guard let provider = CGDataProvider(data: rgb as CFData) else {
            return nil
        }

        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else {
            return nil
        }

        guard let imageRef = CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 24,
            bytesPerRow: Int(linesize),
            space: colorSpace,
            bitmapInfo: CGBitmapInfo.byteOrderDefault,
            provider: provider,
            decode: nil,
            shouldInterpolate: true,
            intent: .defaultIntent
        ) else {
            return nil
        }

        return UIImage(cgImage: imageRef)
    }
}

