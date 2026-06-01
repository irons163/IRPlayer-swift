//
//  IRMetalRendererDistortionPolicy.swift
//  IRPlayer-swift
//
//  Created by Codex on 2026/6/2.
//

import CoreGraphics
import Metal

enum IRMetalRendererDistortionPolicy {
    static func distortionTextureSize(from size: CGSize) -> (width: Int, height: Int)? {
        guard size.width.isFinite,
              size.height.isFinite,
              size.width > 0,
              size.height > 0,
              size.width <= CGFloat(Int.max),
              size.height <= CGFloat(Int.max) else {
            return nil
        }
        return (Int(size.width), Int(size.height))
    }

    static func distortionScissorRects(drawableSize: CGSize) -> (left: MTLScissorRect, right: MTLScissorRect)? {
        guard let textureSize = distortionTextureSize(from: drawableSize) else { return nil }
        let leftWidth = textureSize.width / 2
        let rightWidth = textureSize.width - leftWidth
        return (
            MTLScissorRect(x: 0, y: 0, width: leftWidth, height: textureSize.height),
            MTLScissorRect(x: leftWidth, y: 0, width: rightWidth, height: textureSize.height)
        )
    }
}
