//
//  IRMetalRenderer+RenderPixelFormat.swift
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

    func renderNV12(
        cvFrame: IRFFCVYUVVideoFrame,
        encoder: MTLRenderCommandEncoder,
        resources: IRMetalCommandResources
    ) -> Bool {
        let pixelFormat = CVPixelBufferGetPixelFormatType(
            cvFrame.pixelBuffer
        )
        IRMetalRuntimeDebugOutput.write(
            "IRMetalRenderer: CVPixelBuffer format=\(pixelFormat)"
        )
        guard let generation = frameTextureGeneration(
            for: cvFrame,
            resources: resources
        ),
        case let .nv12(yTexture, uvTexture) =
            generation.textures else {
            return false
        }

        encoder.setRenderPipelineState(pipelineNV12)
        encoder.setFragmentTexture(yTexture, index: 0)
        encoder.setFragmentTexture(uvTexture, index: 1)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        return true
    }

    func renderBGRA(
        cvFrame: IRFFCVYUVVideoFrame,
        encoder: MTLRenderCommandEncoder,
        resources: IRMetalCommandResources
    ) -> Bool {
        guard let generation = frameTextureGeneration(
            for: cvFrame,
            resources: resources
        ),
        case let .bgra(texture) = generation.textures else {
            return false
        }
        encoder.setRenderPipelineState(pipelineRGB)
        encoder.setFragmentTexture(texture, index: 0)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        return true
    }

    func renderI420(
        yuvFrame: IRFFAVYUVVideoFrame,
        encoder: MTLRenderCommandEncoder,
        resources: IRMetalCommandResources
    ) -> Bool {
        guard let generation = frameTextureGeneration(
            for: yuvFrame,
            resources: resources
        ),
        case let .i420(y, u, v) = generation.textures else {
            return false
        }

        encoder.setRenderPipelineState(pipelineI420)
        encoder.setFragmentTexture(y, index: 0)
        encoder.setFragmentTexture(u, index: 1)
        encoder.setFragmentTexture(v, index: 2)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        return true
    }

    func renderRGB(
        rgbFrame: IRVideoFrameRGB,
        encoder: MTLRenderCommandEncoder,
        resources: IRMetalCommandResources
    ) -> Bool {
        guard let generation = frameTextureGeneration(
            for: rgbFrame,
            resources: resources
        ),
        case let .rgb(texture) = generation.textures else {
            return false
        }

        encoder.setRenderPipelineState(pipelineRGB)
        encoder.setFragmentTexture(texture, index: 0)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        return true
    }

    func makeI420Textures(from yuvFrame: IRFFAVYUVVideoFrame) -> (y: MTLTexture, u: MTLTexture, v: MTLTexture)? {
        guard let snapshot = yuvFrame.planeSnapshot() else {
            return nil
        }

        var textures: (
            y: MTLTexture,
            u: MTLTexture,
            v: MTLTexture
        )?
        let madeTextures = snapshot.withUnsafePlaneBytes {
            luma,
            chromaB,
            chromaR in
            guard let y = makeTexture(
                width: snapshot.width,
                height: snapshot.height,
                pixelFormat: .r8Unorm,
                bytes: luma
            ),
            let u = makeTexture(
                width: snapshot.chromaWidth,
                height: snapshot.chromaHeight,
                pixelFormat: .r8Unorm,
                bytes: chromaB
            ),
            let v = makeTexture(
                width: snapshot.chromaWidth,
                height: snapshot.chromaHeight,
                pixelFormat: .r8Unorm,
                bytes: chromaR
            ) else {
                return false
            }
            textures = (y, u, v)
            return true
        }
        return madeTextures ? textures : nil
    }

    func makeRGBTexture(from rgbFrame: IRVideoFrameRGB) -> MTLTexture? {
        let snapshot = rgbFrame.contentSnapshot()
        let pixelFormat: MTLPixelFormat
        switch snapshot.metalUploadFormat {
        case .rgba8:
            pixelFormat = .rgba8Unorm
        case .bgra8:
            pixelFormat = .bgra8Unorm
        }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: pixelFormat,
            width: snapshot.width,
            height: snapshot.height,
            mipmapped: false
        )
        descriptor.usage = .shaderRead
        guard let texture = device.makeTexture(
            descriptor: descriptor
        ) else {
            return nil
        }

        let uploaded = snapshot.withUnsafeMetalUploadBytes {
            rawBuffer -> Bool in
            guard let base = rawBuffer.baseAddress else {
                return false
            }
            texture.replace(
                region: MTLRegionMake2D(
                    0,
                    0,
                    snapshot.width,
                    snapshot.height
                ),
                mipmapLevel: 0,
                withBytes: base,
                bytesPerRow: snapshot.metalUploadBytesPerRow
            )
            return true
        }
        return uploaded ? texture : nil
    }

    func makeTexture(width: Int, height: Int, pixelFormat: MTLPixelFormat, bytes: UnsafeRawPointer) -> MTLTexture? {
        guard width > 0, height > 0 else { return nil }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: pixelFormat, width: width, height: height, mipmapped: false)
        descriptor.usage = .shaderRead
        guard let texture = device.makeTexture(descriptor: descriptor) else { return nil }
        let bytesPerRow = width
        texture.replace(region: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0, withBytes: bytes, bytesPerRow: bytesPerRow)
        return texture
    }

}
