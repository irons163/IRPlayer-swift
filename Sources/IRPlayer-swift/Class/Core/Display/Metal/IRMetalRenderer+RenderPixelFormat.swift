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
        print("IRMetalRenderer: CVPixelBuffer format=\(format)")
        guard format == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange ||
              format == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange else {
            return false
        }

        var yTextureRef: CVMetalTexture?
        var uvTextureRef: CVMetalTexture?

        CVMetalTextureCacheCreateTextureFromImage(kCFAllocatorDefault, textureCache, pixelBuffer, nil, .r8Unorm, width, height, 0, &yTextureRef)
        CVMetalTextureCacheCreateTextureFromImage(kCFAllocatorDefault, textureCache, pixelBuffer, nil, .rg8Unorm, width / 2, height / 2, 1, &uvTextureRef)

        guard let yTextureRef = yTextureRef, let uvTextureRef = uvTextureRef else {
            print("IRMetalRenderer: failed to create CVMetalTexture")
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
        guard let yPtr = yuvFrame.luma, let uPtr = yuvFrame.chromaB, let vPtr = yuvFrame.chromaR else { return false }

        let width = yuvFrame.width
        let height = yuvFrame.height
        guard width > 0, height > 0 else { return false }

        let yTexture = makeTexture(width: width, height: height, pixelFormat: .r8Unorm, bytes: yPtr)
        let uTexture = makeTexture(width: width / 2, height: height / 2, pixelFormat: .r8Unorm, bytes: uPtr)
        let vTexture = makeTexture(width: width / 2, height: height / 2, pixelFormat: .r8Unorm, bytes: vPtr)
        guard let yTexture, let uTexture, let vTexture else { return false }

        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentTexture(yTexture, index: 0)
        encoder.setFragmentTexture(uTexture, index: 1)
        encoder.setFragmentTexture(vTexture, index: 2)
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
        guard let yPtr = yuvFrame.luma, let uPtr = yuvFrame.chromaB, let vPtr = yuvFrame.chromaR else { return nil }
        let width = yuvFrame.width
        let height = yuvFrame.height
        guard width > 0, height > 0 else { return nil }

        guard let yTexture = makeTexture(width: width, height: height, pixelFormat: .r8Unorm, bytes: yPtr) else { return nil }
        guard let uTexture = makeTexture(width: width / 2, height: height / 2, pixelFormat: .r8Unorm, bytes: uPtr) else { return nil }
        guard let vTexture = makeTexture(width: width / 2, height: height / 2, pixelFormat: .r8Unorm, bytes: vPtr) else { return nil }
        return (y: yTexture, u: uTexture, v: vTexture)
    }

    func makeRGBTexture(from rgbFrame: IRVideoFrameRGB) -> MTLTexture? {
        let width = rgbFrame.width
        let height = rgbFrame.height
        guard let layout = Self.rgbTextureLayout(
            width: width,
            height: height,
            linesize: Int(rgbFrame.linesize),
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
        guard width > 0, height > 0, linesize > 0, byteCount >= 0 else { return nil }

        let (expectedBytesPerRow, rowOverflow) = width.multipliedReportingOverflow(by: 4)
        guard !rowOverflow, expectedBytesPerRow > 0, linesize == expectedBytesPerRow else { return nil }

        let (totalByteCount, totalOverflow) = expectedBytesPerRow.multipliedReportingOverflow(by: height)
        guard !totalOverflow, totalByteCount > 0, byteCount >= totalByteCount else { return nil }

        return (bytesPerRow: expectedBytesPerRow, totalByteCount: totalByteCount)
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
