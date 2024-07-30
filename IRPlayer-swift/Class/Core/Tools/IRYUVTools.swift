//
//  IRYUVTools.swift
//  IRPlayer-swift
//
//  Created by irons on 2024/7/27.
//

import Foundation
import CoreGraphics

func IRYUVChannelFilterNeedSize(linesize: Int, width: Int, height: Int, channelCount: Int) -> Int {
    let adjustedWidth = min(linesize, width)
    return adjustedWidth * height * channelCount
}

func IRYUVChannelFilter(src: UnsafePointer<UInt8>, 
                        linesize: Int,
                        width: Int,
                        height: Int,
                        dst: UnsafeMutablePointer<UInt8>,
                        dstsize: Int,
                        channelCount: Int) {
    var src = src
    let adjustedWidth = min(linesize, width)
    var temp = dst
    memset(dst, 0, dstsize)
    for _ in 0..<height {
        memcpy(temp, src, adjustedWidth * channelCount)
        temp += adjustedWidth * channelCount
        src += linesize
    }
}

func IRYUVConvertToImage(srcData: [UnsafePointer<UInt8>?],
                         srcLinesize: [Int32],
                         width: Int,
                         height: Int,
                         pixelFormat: AVPixelFormat) -> IRPLFImage? {
    var swsContext: OpaquePointer? = nil
//    swsContext = sws_getCachedContext(swsContext, width, height, pixelFormat, width, height, AV_PIX_FMT_RGB24, SWS_FAST_BILINEAR, nil, nil, nil)
    swsContext = sws_getCachedContext(swsContext, Int32(width), Int32(height), pixelFormat, Int32(width), Int32(height), AV_PIX_FMT_RGB24, 1, nil, nil, nil)
    guard let context = swsContext else {
        return nil
    }

    var data = [UnsafeMutablePointer<UInt8>?](repeating: nil, count: Int(AV_NUM_DATA_POINTERS))
    var linesize = [Int32](repeating: 0, count: Int(AV_NUM_DATA_POINTERS))

    let result = av_image_alloc(&data, &linesize, Int32(width), Int32(height), AV_PIX_FMT_RGB24, 1)
    if result < 0 {
        sws_freeContext(context)
        return nil
    }

    let scaleResult = sws_scale(context, srcData, srcLinesize, 0, Int32(height), &data, &linesize)
    sws_freeContext(context)
    if scaleResult < 0 {
        av_freep(&data[0])
        return nil
    }
    guard linesize[0] > 0, data[0] != nil else {
        av_freep(&data[0])
        return nil
    }

    let image = IRPLFImageWithRGBData(data[0], linesize[0], Int32(width), Int32(height))
    av_freep(&data[0])

    return image
}
