//
//  IRMetalRendererGeometryPolicy.swift
//  IRPlayer-swift
//
//  Created by Codex on 2026/6/2.
//

import CoreGraphics
import Metal
import simd

enum IRMetalRendererGeometryPolicy {
    static func quadVertices(textureRange: IRMetalRenderer.QuadTextureRange) -> [IRMetalRenderer.QuadVertex] {
        let minU: Float
        let maxU: Float
        switch textureRange {
        case .full:
            minU = 0.0
            maxU = 1.0
        case .left:
            minU = 0.0
            maxU = 0.5
        case .right:
            minU = 0.5
            maxU = 1.0
        }

        return [
            IRMetalRenderer.QuadVertex(position: SIMD2<Float>(-1.0, -1.0), texCoord: SIMD2<Float>(minU, 1.0)),
            IRMetalRenderer.QuadVertex(position: SIMD2<Float>( 1.0, -1.0), texCoord: SIMD2<Float>(maxU, 1.0)),
            IRMetalRenderer.QuadVertex(position: SIMD2<Float>(-1.0,  1.0), texCoord: SIMD2<Float>(minU, 0.0)),
            IRMetalRenderer.QuadVertex(position: SIMD2<Float>( 1.0,  1.0), texCoord: SIMD2<Float>(maxU, 0.0))
        ]
    }

    static func metalViewport(drawableSize: CGSize,
                              viewport: CGRect,
                              orientation: IRMetalRenderer.MetalViewportOrientation) -> MTLViewport {
        guard drawableSize.width.isFinite,
              drawableSize.height.isFinite,
              viewport.origin.x.isFinite,
              viewport.origin.y.isFinite,
              viewport.size.width.isFinite,
              viewport.size.height.isFinite,
              drawableSize.width > 0,
              drawableSize.height > 0,
              viewport.size.width > 0,
              viewport.size.height > 0 else {
            return MTLViewport(originX: 0, originY: 0, width: 0, height: 0, znear: 0, zfar: 1)
        }

        let originY: CGFloat
        let height: CGFloat
        switch orientation {
        case .topLeftFlipped:
            originY = drawableSize.height - viewport.origin.y
            height = -viewport.size.height
        case .bottomLeft:
            originY = drawableSize.height - viewport.origin.y - viewport.size.height
            height = viewport.size.height
        }

        return MTLViewport(originX: Double(viewport.origin.x),
                           originY: Double(originY),
                           width: Double(viewport.size.width),
                           height: Double(height),
                           znear: 0,
                           zfar: 1)
    }
}
