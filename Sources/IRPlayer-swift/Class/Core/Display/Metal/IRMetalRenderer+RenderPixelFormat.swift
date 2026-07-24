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

    func renderNV12(cvFrame: IRFFCVYUVVideoFrame, encoder: MTLRenderCommandEncoder) -> Bool {
        guard let pipeline = pipelineNV12 else { return false }
        guard let pixelBuffer = Optional.some(cvFrame.pixelBuffer) else { return false }
        guard let textureCache = textureCache else { return false }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let format = CVPixelBufferGetPixelFormatType(pixelBuffer)
        IRMetalRuntimeDebugOutput.write("IRMetalRenderer: CVPixelBuffer format=\(format)")
        guard format == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange ||
              format == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange else {
            return false
        }

        var yTextureRef: CVMetalTexture?
        var uvTextureRef: CVMetalTexture?

        CVMetalTextureCacheCreateTextureFromImage(kCFAllocatorDefault, textureCache, pixelBuffer, nil, .r8Unorm, width, height, 0, &yTextureRef)
        CVMetalTextureCacheCreateTextureFromImage(kCFAllocatorDefault, textureCache, pixelBuffer, nil, .rg8Unorm, width / 2, height / 2, 1, &uvTextureRef)

        guard let yTextureRef = yTextureRef, let uvTextureRef = uvTextureRef else {
            IRMetalRuntimeDebugOutput.write("IRMetalRenderer: failed to create CVMetalTexture")
            return false
        }
        guard let yTexture = CVMetalTextureGetTexture(yTextureRef), let uvTexture = CVMetalTextureGetTexture(uvTextureRef) else { return false }

        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentTexture(yTexture, index: 0)
        encoder.setFragmentTexture(uvTexture, index: 1)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        return true
    }

    func renderBGRA(cvFrame: IRFFCVYUVVideoFrame, encoder: MTLRenderCommandEncoder) -> Bool {
        guard let pipeline = pipelineRGB else { return false }
        guard let texture = makeBGRATexture(from: cvFrame) else { return false }
        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentTexture(texture, index: 0)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        return true
    }

    func renderI420(yuvFrame: IRFFAVYUVVideoFrame, encoder: MTLRenderCommandEncoder) -> Bool {
        guard let pipeline = pipelineI420 else { return false }
        guard let textures = makeI420Textures(
            from: yuvFrame
        ) else {
            return false
        }

        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentTexture(textures.y, index: 0)
        encoder.setFragmentTexture(textures.u, index: 1)
        encoder.setFragmentTexture(textures.v, index: 2)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        return true
    }

    func renderRGB(rgbFrame: IRVideoFrameRGB, encoder: MTLRenderCommandEncoder) -> Bool {
        guard let pipeline = pipelineRGB else { return false }
        guard let texture = makeRGBTexture(from: rgbFrame) else { return false }

        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentTexture(texture, index: 0)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        return true
    }

    func makeNV12Textures(from cvFrame: IRFFCVYUVVideoFrame) -> (y: MTLTexture, uv: MTLTexture)? {
        guard let textureCache = textureCache else { return nil }
        let pixelBuffer = cvFrame.pixelBuffer
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let format = CVPixelBufferGetPixelFormatType(pixelBuffer)
        guard format == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange ||
              format == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange else { return nil }

        var yTextureRef: CVMetalTexture?
        var uvTextureRef: CVMetalTexture?
        CVMetalTextureCacheCreateTextureFromImage(kCFAllocatorDefault, textureCache, pixelBuffer, nil, .r8Unorm, width, height, 0, &yTextureRef)
        CVMetalTextureCacheCreateTextureFromImage(kCFAllocatorDefault, textureCache, pixelBuffer, nil, .rg8Unorm, width / 2, height / 2, 1, &uvTextureRef)

        guard let yRef = yTextureRef, let uvRef = uvTextureRef else { return nil }
        guard let y = CVMetalTextureGetTexture(yRef), let uv = CVMetalTextureGetTexture(uvRef) else { return nil }
        return (y: y, uv: uv)
    }

    func makeBGRATexture(from cvFrame: IRFFCVYUVVideoFrame) -> MTLTexture? {
        guard let textureCache = textureCache else { return nil }
        let pixelBuffer = cvFrame.pixelBuffer
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let format = CVPixelBufferGetPixelFormatType(pixelBuffer)
        guard format == kCVPixelFormatType_32BGRA else { return nil }

        var textureRef: CVMetalTexture?
        CVMetalTextureCacheCreateTextureFromImage(kCFAllocatorDefault, textureCache, pixelBuffer, nil, .bgra8Unorm, width, height, 0, &textureRef)
        guard let ref = textureRef else { return nil }
        return CVMetalTextureGetTexture(ref)
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
        let width = rgbFrame.width
        let height = rgbFrame.height
        guard let bytesPerRow = IRVideoFrameRGB.bytesPerRow(from: rgbFrame.linesize) else { return nil }
        guard let layout = Self.rgbTextureLayout(
            width: width,
            height: height,
            linesize: bytesPerRow,
            byteCount: rgbFrame.rgb.count
        ) else { return nil }

        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false)
        descriptor.usage = .shaderRead
        guard let texture = device.makeTexture(descriptor: descriptor) else { return nil }

        rgbFrame.rgb.withUnsafeBytes { rawBuffer in
            if let base = rawBuffer.baseAddress {
                texture.replace(region: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0, withBytes: base, bytesPerRow: layout.bytesPerRow)
            }
        }

        return texture
    }

    static func rgbTextureLayout(width: Int, height: Int, linesize: Int, byteCount: Int) -> (bytesPerRow: Int, totalByteCount: Int)? {
        IRMetalRendererPixelFormatPolicy.rgbTextureLayout(width: width,
                                                          height: height,
                                                          linesize: linesize,
                                                          byteCount: byteCount)
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
