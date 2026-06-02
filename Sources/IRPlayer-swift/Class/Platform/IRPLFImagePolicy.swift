//
//  IRPLFImagePolicy.swift
//  IRPlayer-swift
//
//  Created by Codex on 2026/6/2.
//

import Foundation

enum IRPLFImagePolicy {
    static func rgbDataByteCount(linesize: Int, width: Int, height: Int) -> Int? {
        guard linesize > 0, width > 0, height > 0 else { return nil }

        let (minimumLineSize, minimumLineSizeOverflow) = width.multipliedReportingOverflow(by: 3)
        guard !minimumLineSizeOverflow, linesize >= minimumLineSize else { return nil }

        let (byteCount, byteCountOverflow) = linesize.multipliedReportingOverflow(by: height)
        guard !byteCountOverflow else { return nil }
        return byteCount
    }
}
