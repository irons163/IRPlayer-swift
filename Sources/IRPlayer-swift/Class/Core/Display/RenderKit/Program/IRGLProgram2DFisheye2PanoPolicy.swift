//
//  IRGLProgram2DFisheye2PanoPolicy.swift
//  IRPlayer-swift
//
//  Created by Codex on 2026/6/2.
//

import Foundation

enum IRGLProgram2DFisheye2PanoPolicy {

    static func textureSize(from params: IRGLFish2PanoShaderParams?) -> (width: Int, height: Int)? {
        guard let params else { return nil }
        return (Int(params.textureWidth), Int(params.textureHeight))
    }

    static func normalizedOffsetX(currentOffset: Float, delta: Float, outputWidth: GLint) -> Float? {
        guard outputWidth > 0, currentOffset.isFinite, delta.isFinite else { return nil }

        let width = Float(outputWidth)
        var offset = currentOffset - delta
        while offset > width || offset < -width {
            if offset > width {
                offset -= width
            } else if offset < -width {
                offset += width
            }
        }

        return offset
    }
}
