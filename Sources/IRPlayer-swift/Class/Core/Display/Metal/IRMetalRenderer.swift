//
//  IRMetalRenderer.swift
//  IRPlayer-swift
//
//  Created by Codex on 2026/3/8.
//

import Foundation
import Metal
import CoreVideo
import simd
import QuartzCore

final class IRMetalRenderer {
    struct Fish2PanoParams {
        var fishwidth: Int32
        var fishheight: Int32
        var panowidth: Int32
        var panoheight: Int32
        var antialias: Int32
        var offsetX: Float
        var _padding: SIMD2<Float> = .zero
    }

    let device: MTLDevice
    let commandQueue: MTLCommandQueue
    var textureCache: CVMetalTextureCache?
    var pipelineNV12: MTLRenderPipelineState?
    var pipelineI420: MTLRenderPipelineState?
    var pipelineRGB: MTLRenderPipelineState?
    var pipelineNV12Mesh: MTLRenderPipelineState?
    var pipelineI420Mesh: MTLRenderPipelineState?
    var pipelineRGBMesh: MTLRenderPipelineState?
    var pipelineNV12Fish2Pano: MTLRenderPipelineState?
    var pipelineI420Fish2Pano: MTLRenderPipelineState?
    var pipelineRGBFish2Pano: MTLRenderPipelineState?
    var pipelineDistortion: MTLRenderPipelineState?
    var vertexBuffer: MTLBuffer?
    var vertexBufferLeft: MTLBuffer?
    var vertexBufferRight: MTLBuffer?
    var distortionOffscreenTexture: MTLTexture?
    var distortionOffscreenSize: CGSize = .zero
    private let vertexDescriptor: MTLVertexDescriptor = {
        let descriptor = MTLVertexDescriptor()
        descriptor.attributes[0].format = .float2
        descriptor.attributes[0].offset = 0
        descriptor.attributes[0].bufferIndex = 0
        descriptor.attributes[1].format = .float2
        descriptor.attributes[1].offset = MemoryLayout<SIMD2<Float>>.stride
        descriptor.attributes[1].bufferIndex = 0
        descriptor.layouts[0].stride = MemoryLayout<SIMD2<Float>>.stride * 2
        descriptor.layouts[0].stepFunction = .perVertex
        return descriptor
    }()

    private let vertexDescriptorDistortion: MTLVertexDescriptor = {
        let descriptor = MTLVertexDescriptor()
        descriptor.attributes[0].format = .float2
        descriptor.attributes[0].offset = MemoryLayout<IRMetalDistortionVertex>.offset(of: \.position) ?? 0
        descriptor.attributes[0].bufferIndex = 0
        descriptor.attributes[1].format = .float
        descriptor.attributes[1].offset = MemoryLayout<IRMetalDistortionVertex>.offset(of: \.vignette) ?? 0
        descriptor.attributes[1].bufferIndex = 0
        descriptor.attributes[2].format = .float2
        descriptor.attributes[2].offset = MemoryLayout<IRMetalDistortionVertex>.offset(of: \.redTexCoord) ?? 0
        descriptor.attributes[2].bufferIndex = 0
        descriptor.attributes[3].format = .float2
        descriptor.attributes[3].offset = MemoryLayout<IRMetalDistortionVertex>.offset(of: \.greenTexCoord) ?? 0
        descriptor.attributes[3].bufferIndex = 0
        descriptor.attributes[4].format = .float2
        descriptor.attributes[4].offset = MemoryLayout<IRMetalDistortionVertex>.offset(of: \.blueTexCoord) ?? 0
        descriptor.attributes[4].bufferIndex = 0
        descriptor.layouts[0].stride = MemoryLayout<IRMetalDistortionVertex>.stride
        descriptor.layouts[0].stepFunction = .perVertex
        return descriptor
    }()

