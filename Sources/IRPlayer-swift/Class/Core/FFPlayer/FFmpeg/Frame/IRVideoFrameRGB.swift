//
//  IRVideoFrameRGB.swift
//  IRPlayer-swift
//
//  Created by irons on 2024/7/26.
//

import Foundation
import UIKit

enum IRFrameFormat: String, Hashable, Equatable, Sendable, RawRepresentable {
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
        guard let bytesPerRow = Self.bytesPerRow(from: linesize) else {
            return nil
        }

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
            bytesPerRow: bytesPerRow,
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

    static func bytesPerRow(from linesize: UInt) -> Int? {
        guard linesize <= UInt(Int.max) else { return nil }
        return Int(linesize)
    }
}
