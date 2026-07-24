//
//  IRMetalRenderer+RenderMesh.swift
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

    func renderNV12Mesh(cvFrame: IRFFCVYUVVideoFrame,
                        encoder: MTLRenderCommandEncoder,
                        indexCount: Int,
                        indexBuffer: MTLBuffer,
                        resources: IRMetalCommandResources) -> Bool {
        guard let generation = frameTextureGeneration(
            for: cvFrame,
            resources: resources
        ),
        case let .nv12(y, uv) = generation.textures else {
            return false
        }
        encoder.setRenderPipelineState(pipelineNV12Mesh)
        encoder.setFragmentTexture(y, index: 0)
        encoder.setFragmentTexture(uv, index: 1)
        encoder.drawIndexedPrimitives(type: .triangle, indexCount: indexCount, indexType: .uint16, indexBuffer: indexBuffer, indexBufferOffset: 0)
        return true
    }

    func renderBGRAMesh(cvFrame: IRFFCVYUVVideoFrame,
                        encoder: MTLRenderCommandEncoder,
                        indexCount: Int,
                        indexBuffer: MTLBuffer,
                        resources: IRMetalCommandResources) -> Bool {
        guard let generation = frameTextureGeneration(
            for: cvFrame,
            resources: resources
        ),
        case let .bgra(texture) = generation.textures else {
            return false
        }
        encoder.setRenderPipelineState(pipelineRGBMesh)
        encoder.setFragmentTexture(texture, index: 0)
        encoder.drawIndexedPrimitives(type: .triangle, indexCount: indexCount, indexType: .uint16, indexBuffer: indexBuffer, indexBufferOffset: 0)
        return true
    }

    func renderI420Mesh(yuvFrame: IRFFAVYUVVideoFrame,
                        encoder: MTLRenderCommandEncoder,
                        indexCount: Int,
                        indexBuffer: MTLBuffer,
                        resources: IRMetalCommandResources) -> Bool {
        guard let generation = frameTextureGeneration(
            for: yuvFrame,
            resources: resources
        ),
        case let .i420(y, u, v) = generation.textures else {
            return false
        }
        encoder.setRenderPipelineState(pipelineI420Mesh)
        encoder.setFragmentTexture(y, index: 0)
        encoder.setFragmentTexture(u, index: 1)
        encoder.setFragmentTexture(v, index: 2)
        encoder.drawIndexedPrimitives(type: .triangle, indexCount: indexCount, indexType: .uint16, indexBuffer: indexBuffer, indexBufferOffset: 0)
        return true
    }

}
