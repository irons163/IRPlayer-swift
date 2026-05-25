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
    guard linesize > 0, width > 0, height > 0, channelCount > 0 else { return nil }

    let adjustedWidth = min(linesize, width)
    let (rowByteCount, rowOverflow) = adjustedWidth.multipliedReportingOverflow(by: channelCount)
    guard !rowOverflow, rowByteCount > 0 else { return nil }

    let (bufferSize, bufferOverflow) = rowByteCount.multipliedReportingOverflow(by: height)
    guard !bufferOverflow, bufferSize > 0 else { return nil }
    return bufferSize
}

func IRYUVChannelFilterNeedSize(linesize: Int, width: Int, height: Int, channelCount: Int) -> Int {
    return IRYUVChannelFilterNeedSizeChecked(linesize: linesize, width: width, height: height, channelCount: channelCount) ?? 0
}

func IRYUVImageDimensions32(width: Int, height: Int) -> (width: Int32, height: Int32)? {
    guard width > 0, height > 0, width <= Int(Int32.max), height <= Int(Int32.max) else { return nil }
    return (Int32(width), Int32(height))
}

func IRYUVChannelFilter(src: UnsafePointer<UInt8>, 
                        linesize: Int,
                        width: Int,
                        height: Int,
                        dst: UnsafeMutablePointer<UInt8>,
                        dstsize: Int,
                        channelCount: Int) {
    guard dstsize > 0 else { return }
    memset(dst, 0, dstsize)

    guard let rowByteCount = IRYUVChannelFilterNeedSizeChecked(linesize: linesize, width: width, height: 1, channelCount: channelCount),
          let totalByteCount = IRYUVChannelFilterNeedSizeChecked(linesize: linesize, width: width, height: height, channelCount: channelCount),
          totalByteCount <= dstsize else { return }

    var src = src
    var temp = dst
    for _ in 0..<height {
        memcpy(temp, src, rowByteCount)
        temp += rowByteCount
        src += linesize
    }
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
