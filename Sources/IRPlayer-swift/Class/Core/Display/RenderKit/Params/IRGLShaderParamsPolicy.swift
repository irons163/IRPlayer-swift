//
//  IRGLShaderParamsPolicy.swift
//  IRPlayer-swift
//
//  Created by Codex on 2026/6/2.
//

import Foundation

enum IRGLShaderParamsPolicy {
    static func boundedGLint(from value: Double) -> GLint? {
        guard value.isFinite, value >= Double(GLint.min), value <= Double(GLint.max) else { return nil }
        return GLint(value)
    }
}