    private let vertexDescriptor3D: MTLVertexDescriptor = {
        let descriptor = MTLVertexDescriptor()
        descriptor.attributes[0].format = .float3
        descriptor.attributes[0].offset = 0
        descriptor.attributes[0].bufferIndex = 0
        descriptor.attributes[1].format = .float2
        descriptor.attributes[1].offset = MemoryLayout<SIMD3<Float>>.stride
        descriptor.attributes[1].bufferIndex = 0
        descriptor.layouts[0].stride = MemoryLayout<IRMetalFisheyeMesh.Vertex>.stride
        descriptor.layouts[0].stepFunction = .perVertex
        return descriptor
    }()

    let pixelRendererNV12 = IRMetalPixelRendererNV12()
    let pixelRendererI420 = IRMetalPixelRendererI420()
    let pixelRendererRGB = IRMetalPixelRendererRGB()

    init?(device: MTLDevice) {
        self.device = device
        guard let queue = device.makeCommandQueue() else {
            return nil
        }
        self.commandQueue = queue
        if CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, device, nil, &textureCache) != kCVReturnSuccess {
            textureCache = nil
        }
        buildPipelines()
        buildVertexBuffer()
    }

    private func buildPipelines() {
        let library: MTLLibrary?
        #if SWIFT_PACKAGE
        library = (try? device.makeDefaultLibrary(bundle: .module)) ?? (try? device.makeDefaultLibrary())
        #else
        library = try? device.makeDefaultLibrary()
        #endif
        guard let library = library else {
            return
        }

        let vertexFunction = library.makeFunction(name: "irVertex")
        let vertexFunction3D = library.makeFunction(name: "irVertex3D")
        let fragmentNV12 = library.makeFunction(name: "irFragmentNV12")
        let fragmentI420 = library.makeFunction(name: "irFragmentI420")
        let fragmentRGB = library.makeFunction(name: "irFragmentRGB")
        let fragmentFish2PanoNV12 = library.makeFunction(name: "irFragmentFish2PanoNV12")
        let fragmentFish2PanoI420 = library.makeFunction(name: "irFragmentFish2PanoI420")
        let fragmentFish2PanoRGB = library.makeFunction(name: "irFragmentFish2PanoRGB")
        let vertexDistortion = library.makeFunction(name: "irDistortionVertex")
        let fragmentDistortion = library.makeFunction(name: "irFragmentDistortion")

        if let vertexFunction = vertexFunction, let fragmentNV12 = fragmentNV12 {
            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.vertexFunction = vertexFunction
            descriptor.fragmentFunction = fragmentNV12
            descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
            descriptor.vertexDescriptor = vertexDescriptor
//            pipelineNV12 = try? device.makeRenderPipelineState(descriptor: descriptor)
//            if pipelineNV12 == nil {
//                print("IRMetalRenderer: failed to create NV12 pipeline")
//            }
            do {
                pipelineNV12 = try device.makeRenderPipelineState(descriptor: descriptor)
            } catch {
                print("Metal Pipeline Error: \(error)")
                // 這裡通常會印出：Vertex shader output doesn't match fragment shader input
            }
        }

        if let vertexFunction = vertexFunction, let fragmentI420 = fragmentI420 {
            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.vertexFunction = vertexFunction
            descriptor.fragmentFunction = fragmentI420
            descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
            descriptor.vertexDescriptor = vertexDescriptor
            pipelineI420 = try? device.makeRenderPipelineState(descriptor: descriptor)
            if pipelineI420 == nil {
                print("IRMetalRenderer: failed to create I420 pipeline")
            }
        }

        if let vertexFunction = vertexFunction, let fragmentRGB = fragmentRGB {
            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.vertexFunction = vertexFunction
            descriptor.fragmentFunction = fragmentRGB
            descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
            descriptor.vertexDescriptor = vertexDescriptor
            pipelineRGB = try? device.makeRenderPipelineState(descriptor: descriptor)
            if pipelineRGB == nil {
                print("IRMetalRenderer: failed to create RGB pipeline")
            }
        }

        if let vertexFunction3D = vertexFunction3D, let fragmentNV12 = fragmentNV12 {
            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.vertexFunction = vertexFunction3D
            descriptor.fragmentFunction = fragmentNV12
            descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
            descriptor.vertexDescriptor = vertexDescriptor3D
            pipelineNV12Mesh = try? device.makeRenderPipelineState(descriptor: descriptor)
            if pipelineNV12Mesh == nil {
                print("IRMetalRenderer: failed to create NV12 mesh pipeline")
            }
        }

        if let vertexFunction3D = vertexFunction3D, let fragmentI420 = fragmentI420 {
            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.vertexFunction = vertexFunction3D
            descriptor.fragmentFunction = fragmentI420
            descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
            descriptor.vertexDescriptor = vertexDescriptor3D
            pipelineI420Mesh = try? device.makeRenderPipelineState(descriptor: descriptor)
            if pipelineI420Mesh == nil {
                print("IRMetalRenderer: failed to create I420 mesh pipeline")
            }
        }

        if let vertexFunction3D = vertexFunction3D, let fragmentRGB = fragmentRGB {
            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.vertexFunction = vertexFunction3D
            descriptor.fragmentFunction = fragmentRGB
            descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
            descriptor.vertexDescriptor = vertexDescriptor3D
            pipelineRGBMesh = try? device.makeRenderPipelineState(descriptor: descriptor)
            if pipelineRGBMesh == nil {
                print("IRMetalRenderer: failed to create RGB mesh pipeline")
            }
        }

        if let vertexFunction = vertexFunction, let fragmentFish2PanoNV12 = fragmentFish2PanoNV12 {
            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.vertexFunction = vertexFunction
            descriptor.fragmentFunction = fragmentFish2PanoNV12
            descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
            descriptor.vertexDescriptor = vertexDescriptor
            pipelineNV12Fish2Pano = try? device.makeRenderPipelineState(descriptor: descriptor)
            if pipelineNV12Fish2Pano == nil {
                print("IRMetalRenderer: failed to create NV12 fish2pano pipeline")
            }
        }

        if let vertexFunction = vertexFunction, let fragmentFish2PanoI420 = fragmentFish2PanoI420 {
            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.vertexFunction = vertexFunction
            descriptor.fragmentFunction = fragmentFish2PanoI420
            descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
            descriptor.vertexDescriptor = vertexDescriptor
            pipelineI420Fish2Pano = try? device.makeRenderPipelineState(descriptor: descriptor)
            if pipelineI420Fish2Pano == nil {
                print("IRMetalRenderer: failed to create I420 fish2pano pipeline")
            }
        }

        if let vertexFunction = vertexFunction, let fragmentFish2PanoRGB = fragmentFish2PanoRGB {
            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.vertexFunction = vertexFunction
            descriptor.fragmentFunction = fragmentFish2PanoRGB
            descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
            descriptor.vertexDescriptor = vertexDescriptor
            pipelineRGBFish2Pano = try? device.makeRenderPipelineState(descriptor: descriptor)
            if pipelineRGBFish2Pano == nil {
                print("IRMetalRenderer: failed to create RGB fish2pano pipeline")
            }
        }

        if let vertexDistortion = vertexDistortion, let fragmentDistortion = fragmentDistortion {
            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.vertexFunction = vertexDistortion
            descriptor.fragmentFunction = fragmentDistortion
            descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
            descriptor.vertexDescriptor = vertexDescriptorDistortion
            pipelineDistortion = try? device.makeRenderPipelineState(descriptor: descriptor)
            if pipelineDistortion == nil {
                print("IRMetalRenderer: failed to create distortion pipeline")
            }
        }
    }

    func buildVertexBuffer() {
        struct Vertex {
            let position: SIMD2<Float>
            let texCoord: SIMD2<Float>
        }

        let vertices: [Vertex] = [
            Vertex(position: SIMD2<Float>(-1.0, -1.0), texCoord: SIMD2<Float>(0.0, 1.0)),
            Vertex(position: SIMD2<Float>( 1.0, -1.0), texCoord: SIMD2<Float>(1.0, 1.0)),
            Vertex(position: SIMD2<Float>(-1.0,  1.0), texCoord: SIMD2<Float>(0.0, 0.0)),
            Vertex(position: SIMD2<Float>( 1.0,  1.0), texCoord: SIMD2<Float>(1.0, 0.0))
        ]

        vertexBuffer = device.makeBuffer(bytes: vertices, length: MemoryLayout<Vertex>.stride * vertices.count, options: .storageModeShared)

        let leftVertices: [Vertex] = [
            Vertex(position: SIMD2<Float>(-1.0, -1.0), texCoord: SIMD2<Float>(0.0, 1.0)),
            Vertex(position: SIMD2<Float>( 1.0, -1.0), texCoord: SIMD2<Float>(0.5, 1.0)),
            Vertex(position: SIMD2<Float>(-1.0,  1.0), texCoord: SIMD2<Float>(0.0, 0.0)),
            Vertex(position: SIMD2<Float>( 1.0,  1.0), texCoord: SIMD2<Float>(0.5, 0.0))
        ]
        vertexBufferLeft = device.makeBuffer(bytes: leftVertices, length: MemoryLayout<Vertex>.stride * leftVertices.count, options: .storageModeShared)

        let rightVertices: [Vertex] = [
            Vertex(position: SIMD2<Float>(-1.0, -1.0), texCoord: SIMD2<Float>(0.5, 1.0)),
            Vertex(position: SIMD2<Float>( 1.0, -1.0), texCoord: SIMD2<Float>(1.0, 1.0)),
            Vertex(position: SIMD2<Float>(-1.0,  1.0), texCoord: SIMD2<Float>(0.5, 0.0)),
            Vertex(position: SIMD2<Float>( 1.0,  1.0), texCoord: SIMD2<Float>(1.0, 0.0))
        ]
        vertexBufferRight = device.makeBuffer(bytes: rightVertices, length: MemoryLayout<Vertex>.stride * rightVertices.count, options: .storageModeShared)
    }

    func currentRenderPassDescriptor(drawable: CAMetalDrawable) -> MTLRenderPassDescriptor? {
        let descriptor = MTLRenderPassDescriptor()
        descriptor.colorAttachments[0].texture = drawable.texture
        descriptor.colorAttachments[0].loadAction = .clear
        descriptor.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 1)
        descriptor.colorAttachments[0].storeAction = .store
        return descriptor
    }


    func pixelRenderer(for frame: IRFFVideoFrame) -> IRMetalPixelRenderer? {
        if frame is IRFFCVYUVVideoFrame {
            return pixelRendererNV12
        }
        if frame is IRFFAVYUVVideoFrame {
            return pixelRendererI420
        }
        if frame is IRVideoFrameRGB {
            return pixelRendererRGB
        }
        return nil
    }
    func computeScale(contentMode: IRGLRenderContentMode, frameSize: CGSize, drawableSize: CGSize) -> CGSize {
        return Self.computeScale(contentMode: contentMode, frameSize: frameSize, drawableSize: drawableSize)
    }

    static func computeScale(contentMode: IRGLRenderContentMode, frameSize: CGSize, drawableSize: CGSize) -> CGSize {
        guard frameSize.width.isFinite,
              frameSize.height.isFinite,
              drawableSize.width.isFinite,
              drawableSize.height.isFinite,
              frameSize.width > 0,
              frameSize.height > 0,
              drawableSize.width > 0,
              drawableSize.height > 0 else {
            return CGSize(width: 1, height: 1)
        }

        let sx = drawableSize.width / frameSize.width
        let sy = drawableSize.height / frameSize.height

        switch contentMode {
        case .scaleAspectFit:
            let s = min(sx, sy)
            return CGSize(width: s / sx, height: s / sy)
        case .scaleAspectFill:
            let s = max(sx, sy)
            return CGSize(width: s / sx, height: s / sy)
        case .scaleToFill:
            return CGSize(width: 1, height: 1)
        @unknown default:
            return CGSize(width: 1, height: 1)
        }
    }
}

extension IRMetalRenderer: IRGLRenderInternal {}
