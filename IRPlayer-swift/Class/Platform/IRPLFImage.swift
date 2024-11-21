//
//  IRPLFImage.swift
//  IRPlayer-swift
//
//  Created by irons on 2024/11/21.
//

import Foundation
import UIKit

typealias IRPLFImage = UIImage

// Function to create UIImage from CGImage
func IRPLFImageWithCGImage(_ image: CGImage) -> IRPLFImage {
    return UIImage(cgImage: image)
}

// Function to create UIImage from RGB data buffer
func IRPLFImageWithRGBData(_ rgbData: UnsafePointer<UInt8>, linesize: Int, width: Int, height: Int) -> IRPLFImage? {
    guard let imageRef = IRPLFImageCGImageWithRGBData(rgbData, linesize: linesize, width: width, height: height) else {
        return nil
    }
    let image = IRPLFImageWithCGImage(imageRef)
    return image
}

// Function to create CGImage from RGB data buffer
func IRPLFImageCGImageWithRGBData(_ rgbData: UnsafePointer<UInt8>, linesize: Int, width: Int, height: Int) -> CGImage? {
    guard let data = CFDataCreate(kCFAllocatorDefault, rgbData, linesize * height) else { return nil }
    guard let provider = CGDataProvider(data: data) else {
        return nil
    }

    guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else {
        return nil
    }

    let imageRef = CGImage(
        width: width,
        height: height,
        bitsPerComponent: 8,
        bitsPerPixel: 24,
        bytesPerRow: linesize,
        space: colorSpace,
        bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
        provider: provider,
        decode: nil,
        shouldInterpolate: false,
        intent: .defaultIntent
    )

    return imageRef
}
