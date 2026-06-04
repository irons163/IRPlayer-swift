//
//  IRMetalRenderer+RenderDistortion.swift
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

    func renderDistortion(frame: IRFFVideoFrame,
                          leftMesh: IRMetalDistortionMesh,
                          rightMesh: IRMetalDistortionMesh,
                          to drawable: CAMetalDrawable,
                          drawableSize: CGSize,
                          contentMode: IRGLRenderContentMode) -> Bool {
        guard let commandBuffer = commandQueue.makeCommandBuffer() else { return false }
        guard let offscreen = makeDistortionOffscreenTexture(size: drawableSize) else { return false }

        let offscreenPass = MTLRenderPassDescriptor()
        offscreenPass.colorAttachments[0].texture = offscreen
        offscreenPass.colorAttachments[0].loadAction = .clear
        offscreenPass.colorAttachments[0].storeAction = .store
        offscreenPass.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 1)

        guard let offscreenEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: offscreenPass) else { return false }
        offscreenEncoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)

        let halfWidth = drawableSize.width / 2.0
        func renderHalf(originX: Double, isLeft: Bool) -> Bool {
            // Distortion expects the offscreen texture to fill each eye half.
            var scaleVector = SIMD2<Float>(1.0, 1.0)
            var translationVector = SIMD2<Float>(repeating: 0)
            offscreenEncoder.setVertexBytes(&scaleVector, length: MemoryLayout<SIMD2<Float>>.size, index: 1)
            offscreenEncoder.setVertexBytes(&translationVector, length: MemoryLayout<SIMD2<Float>>.size, index: 2)
            if let buffer = isLeft ? vertexBufferLeft : vertexBufferRight {
                offscreenEncoder.setVertexBuffer(buffer, offset: 0, index: 0)
            } else {
                offscreenEncoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
            }
            offscreenEncoder.setViewport(MTLViewport(originX: originX,
                                                     originY: 0,
                                                     width: Double(halfWidth),
                                                     height: Double(drawableSize.height),
                                                     znear: 0,
                                                     zfar: 1))

            if let pixelRenderer = pixelRenderer(for: frame) {
                return pixelRenderer.render2D(renderer: self, frame: frame, encoder: offscreenEncoder)
            }
            return false
        }

        let leftRendered = renderHalf(originX: 0, isLeft: true)
        let rightRendered = renderHalf(originX: Double(halfWidth), isLeft: false)
        offscreenEncoder.endEncoding()

        guard leftRendered || rightRendered else { return false }
        guard let renderPass = currentRenderPassDescriptor(drawable: drawable) else { return false }
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPass) else { return false }
        guard let pipelineDistortion = pipelineDistortion else { return false }

        encoder.setRenderPipelineState(pipelineDistortion)
        encoder.setFragmentTexture(offscreen, index: 0)
        encoder.setViewport(MTLViewport(originX: 0,
                                        originY: 0,
                                        width: Double(drawableSize.width),
                                        height: Double(drawableSize.height),
                                        znear: 0,
                                        zfar: 1))

        guard let scissorRects = Self.distortionScissorRects(drawableSize: drawableSize) else { return false }

        encoder.setScissorRect(scissorRects.left)
        encoder.setVertexBuffer(leftMesh.vertexBuffer, offset: 0, index: 0)
        encoder.drawIndexedPrimitives(type: MTLPrimitiveType.triangleStrip,
                                      indexCount: leftMesh.indexCount,
                                      indexType: MTLIndexType.uint16,
                                      indexBuffer: leftMesh.indexBuffer,
                                      indexBufferOffset: 0)

        encoder.setScissorRect(scissorRects.right)
        encoder.setVertexBuffer(rightMesh.vertexBuffer, offset: 0, index: 0)
        encoder.drawIndexedPrimitives(type: MTLPrimitiveType.triangleStrip,
                                      indexCount: rightMesh.indexCount,
                                      indexType: MTLIndexType.uint16,
                                      indexBuffer: rightMesh.indexBuffer,
                                      indexBufferOffset: 0)

        encoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
        return true
    }

    private func makeDistortionOffscreenTexture(size: CGSize) -> MTLTexture? {
        guard let textureSize = Self.distortionTextureSize(from: size) else { return nil }
        if let texture = distortionOffscreenTexture,
           distortionOffscreenSize == size {
            return texture
        }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: textureSize.width, height: textureSize.height, mipmapped: false)
        descriptor.usage = [.renderTarget, .shaderRead]
        guard let texture = device.makeTexture(descriptor: descriptor) else { return nil }
        distortionOffscreenTexture = texture
        distortionOffscreenSize = size
        return texture
    }

    static func distortionTextureSize(from size: CGSize) -> (width: Int, height: Int)? {
        IRMetalRendererDistortionPolicy.distortionTextureSize(from: size)
    }

    static func distortionScissorRects(drawableSize: CGSize) -> (left: MTLScissorRect, right: MTLScissorRect)? {
        IRMetalRendererDistortionPolicy.distortionScissorRects(drawableSize: drawableSize)
    }

}
