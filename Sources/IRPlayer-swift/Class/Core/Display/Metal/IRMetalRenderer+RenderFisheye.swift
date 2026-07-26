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
        renderFisheye(
            frame: frame,
            mesh: mesh,
            mvp: mvp,
            textureMatrix: textureMatrix,
            to: drawable,
            drawableSize: drawableSize,
            viewport: viewport,
            completion: {}
        )
    }

    func renderFisheye(frame: IRFFVideoFrame,
                       mesh: IRMetalFisheyeMesh,
                       mvp: simd_float4x4,
                       textureMatrix: simd_float4x4,
                       to drawable: CAMetalDrawable,
                       drawableSize: CGSize,
                       viewport: CGRect,
                       completion: @escaping IRGLRenderCompletion) -> Bool {
        guard meshBuffersAreCompatible(mesh),
              Self.matrixIsFinite(mvp),
              Self.matrixIsFinite(textureMatrix),
              meshDrawableIsCompatible(drawable) else {
            return false
        }
        let metalViewport = Self.metalViewport(
            drawableSize: drawableSize,
            viewport: viewport,
            orientation: .bottomLeft
        )
        guard metalViewport.width > 0,
              metalViewport.height > 0 else {
            return false
        }
        guard let commandBuffer = commandQueue.makeCommandBuffer() else { return false }
        let commandResources = IRMetalCommandResources()
        guard let renderPass = currentRenderPassDescriptor(drawable: drawable) else { return false }
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPass) else { return false }

        encoder.setViewport(metalViewport)
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
                                                 indexBuffer: mesh.indexBuffer,
                                                 resources: commandResources)
        }

        encoder.endEncoding()
        if didRender {
            guard commandResources.submit(
                to: commandBuffer,
                completion: completion
            ) else {
                return false
            }
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
        renderFisheyeMulti(
            frame: frame,
            mesh: mesh,
            mvpList: mvpList,
            textureMatrix: textureMatrix,
            to: drawable,
            drawableSize: drawableSize,
            viewports: viewports,
            completion: {}
        )
    }

    func renderFisheyeMulti(frame: IRFFVideoFrame,
                            mesh: IRMetalFisheyeMesh,
                            mvpList: [simd_float4x4],
                            textureMatrix: simd_float4x4,
                            to drawable: CAMetalDrawable,
                            drawableSize: CGSize,
                            viewports: [CGRect],
                            completion: @escaping IRGLRenderCompletion) -> Bool {
        guard !viewports.isEmpty,
              viewports.count == mvpList.count,
              meshBuffersAreCompatible(mesh),
              mvpList.allSatisfy(Self.matrixIsFinite),
              Self.matrixIsFinite(textureMatrix),
              meshDrawableIsCompatible(drawable) else {
            return false
        }
        let metalViewports = viewports.map {
            Self.metalViewport(
                drawableSize: drawableSize,
                viewport: $0,
                orientation: .bottomLeft
            )
        }
        guard metalViewports.allSatisfy({
            $0.width > 0 && $0.height > 0
        }) else {
            return false
        }
        guard let commandBuffer = commandQueue.makeCommandBuffer() else { return false }
        let commandResources = IRMetalCommandResources()
        guard let renderPass = currentRenderPassDescriptor(drawable: drawable) else { return false }
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPass) else { return false }

        encoder.setVertexBuffer(mesh.vertexBuffer, offset: 0, index: 0)
        var texMatrix = textureMatrix
        encoder.setVertexBytes(&texMatrix, length: MemoryLayout<simd_float4x4>.size, index: 2)

        var didRender = false

        if let pixelRenderer = pixelRenderer(for: frame) {
            for (index, metalViewport) in
                metalViewports.enumerated() {
                encoder.setViewport(metalViewport)
                var mvpMatrix = mvpList[index]
                encoder.setVertexBytes(&mvpMatrix, length: MemoryLayout<simd_float4x4>.size, index: 1)
                if !pixelRenderer.renderMesh(renderer: self,
                                             frame: frame,
                                             encoder: encoder,
                                             indexCount: mesh.indexCount,
                                             indexBuffer: mesh.indexBuffer,
                                             resources: commandResources) {
                    encoder.endEncoding()
                    return false
                }
            }
            didRender = true
        }

        encoder.endEncoding()
        if didRender {
            guard commandResources.submit(
                to: commandBuffer,
                completion: completion
            ) else {
                return false
            }
            commandBuffer.present(drawable)
            commandBuffer.commit()
        }
        return didRender
    }

    private func meshBuffersAreCompatible(
        _ mesh: IRMetalFisheyeMesh
    ) -> Bool {
        mesh.vertexBuffer.device === device
            && mesh.indexBuffer.device === device
    }

    private func meshDrawableIsCompatible(
        _ drawable: CAMetalDrawable
    ) -> Bool {
        let texture = drawable.texture
        return texture.device === device
            && texture.pixelFormat == .bgra8Unorm
            && texture.textureType == .type2D
            && texture.width > 0
            && texture.height > 0
    }

    private static func matrixIsFinite(
        _ matrix: simd_float4x4
    ) -> Bool {
        for columnIndex in 0..<4 {
            let column = matrix[columnIndex]
            for componentIndex in 0..<4
                where !column[componentIndex].isFinite {
                return false
            }
        }
        return true
    }

}
