//
//  IRFFFramePoolPolicy.swift
//  IRPlayer-swift
//
//  Created by Codex on 2026/6/2.
//

import Foundation

enum IRFFFramePoolPolicy {
    static func reserveCapacity(from capacity: Int) -> Int {
        return max(0, capacity)
    }

    static func isFrame(_ frame: IRFFFrame?, compatibleWith frameClassName: AnyClass) -> Bool {
        return frame?.isKind(of: frameClassName) == true
    }
}
