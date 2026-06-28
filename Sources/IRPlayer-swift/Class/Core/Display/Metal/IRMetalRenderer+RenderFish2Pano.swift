//
//  IRMetalRenderer+RenderFish2Pano.swift
//  IRPlayer-swift
//
//  Created by Codex on 2026/3/13.
//

import Foundation
import Metal
import CoreVideo
import simd
import QuartzCore

extension IRMetalRenderer {

    func renderFish2Pano(frame: IRFFVideoFrame,
                         params: Fish2PanoParams,
                         texUVTextures: [MTLTexture],
                         to drawable: CAMetalDrawable,
                         drawableSize: CGSize,
                         viewport: CGRect,
                         contentMode: IRGLRenderContentMode,
                         outputSize: CGSize,
                         zoomScale: Float,
                         translation: SIMD2<Float>) -> Bool {
        guard Self.fish2PanoInputsAreValid(params: params, texUVTextureCount: texUVTextures.count) else { return false }
        guard let commandBuffer = commandQueue.makeCommandBuffer() else { return false }
        guard let renderPass = currentRenderPassDescriptor(drawable: drawable) else { return false }
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPass) else { return false }

        encoder.setViewport(Self.metalViewport(drawableSize: drawableSize,
                                               viewport: viewport,
                                               orientation: .topLeftFlipped))

        let targetSize = viewport.size
        let scale = computeScale(contentMode: contentMode, frameSize: outputSize, drawableSize: targetSize)
        var scaleVector = SIMD2<Float>(Float(scale.width), Float(scale.height)) * zoomScale

        encoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
        encoder.setVertexBytes(&scaleVector, length: MemoryLayout<SIMD2<Float>>.size, index: 1)
        var translationVector = translation
        encoder.setVertexBytes(&translationVector, length: MemoryLayout<SIMD2<Float>>.size, index: 2)

        var fishParams = params
        encoder.setFragmentBytes(&fishParams, length: MemoryLayout<Fish2PanoParams>.size, index: 0)

        for i in 0..<9 {
            let textureIndex = i + 4
            if i < texUVTextures.count {
                encoder.setFragmentTexture(texUVTextures[i], index: textureIndex)
            } else {
                encoder.setFragmentTexture(nil as MTLTexture?, index: textureIndex)
            }
        }

        var didRender = false
        if let pixelRenderer = pixelRenderer(for: frame) {
            didRender = pixelRenderer.renderFish2Pano(renderer: self,
                                                      frame: frame,
                                                      encoder: encoder,
                                                      params: fishParams,
                                                      texUVTextures: texUVTextures)
        }

        encoder.endEncoding()
        if didRender {
            commandBuffer.present(drawable)
            commandBuffer.commit()
        }
        return didRender
    }

}
