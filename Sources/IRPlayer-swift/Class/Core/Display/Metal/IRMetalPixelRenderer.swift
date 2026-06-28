//
//  IRMetalPixelRenderer.swift
//  IRPlayer-swift
//
//  Created by Codex on 2026/3/13.
//

import Foundation
import Metal
import simd

protocol IRMetalPixelRenderer {
    func render2D(renderer: IRMetalRenderer,
                  frame: IRFFVideoFrame,
                  encoder: MTLRenderCommandEncoder) -> Bool

    func renderMesh(renderer: IRMetalRenderer,
                    frame: IRFFVideoFrame,
                    encoder: MTLRenderCommandEncoder,
                    indexCount: Int,
                    indexBuffer: MTLBuffer) -> Bool

    func renderFish2Pano(renderer: IRMetalRenderer,
                         frame: IRFFVideoFrame,
                         encoder: MTLRenderCommandEncoder,
                         params: IRMetalRenderer.Fish2PanoParams,
                         texUVTextures: [MTLTexture]) -> Bool
}

final class IRMetalPixelRendererNV12: IRMetalPixelRenderer {
    func render2D(renderer: IRMetalRenderer,
                  frame: IRFFVideoFrame,
                  encoder: MTLRenderCommandEncoder) -> Bool {
        guard let cvFrame = frame as? IRFFCVYUVVideoFrame else { return false }
        if renderer.renderNV12(cvFrame: cvFrame, encoder: encoder) {
            return true
        }
        return renderer.renderBGRA(cvFrame: cvFrame, encoder: encoder)
    }

    func renderMesh(renderer: IRMetalRenderer,
                    frame: IRFFVideoFrame,
                    encoder: MTLRenderCommandEncoder,
                    indexCount: Int,
                    indexBuffer: MTLBuffer) -> Bool {
        guard let cvFrame = frame as? IRFFCVYUVVideoFrame else { return false }
        if renderer.renderNV12Mesh(cvFrame: cvFrame, encoder: encoder, indexCount: indexCount, indexBuffer: indexBuffer) {
            return true
        }
        return renderer.renderBGRAMesh(cvFrame: cvFrame, encoder: encoder, indexCount: indexCount, indexBuffer: indexBuffer)
    }

    func renderFish2Pano(renderer: IRMetalRenderer,
                         frame: IRFFVideoFrame,
                         encoder: MTLRenderCommandEncoder,
                         params: IRMetalRenderer.Fish2PanoParams,
                         texUVTextures: [MTLTexture]) -> Bool {
        guard IRMetalRenderer.fish2PanoInputsAreValid(params: params, texUVTextureCount: texUVTextures.count) else { return false }
        guard let cvFrame = frame as? IRFFCVYUVVideoFrame else { return false }
        if let pipeline = renderer.pipelineNV12Fish2Pano, let textures = renderer.makeNV12Textures(from: cvFrame) {
            var fishParams = params
            encoder.setRenderPipelineState(pipeline)
            encoder.setFragmentBytes(&fishParams, length: MemoryLayout<IRMetalRenderer.Fish2PanoParams>.size, index: 0)
            encoder.setFragmentTexture(textures.y, index: 0)
            encoder.setFragmentTexture(textures.uv, index: 1)
            for i in 0..<9 {
                let textureIndex = i + 4
                if i < texUVTextures.count {
                    encoder.setFragmentTexture(texUVTextures[i], index: textureIndex)
                } else {
                    encoder.setFragmentTexture(nil, index: textureIndex)
                }
            }
            encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
            return true
        }

        if let pipeline = renderer.pipelineRGBFish2Pano, let texture = renderer.makeBGRATexture(from: cvFrame) {
            var fishParams = params
            encoder.setRenderPipelineState(pipeline)
            encoder.setFragmentBytes(&fishParams, length: MemoryLayout<IRMetalRenderer.Fish2PanoParams>.size, index: 0)
            encoder.setFragmentTexture(texture, index: 0)
            for i in 0..<9 {
                let textureIndex = i + 4
                if i < texUVTextures.count {
                    encoder.setFragmentTexture(texUVTextures[i], index: textureIndex)
                } else {
                    encoder.setFragmentTexture(nil, index: textureIndex)
                }
            }
            encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
            return true
        }
        return false
    }
}


