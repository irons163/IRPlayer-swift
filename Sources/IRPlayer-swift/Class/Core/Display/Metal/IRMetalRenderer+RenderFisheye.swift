//
//  IRMetalRenderer+RenderFisheye.swift
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

    func renderFisheye(frame: IRFFVideoFrame,
                       mesh: IRMetalFisheyeMesh,
                       mvp: simd_float4x4,
                       textureMatrix: simd_float4x4,
                       to drawable: CAMetalDrawable,
                       drawableSize: CGSize,
                       viewport: CGRect) -> Bool {
        guard let commandBuffer = commandQueue.makeCommandBuffer() else { return false }
        guard let renderPass = currentRenderPassDescriptor(drawable: drawable) else { return false }
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPass) else { return false }

        encoder.setViewport(Self.metalViewport(drawableSize: drawableSize,
                                               viewport: viewport,
                                               orientation: .bottomLeft))
        encoder.setVertexBuffer(mesh.vertexBuffer, offset: 0, index: 0)
        var mvpMatrix = mvp
        var texMatrix = textureMatrix
        encoder.setVertexBytes(&mvpMatrix, length: MemoryLayout<simd_float4x4>.size, index: 1)
        encoder.setVertexBytes(&texMatrix, length: MemoryLayout<simd_float4x4>.size, index: 2)

        var didRender = false
        if let pixelRenderer = pixelRenderer(for: frame) {
            didRender = pixelRenderer.renderMesh(renderer: self,
                                                 frame: frame,
                                                 encoder: encoder,
                                                 indexCount: mesh.indexCount,
                                                 indexBuffer: mesh.indexBuffer)
        }

        encoder.endEncoding()
        if didRender {
            commandBuffer.present(drawable)
            commandBuffer.commit()
        }
        return didRender
    }

    func renderFisheyeMulti(frame: IRFFVideoFrame,
                            mesh: IRMetalFisheyeMesh,
                            mvpList: [simd_float4x4],
                            textureMatrix: simd_float4x4,
                            to drawable: CAMetalDrawable,
                            drawableSize: CGSize,
                            viewports: [CGRect]) -> Bool {
        guard !viewports.isEmpty, viewports.count == mvpList.count else { return false }
        guard let commandBuffer = commandQueue.makeCommandBuffer() else { return false }
        guard let renderPass = currentRenderPassDescriptor(drawable: drawable) else { return false }
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPass) else { return false }

        encoder.setVertexBuffer(mesh.vertexBuffer, offset: 0, index: 0)
        var texMatrix = textureMatrix
        encoder.setVertexBytes(&texMatrix, length: MemoryLayout<simd_float4x4>.size, index: 2)

        var didRender = false

        if let pixelRenderer = pixelRenderer(for: frame) {
            for (index, viewport) in viewports.enumerated() {
                encoder.setViewport(Self.metalViewport(drawableSize: drawableSize,
                                                       viewport: viewport,
                                                       orientation: .bottomLeft))
                var mvpMatrix = mvpList[index]
                encoder.setVertexBytes(&mvpMatrix, length: MemoryLayout<simd_float4x4>.size, index: 1)
                if !pixelRenderer.renderMesh(renderer: self,
                                             frame: frame,
                                             encoder: encoder,
                                             indexCount: mesh.indexCount,
                                             indexBuffer: mesh.indexBuffer) {
                    encoder.endEncoding()
                    return false
                }
            }
            didRender = true
        }

        encoder.endEncoding()
        if didRender {
            commandBuffer.present(drawable)
            commandBuffer.commit()
        }
        return didRender
    }

}
