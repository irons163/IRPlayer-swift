//
//  IRYUVChannelFilterPolicy.swift
//  IRPlayer-swift
//
//  Created by Codex on 2026/6/2.
//

import Foundation

enum IRYUVChannelFilterPolicy {
    static func needSize(linesize: Int32, width: Int, height: Int, channelCount: Int) -> Int {
        return IRYUVChannelFilterNeedSizeChecked(linesize: Int(linesize), width: width, height: height, channelCount: channelCount) ?? 0
    }

    static func copy(_ source: UnsafePointer<UInt8>,
                     linesize: Int32,
                     width: Int,
                     height: Int,
                     destination: UnsafeMutablePointer<UInt8>?,
                     bufferSize: Int,
                     channelCount: Int) {
        guard let destination = destination else { return }

        let linesize = Int(linesize)
        guard let rowByteCount = IRYUVChannelFilterNeedSizeChecked(linesize: linesize, width: width, height: 1, channelCount: channelCount),
              let totalByteCount = IRYUVChannelFilterNeedSizeChecked(linesize: linesize, width: width, height: height, channelCount: channelCount),
              totalByteCount <= bufferSize else { return }

        for y in 0..<height {
            let srcRow = source + y * linesize
            let dstRow = destination + y * rowByteCount
            memcpy(dstRow, srcRow, rowByteCount)
        }
    }
}
