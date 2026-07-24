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
                  encoder: MTLRenderCommandEncoder,
                  resources: IRMetalCommandResources) -> Bool

    func renderMesh(renderer: IRMetalRenderer,
                    frame: IRFFVideoFrame,
                    encoder: MTLRenderCommandEncoder,
                    indexCount: Int,
                    indexBuffer: MTLBuffer,
                    resources: IRMetalCommandResources) -> Bool

    func renderFish2Pano(renderer: IRMetalRenderer,
                         frame: IRFFVideoFrame,
                         encoder: MTLRenderCommandEncoder,
                         params: IRMetalRenderer.Fish2PanoParams,
                         texUVTextures: [MTLTexture],
                         resources: IRMetalCommandResources) -> Bool
}

final class IRMetalPixelRendererNV12: IRMetalPixelRenderer {
    func render2D(renderer: IRMetalRenderer,
                  frame: IRFFVideoFrame,
                  encoder: MTLRenderCommandEncoder,
                  resources: IRMetalCommandResources) -> Bool {
        guard let cvFrame = frame as? IRFFCVYUVVideoFrame else { return false }
        if renderer.renderNV12(
            cvFrame: cvFrame,
            encoder: encoder,
            resources: resources
        ) {
            return true
        }
        return renderer.renderBGRA(
            cvFrame: cvFrame,
            encoder: encoder,
            resources: resources
        )
    }

    func renderMesh(renderer: IRMetalRenderer,
                    frame: IRFFVideoFrame,
                    encoder: MTLRenderCommandEncoder,
                    indexCount: Int,
                    indexBuffer: MTLBuffer,
                    resources: IRMetalCommandResources) -> Bool {
        guard let cvFrame = frame as? IRFFCVYUVVideoFrame else { return false }
        if renderer.renderNV12Mesh(
            cvFrame: cvFrame,
            encoder: encoder,
            indexCount: indexCount,
            indexBuffer: indexBuffer,
            resources: resources
        ) {
            return true
        }
        return renderer.renderBGRAMesh(
            cvFrame: cvFrame,
            encoder: encoder,
            indexCount: indexCount,
            indexBuffer: indexBuffer,
            resources: resources
        )
    }

    func renderFish2Pano(renderer: IRMetalRenderer,
                         frame: IRFFVideoFrame,
                         encoder: MTLRenderCommandEncoder,
                         params: IRMetalRenderer.Fish2PanoParams,
                         texUVTextures: [MTLTexture],
                         resources: IRMetalCommandResources) -> Bool {
        guard IRMetalRenderer.fish2PanoInputsAreValid(params: params, texUVTextureCount: texUVTextures.count) else { return false }
        guard let cvFrame = frame as? IRFFCVYUVVideoFrame else { return false }
        guard let generation = renderer.frameTextureGeneration(
            for: cvFrame,
            resources: resources
        ) else {
            return false
        }

        if let pipeline = renderer.pipelineNV12Fish2Pano,
           case let .nv12(y, uv) = generation.textures {
            var fishParams = params
            encoder.setRenderPipelineState(pipeline)
            encoder.setFragmentBytes(&fishParams, length: MemoryLayout<IRMetalRenderer.Fish2PanoParams>.size, index: 0)
            encoder.setFragmentTexture(y, index: 0)
            encoder.setFragmentTexture(uv, index: 1)
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

        if let pipeline = renderer.pipelineRGBFish2Pano,
           case let .bgra(texture) = generation.textures {
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
                  encoder: MTLRenderCommandEncoder,
                  resources: IRMetalCommandResources) -> Bool {
        guard let yuvFrame = frame as? IRFFAVYUVVideoFrame else { return false }
        return renderer.renderI420(
            yuvFrame: yuvFrame,
            encoder: encoder,
            resources: resources
        )
    }

    func renderMesh(renderer: IRMetalRenderer,
                    frame: IRFFVideoFrame,
                    encoder: MTLRenderCommandEncoder,
                    indexCount: Int,
                    indexBuffer: MTLBuffer,
                    resources: IRMetalCommandResources) -> Bool {
        guard let yuvFrame = frame as? IRFFAVYUVVideoFrame else { return false }
        return renderer.renderI420Mesh(
            yuvFrame: yuvFrame,
            encoder: encoder,
            indexCount: indexCount,
            indexBuffer: indexBuffer,
            resources: resources
        )
    }

    func renderFish2Pano(renderer: IRMetalRenderer,
                         frame: IRFFVideoFrame,
                         encoder: MTLRenderCommandEncoder,
                         params: IRMetalRenderer.Fish2PanoParams,
                         texUVTextures: [MTLTexture],
                         resources: IRMetalCommandResources) -> Bool {
        guard IRMetalRenderer.fish2PanoInputsAreValid(params: params, texUVTextureCount: texUVTextures.count) else { return false }
        guard let yuvFrame = frame as? IRFFAVYUVVideoFrame else { return false }
        if let pipeline = renderer.pipelineI420Fish2Pano,
           let generation = renderer.frameTextureGeneration(
               for: yuvFrame,
               resources: resources
           ),
           case let .i420(y, u, v) = generation.textures {
            var fishParams = params
            encoder.setRenderPipelineState(pipeline)
            encoder.setFragmentBytes(&fishParams, length: MemoryLayout<IRMetalRenderer.Fish2PanoParams>.size, index: 0)
            encoder.setFragmentTexture(y, index: 0)
            encoder.setFragmentTexture(u, index: 1)
            encoder.setFragmentTexture(v, index: 2)
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
                  encoder: MTLRenderCommandEncoder,
                  resources: IRMetalCommandResources) -> Bool {
        guard let rgbFrame = frame as? IRVideoFrameRGB else { return false }
        return renderer.renderRGB(
            rgbFrame: rgbFrame,
            encoder: encoder,
            resources: resources
        )
    }

    func renderMesh(renderer: IRMetalRenderer,
                    frame: IRFFVideoFrame,
                    encoder: MTLRenderCommandEncoder,
                    indexCount: Int,
                    indexBuffer: MTLBuffer,
                    resources: IRMetalCommandResources) -> Bool {
        // RGB mesh rendering is unsupported.
        return false
    }

    func renderFish2Pano(renderer: IRMetalRenderer,
                         frame: IRFFVideoFrame,
                         encoder: MTLRenderCommandEncoder,
                         params: IRMetalRenderer.Fish2PanoParams,
                         texUVTextures: [MTLTexture],
                         resources: IRMetalCommandResources) -> Bool {
        guard IRMetalRenderer.fish2PanoInputsAreValid(params: params, texUVTextureCount: texUVTextures.count) else { return false }
        guard let rgbFrame = frame as? IRVideoFrameRGB else { return false }
        if let pipeline = renderer.pipelineRGBFish2Pano,
           let generation = renderer.frameTextureGeneration(
               for: rgbFrame,
               resources: resources
           ),
           case let .rgb(texture) = generation.textures {
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