final class IRMetalPixelRendererI420: IRMetalPixelRenderer {
    func render2D(renderer: IRMetalRenderer,
                  frame: IRFFVideoFrame,
                  encoder: MTLRenderCommandEncoder) -> Bool {
        guard let yuvFrame = frame as? IRFFAVYUVVideoFrame else { return false }
        return renderer.renderI420(yuvFrame: yuvFrame, encoder: encoder)
    }

    func renderMesh(renderer: IRMetalRenderer,
                    frame: IRFFVideoFrame,
                    encoder: MTLRenderCommandEncoder,
                    indexCount: Int,
                    indexBuffer: MTLBuffer) -> Bool {
        guard let yuvFrame = frame as? IRFFAVYUVVideoFrame else { return false }
        return renderer.renderI420Mesh(yuvFrame: yuvFrame, encoder: encoder, indexCount: indexCount, indexBuffer: indexBuffer)
    }

    func renderFish2Pano(renderer: IRMetalRenderer,
                         frame: IRFFVideoFrame,
                         encoder: MTLRenderCommandEncoder,
                         params: IRMetalRenderer.Fish2PanoParams,
                         texUVTextures: [MTLTexture]) -> Bool {
        guard IRMetalRenderer.fish2PanoInputsAreValid(params: params, texUVTextureCount: texUVTextures.count) else { return false }
        guard let yuvFrame = frame as? IRFFAVYUVVideoFrame else { return false }
        if let pipeline = renderer.pipelineI420Fish2Pano, let textures = renderer.makeI420Textures(from: yuvFrame) {
            var fishParams = params
            encoder.setRenderPipelineState(pipeline)
            encoder.setFragmentBytes(&fishParams, length: MemoryLayout<IRMetalRenderer.Fish2PanoParams>.size, index: 0)
            encoder.setFragmentTexture(textures.y, index: 0)
            encoder.setFragmentTexture(textures.u, index: 1)
            encoder.setFragmentTexture(textures.v, index: 2)
            for i in 0..<9 {
                let textureIndex = i + 4
                if i < texUVTextures.count {
                    encoder.setFragmentTexture(texUVTextures[i], index: textureIndex)
                } else {
                    encoder.setFragmentTexture(nil, index: textureIndex)
                }
            }
            encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
            return true
        }
        return false
    }
}

final class IRMetalPixelRendererRGB: IRMetalPixelRenderer {
    func render2D(renderer: IRMetalRenderer,
                  frame: IRFFVideoFrame,
                  encoder: MTLRenderCommandEncoder) -> Bool {
        guard let rgbFrame = frame as? IRVideoFrameRGB else { return false }
        return renderer.renderRGB(rgbFrame: rgbFrame, encoder: encoder)
    }

    func renderMesh(renderer: IRMetalRenderer,
                    frame: IRFFVideoFrame,
                    encoder: MTLRenderCommandEncoder,
                    indexCount: Int,
                    indexBuffer: MTLBuffer) -> Bool {
        // RGB mesh rendering is unsupported.
        return false
    }

    func renderFish2Pano(renderer: IRMetalRenderer,
                         frame: IRFFVideoFrame,
                         encoder: MTLRenderCommandEncoder,
                         params: IRMetalRenderer.Fish2PanoParams,
                         texUVTextures: [MTLTexture]) -> Bool {
        guard IRMetalRenderer.fish2PanoInputsAreValid(params: params, texUVTextureCount: texUVTextures.count) else { return false }
        guard let rgbFrame = frame as? IRVideoFrameRGB else { return false }
        if let pipeline = renderer.pipelineRGBFish2Pano, let texture = renderer.makeRGBTexture(from: rgbFrame) {
            var fishParams = params
            encoder.setRenderPipelineState(pipeline)
            encoder.setFragmentBytes(&fishParams, length: MemoryLayout<IRMetalRenderer.Fish2PanoParams>.size, index: 0)
            encoder.setFragmentTexture(texture, index: 0)
            for i in 0..<9 {
                let textureIndex = i + 4
                if i < texUVTextures.count {
                    encoder.setFragmentTexture(texUVTextures[i], index: textureIndex)
                } else {
                    encoder.setFragmentTexture(nil, index: textureIndex)
                }
            }
            encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
            return true
        }
        return false
    }
}
