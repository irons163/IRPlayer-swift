//
//  IRYUVToolsPolicy.swift
//  IRPlayer-swift
//
//  Created by Codex on 2026/6/2.
//

import Foundation

enum IRYUVToolsPolicy {
    static func channelFilterNeedSizeChecked(linesize: Int, width: Int, height: Int, channelCount: Int) -> Int? {
        guard linesize > 0, width > 0, height > 0, channelCount > 0 else { return nil }

        let adjustedWidth = min(linesize, width)
        let (rowByteCount, rowOverflow) = adjustedWidth.multipliedReportingOverflow(by: channelCount)
        guard !rowOverflow, rowByteCount > 0 else { return nil }

        let (bufferSize, bufferOverflow) = rowByteCount.multipliedReportingOverflow(by: height)
        guard !bufferOverflow, bufferSize > 0 else { return nil }
        return bufferSize
    }

    static func channelFilterNeedSize(linesize: Int, width: Int, height: Int, channelCount: Int) -> Int {
        return channelFilterNeedSizeChecked(linesize: linesize, width: width, height: height, channelCount: channelCount) ?? 0
    }

    static func imageDimensions32(width: Int, height: Int) -> (width: Int32, height: Int32)? {
        guard width > 0, height > 0, width <= Int(Int32.max), height <= Int(Int32.max) else { return nil }
        return (Int32(width), Int32(height))
    }

    static func sourcePlaneInputsAreValid(srcData: [UnsafePointer<UInt8>?], srcLinesize: [Int32]) -> Bool {
        guard !srcData.isEmpty,
              srcData.count == srcLinesize.count,
              srcData[0] != nil,
              srcLinesize[0] > 0 else {
            return false
        }
        return true
    }

    static func channelFilter(src: UnsafePointer<UInt8>,
                              linesize: Int,
                              width: Int,
                              height: Int,
                              dst: UnsafeMutablePointer<UInt8>,
                              dstsize: Int,
                              channelCount: Int) {
        guard dstsize > 0 else { return }
        memset(dst, 0, dstsize)

        guard let rowByteCount = channelFilterNeedSizeChecked(linesize: linesize, width: width, height: 1, channelCount: channelCount),
              let totalByteCount = channelFilterNeedSizeChecked(linesize: linesize, width: width, height: height, channelCount: channelCount),
              totalByteCount <= dstsize else { return }

        var src = src
        var temp = dst
        for _ in 0..<height {
            memcpy(temp, src, rowByteCount)
            temp += rowByteCount
            src += linesize
        }
    }
}
