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
                                indexBuffer: MTLBuffer) -> Bool {
        guard let pipeline = pipelineNV12Mesh else { return false }
        guard let textures = makeNV12Textures(from: cvFrame) else { return false }
        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentTexture(textures.y, index: 0)
        encoder.setFragmentTexture(textures.uv, index: 1)
        encoder.drawIndexedPrimitives(type: .triangle, indexCount: indexCount, indexType: .uint16, indexBuffer: indexBuffer, indexBufferOffset: 0)
        return true
    }

    func renderBGRAMesh(cvFrame: IRFFCVYUVVideoFrame,
                                encoder: MTLRenderCommandEncoder,
                                indexCount: Int,
                                indexBuffer: MTLBuffer) -> Bool {
        guard let pipeline = pipelineRGBMesh else { return false }
        guard let texture = makeBGRATexture(from: cvFrame) else { return false }
        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentTexture(texture, index: 0)
        encoder.drawIndexedPrimitives(type: .triangle, indexCount: indexCount, indexType: .uint16, indexBuffer: indexBuffer, indexBufferOffset: 0)
        return true
    }

    func renderI420Mesh(yuvFrame: IRFFAVYUVVideoFrame,
                                encoder: MTLRenderCommandEncoder,
                                indexCount: Int,
                                indexBuffer: MTLBuffer) -> Bool {
        guard let pipeline = pipelineI420Mesh else { return false }
        guard let textures = makeI420Textures(from: yuvFrame) else { return false }
        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentTexture(textures.y, index: 0)
        encoder.setFragmentTexture(textures.u, index: 1)
        encoder.setFragmentTexture(textures.v, index: 2)
        encoder.drawIndexedPrimitives(type: .triangle, indexCount: indexCount, indexType: .uint16, indexBuffer: indexBuffer, indexBufferOffset: 0)
        return true
    }

}
