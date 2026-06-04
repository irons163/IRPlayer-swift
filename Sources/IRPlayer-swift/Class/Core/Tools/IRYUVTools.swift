//
//  IRYUVTools.swift
//  IRPlayer-swift
//
//  Created by irons on 2024/7/27.
//

import Foundation
import CoreGraphics
import IRFFMpeg

func IRYUVChannelFilterNeedSizeChecked(linesize: Int, width: Int, height: Int, channelCount: Int) -> Int? {
    return IRYUVToolsPolicy.channelFilterNeedSizeChecked(linesize: linesize, width: width, height: height, channelCount: channelCount)
}

func IRYUVChannelFilterNeedSize(linesize: Int, width: Int, height: Int, channelCount: Int) -> Int {
    return IRYUVToolsPolicy.channelFilterNeedSize(linesize: linesize, width: width, height: height, channelCount: channelCount)
}

func IRYUVImageDimensions32(width: Int, height: Int) -> (width: Int32, height: Int32)? {
    return IRYUVToolsPolicy.imageDimensions32(width: width, height: height)
}

func IRYUVChannelFilter(src: UnsafePointer<UInt8>, 
                        linesize: Int,
                        width: Int,
                        height: Int,
                        dst: UnsafeMutablePointer<UInt8>,
                        dstsize: Int,
                        channelCount: Int) {
    IRYUVToolsPolicy.channelFilter(src: src, linesize: linesize, width: width, height: height, dst: dst, dstsize: dstsize, channelCount: channelCount)
}

func IRYUVConvertToImage(srcData: [UnsafePointer<UInt8>?],
                         srcLinesize: [Int32],
                         width: Int,
                         height: Int,
                         pixelFormat: AVPixelFormat) -> IRPLFImage? {
    guard let dimensions = IRYUVImageDimensions32(width: width, height: height) else { return nil }

    var swsContext: OpaquePointer? = nil
//    swsContext = sws_getCachedContext(swsContext, width, height, pixelFormat, width, height, AV_PIX_FMT_RGB24, SWS_FAST_BILINEAR, nil, nil, nil)
    swsContext = sws_getCachedContext(swsContext, dimensions.width, dimensions.height, pixelFormat, dimensions.width, dimensions.height, AV_PIX_FMT_RGB24, 1, nil, nil, nil)
    guard let context = swsContext else {
        return nil
    }

    var data = [UnsafeMutablePointer<UInt8>?](repeating: nil, count: Int(AV_NUM_DATA_POINTERS))
    var linesize = [Int32](repeating: 0, count: Int(AV_NUM_DATA_POINTERS))

    let result = av_image_alloc(&data, &linesize, dimensions.width, dimensions.height, AV_PIX_FMT_RGB24, 1)
    if result < 0 {
        sws_freeContext(context)
        return nil
    }

    let scaleResult = sws_scale(context, srcData, srcLinesize, 0, dimensions.height, &data, &linesize)
    sws_freeContext(context)
    if scaleResult < 0 {
        av_freep(&data[0])
        return nil
    }
    guard linesize[0] > 0, let firstData = data[0] else {
        av_freep(&data[0])
        return nil
    }

    let image = IRPLFImageWithRGBData(firstData, linesize: Int(linesize[0]), width: width, height: height)
    av_freep(&data[0])

    return image
}
