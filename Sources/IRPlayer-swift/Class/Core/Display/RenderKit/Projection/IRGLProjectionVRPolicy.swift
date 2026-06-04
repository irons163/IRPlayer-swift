//
//  IRGLProjectionVRPolicy.swift
//  IRPlayer-swift
//
//  Created by Codex on 2026/6/2.
//

import Foundation

enum IRGLProjectionVRPolicy {
    static func glIndex(_ value: Int) -> GLushort? {
        guard value >= 0, value <= Int(GLushort.max) else { return nil }
        return GLushort(value)
    }
}
