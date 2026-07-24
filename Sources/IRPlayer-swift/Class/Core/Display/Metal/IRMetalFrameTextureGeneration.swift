//
//  IRMetalFrameTextureGeneration.swift
//  IRPlayer-swift
//
//  Created by Codex on 2026/7/24.
//

import CoreVideo
import Foundation
import Metal

enum IRMetalFrameTextureFormat: Equatable {
    case nv12
    case bgra
    case i420
    case rgb
}

struct IRMetalFrameTextureDiagnostics: Equatable {
    let format: IRMetalFrameTextureFormat
    let textureCount: Int
    let coreVideoTextureCount: Int
    let retainsSourcePixelBuffer: Bool
}

final class IRMetalFrameTextureGeneration {
    enum Textures {
        case nv12(y: MTLTexture, uv: MTLTexture)
        case bgra(MTLTexture)
        case i420(
            y: MTLTexture,
            u: MTLTexture,
            v: MTLTexture
        )
        case rgb(MTLTexture)
    }

    let textures: Textures

    private let coreVideoTextures: [CVMetalTexture]
    private let sourcePixelBuffer: CVPixelBuffer?

    init(
        textures: Textures,
        coreVideoTextures: [CVMetalTexture] = [],
        sourcePixelBuffer: CVPixelBuffer? = nil
    ) {
        self.textures = textures
        self.coreVideoTextures = coreVideoTextures
        self.sourcePixelBuffer = sourcePixelBuffer
    }

    var diagnostics: IRMetalFrameTextureDiagnostics {
        let format: IRMetalFrameTextureFormat
        let textureCount: Int
        switch textures {
        case .nv12:
            format = .nv12
            textureCount = 2
        case .bgra:
            format = .bgra
            textureCount = 1
        case .i420:
            format = .i420
            textureCount = 3
        case .rgb:
            format = .rgb
            textureCount = 1
        }
        return IRMetalFrameTextureDiagnostics(
            format: format,
            textureCount: textureCount,
            coreVideoTextureCount: coreVideoTextures.count,
            retainsSourcePixelBuffer: sourcePixelBuffer != nil
        )
    }
}

extension IRMetalRenderer {
    func frameTextureGeneration(
        for frame: IRFFVideoFrame,
        resources: IRMetalCommandResources
    ) -> IRMetalFrameTextureGeneration? {
        resources.frameTextureGeneration(for: frame) {
            makeFrameTextureGeneration(from: frame)
        }
    }

    func makeFrameTextureGeneration(
        from frame: IRFFVideoFrame
    ) -> IRMetalFrameTextureGeneration? {
        if let frame = frame as? IRFFCVYUVVideoFrame {
            let format = CVPixelBufferGetPixelFormatType(
                frame.pixelBuffer
            )
            switch format {
            case kCVPixelFormatType_420YpCbCr8BiPlanarFullRange,
                 kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange:
                return makeNV12TextureGeneration(from: frame)
            case kCVPixelFormatType_32BGRA:
                return makeBGRATextureGeneration(from: frame)
            default:
                return nil
            }
        }
        if let frame = frame as? IRFFAVYUVVideoFrame,
           let textures = makeI420Textures(from: frame) {
            return IRMetalFrameTextureGeneration(
                textures: .i420(
                    y: textures.y,
                    u: textures.u,
                    v: textures.v
                )
            )
        }
        if let frame = frame as? IRVideoFrameRGB,
           let texture = makeRGBTexture(from: frame) {
            return IRMetalFrameTextureGeneration(
                textures: .rgb(texture)
            )
        }
        return nil
    }

    func makeNV12TextureGeneration(
        from frame: IRFFCVYUVVideoFrame
    ) -> IRMetalFrameTextureGeneration? {
        let pixelBuffer = frame.pixelBuffer
        let format = CVPixelBufferGetPixelFormatType(
            pixelBuffer
        )
        guard format
                == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
                || format
                == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
              CVPixelBufferGetPlaneCount(pixelBuffer) == 2 else {
            return nil
        }

        let yWidth = CVPixelBufferGetWidthOfPlane(
            pixelBuffer,
            0
        )
        let yHeight = CVPixelBufferGetHeightOfPlane(
            pixelBuffer,
            0
        )
        let uvWidth = CVPixelBufferGetWidthOfPlane(
            pixelBuffer,
            1
        )
        let uvHeight = CVPixelBufferGetHeightOfPlane(
            pixelBuffer,
            1
        )
        guard yWidth > 0,
              yHeight > 0,
              uvWidth > 0,
              uvHeight > 0 else {
            return nil
        }

        var yReference: CVMetalTexture?
        var uvReference: CVMetalTexture?
        let yStatus =
            CVMetalTextureCacheCreateTextureFromImage(
                kCFAllocatorDefault,
                textureCache,
                pixelBuffer,
                nil,
                .r8Unorm,
                yWidth,
                yHeight,
                0,
                &yReference
            )
        let uvStatus =
            CVMetalTextureCacheCreateTextureFromImage(
                kCFAllocatorDefault,
                textureCache,
                pixelBuffer,
                nil,
                .rg8Unorm,
                uvWidth,
                uvHeight,
                1,
                &uvReference
            )

        guard yStatus == kCVReturnSuccess,
              uvStatus == kCVReturnSuccess,
              let yReference,
              let uvReference,
              let yTexture =
                CVMetalTextureGetTexture(yReference),
              let uvTexture =
                CVMetalTextureGetTexture(uvReference) else {
            return nil
        }
        return IRMetalFrameTextureGeneration(
            textures: .nv12(
                y: yTexture,
                uv: uvTexture
            ),
            coreVideoTextures: [
                yReference,
                uvReference
            ],
            sourcePixelBuffer: pixelBuffer
        )
    }

    func makeBGRATextureGeneration(
        from frame: IRFFCVYUVVideoFrame
    ) -> IRMetalFrameTextureGeneration? {
        let pixelBuffer = frame.pixelBuffer
        guard CVPixelBufferGetPixelFormatType(pixelBuffer)
                == kCVPixelFormatType_32BGRA else {
            return nil
        }
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        guard width > 0, height > 0 else {
            return nil
        }

        var reference: CVMetalTexture?
        let status =
            CVMetalTextureCacheCreateTextureFromImage(
                kCFAllocatorDefault,
                textureCache,
                pixelBuffer,
                nil,
                .bgra8Unorm,
                width,
                height,
                0,
                &reference
            )
        guard status == kCVReturnSuccess,
              let reference,
              let texture =
                CVMetalTextureGetTexture(reference) else {
            return nil
        }
        return IRMetalFrameTextureGeneration(
            textures: .bgra(texture),
            coreVideoTextures: [reference],
            sourcePixelBuffer: pixelBuffer
        )
    }
}
