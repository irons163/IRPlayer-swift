//
//  IRYUVTools.swift
//  IRPlayer-swift
//
//  Created by irons on 2024/7/27.
//

import Foundation
import IRFFMpeg

func IRYUVChannelFilterNeedSizeChecked(linesize: Int, width: Int, height: Int, channelCount: Int) -> Int? {
    guard linesize > 0,
          width > 0,
          height > 0,
          channelCount > 0 else {
        return nil
    }

    let adjustedWidth = min(linesize, width)
    let (rowByteCount, rowOverflow) =
        adjustedWidth.multipliedReportingOverflow(
            by: channelCount
        )
    guard !rowOverflow, rowByteCount > 0 else {
        return nil
    }

    let (bufferSize, bufferOverflow) =
        rowByteCount.multipliedReportingOverflow(by: height)
    guard !bufferOverflow, bufferSize > 0 else {
        return nil
    }
    return bufferSize
}

func IRYUVChannelFilterNeedSize(linesize: Int, width: Int, height: Int, channelCount: Int) -> Int {
    IRYUVChannelFilterNeedSizeChecked(
        linesize: linesize,
        width: width,
        height: height,
        channelCount: channelCount
    ) ?? 0
}

func IRYUVImageDimensions32(width: Int, height: Int) -> (width: Int32, height: Int32)? {
    guard width > 0,
          height > 0,
          width <= Int(Int32.max),
          height <= Int(Int32.max) else {
        return nil
    }
    return (Int32(width), Int32(height))
}

func IRYUVSourcePlaneInputsAreValid(srcData: [UnsafePointer<UInt8>?], srcLinesize: [Int32]) -> Bool {
    guard !srcData.isEmpty,
          srcData.count == srcLinesize.count,
          srcData.count <= Int(AV_NUM_DATA_POINTERS),
          srcData[0] != nil,
          srcLinesize[0] > 0 else {
        return false
    }

    for (pointer, lineSize) in zip(srcData, srcLinesize) {
        if pointer != nil, lineSize <= 0 {
            return false
        }
    }
    return true
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

    guard let rowByteCount =
            IRYUVChannelFilterNeedSizeChecked(
                linesize: linesize,
                width: width,
                height: 1,
                channelCount: channelCount
            ),
          let totalByteCount =
            IRYUVChannelFilterNeedSizeChecked(
                linesize: linesize,
                width: width,
                height: height,
                channelCount: channelCount
            ),
          totalByteCount <= dstsize else {
        return
    }

    var source = src
    var destination = dst
    for _ in 0..<height {
        memcpy(destination, source, rowByteCount)
        destination += rowByteCount
        source += linesize
    }
}

func IRYUVConvertToImage(srcData: [UnsafePointer<UInt8>?],
                         srcLinesize: [Int32],
                         width: Int,
                         height: Int,
                         pixelFormat: AVPixelFormat) -> IRPLFImage? {
    guard IRYUVSourcePlaneInputsAreValid(
        srcData: srcData,
        srcLinesize: srcLinesize
    ),
    let session = IRYUVImageConversionSession(
        width: width,
        height: height,
        sourcePixelFormat: pixelFormat
    ) else {
        return nil
    }

    var image: IRPLFImage?
    let outcome = session.withConvertedRGB(
        sourceData: srcData,
        sourceLineSizes: srcLinesize
    ) {
        bytes,
        configuration in
        guard let baseAddress = bytes.baseAddress else {
            return false
        }
        image = IRPLFImageWithRGBData(
            baseAddress,
            linesize: Int(configuration.outputLineSize),
            width: Int(configuration.width),
            height: Int(configuration.height)
        )
        return image != nil
    }
    return outcome == .converted ? image : nil
}
