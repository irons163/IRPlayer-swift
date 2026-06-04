//
//  IRVideoFrameRGBPolicy.swift
//  IRPlayer-swift
//
//  Created by Codex on 2026/6/2.
//

import Foundation

enum IRVideoFrameRGBPolicy {
    static func bytesPerRow(from linesize: UInt) -> Int? {
        guard linesize <= UInt(Int.max) else { return nil }
        return Int(linesize)
    }
}
