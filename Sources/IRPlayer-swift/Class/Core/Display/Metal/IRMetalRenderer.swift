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

    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private var textureCache: CVMetalTextureCache?
    private var pipelineNV12: MTLRenderPipelineState?
    private var pipelineI420: MTLRenderPipelineState?
    private var pipelineRGB: MTLRenderPipelineState?
    private var pipelineNV12Mesh: MTLRenderPipelineState?
    private var pipelineI420Mesh: MTLRenderPipelineState?
    private var pipelineRGBMesh: MTLRenderPipelineState?
    private var pipelineNV12Fish2Pano: MTLRenderPipelineState?
    private var pipelineI420Fish2Pano: MTLRenderPipelineState?
    private var pipelineRGBFish2Pano: MTLRenderPipelineState?
    private var pipelineDistortion: MTLRenderPipelineState?
    private var vertexBuffer: MTLBuffer?
    private var vertexBufferLeft: MTLBuffer?
    private var vertexBufferRight: MTLBuffer?
    private var distortionOffscreenTexture: MTLTexture?
    private var distortionOffscreenSize: CGSize = .zero
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

    func render(frame: IRFFVideoFrame,
                to drawable: CAMetalDrawable,
                contentMode: IRGLRenderContentMode,
                drawableSize: CGSize) -> Bool {
        guard let commandBuffer = commandQueue.makeCommandBuffer() else { return false }
        guard let renderPass = currentRenderPassDescriptor(drawable: drawable) else { return false }
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPass) else { return false }

        let scale = computeScale(contentMode: contentMode, frameSize: CGSize(width: frame.width, height: frame.height), drawableSize: drawableSize)
        var scaleVector = SIMD2<Float>(Float(scale.width), Float(scale.height))

        encoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
        encoder.setVertexBytes(&scaleVector, length: MemoryLayout<SIMD2<Float>>.size, index: 1)
        encoder.setViewport(MTLViewport(originX: 0,
                                        originY: Double(drawableSize.height),
                                        width: Double(drawableSize.width),
                                        height: -Double(drawableSize.height),
                                        znear: 0,
                                        zfar: 1))

        if let cvFrame = frame as? IRFFCVYUVVideoFrame {
            if renderNV12(cvFrame: cvFrame, encoder: encoder) || renderBGRA(cvFrame: cvFrame, encoder: encoder) {
                encoder.endEncoding()
                commandBuffer.present(drawable)
                commandBuffer.commit()
                return true
            }
        } else if let yuvFrame = frame as? IRFFAVYUVVideoFrame {
            if renderI420(yuvFrame: yuvFrame, encoder: encoder) {
                encoder.endEncoding()
                commandBuffer.present(drawable)
                commandBuffer.commit()
                return true
            }
        } else if let rgbFrame = frame as? IRVideoFrameRGB {
            if renderRGB(rgbFrame: rgbFrame, encoder: encoder) {
                encoder.endEncoding()
                commandBuffer.present(drawable)
                commandBuffer.commit()
                return true
            }
        }

        encoder.endEncoding()
        return false
    }

    func renderMulti(frame: IRFFVideoFrame,
                     to drawable: CAMetalDrawable,
                     drawableSize: CGSize,
                     viewports: [CGRect],
                     contentModes: [IRGLRenderContentMode]) -> Bool {
        guard !viewports.isEmpty, viewports.count == contentModes.count else { return false }
        guard let commandBuffer = commandQueue.makeCommandBuffer() else { return false }
        guard let renderPass = currentRenderPassDescriptor(drawable: drawable) else { return false }
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPass) else { return false }

        encoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)

        var didRender = false
        for (index, viewport) in viewports.enumerated() {
            guard viewport.width > 0, viewport.height > 0 else { continue }
            let originY = drawableSize.height - viewport.origin.y
            encoder.setViewport(MTLViewport(originX: Double(viewport.origin.x),
                                            originY: Double(originY),
                                            width: Double(viewport.size.width),
                                            height: -Double(viewport.size.height),
                                            znear: 0,
                                            zfar: 1))

            let targetSize = viewport.size
            let scale = computeScale(contentMode: contentModes[index],
                                     frameSize: CGSize(width: frame.width, height: frame.height),
                                     drawableSize: targetSize)
            var scaleVector = SIMD2<Float>(Float(scale.width), Float(scale.height))
            encoder.setVertexBytes(&scaleVector, length: MemoryLayout<SIMD2<Float>>.size, index: 1)

            if let cvFrame = frame as? IRFFCVYUVVideoFrame {
                didRender = renderNV12(cvFrame: cvFrame, encoder: encoder) || renderBGRA(cvFrame: cvFrame, encoder: encoder) || didRender
            } else if let yuvFrame = frame as? IRFFAVYUVVideoFrame {
                didRender = renderI420(yuvFrame: yuvFrame, encoder: encoder) || didRender
            } else if let rgbFrame = frame as? IRVideoFrameRGB {
                didRender = renderRGB(rgbFrame: rgbFrame, encoder: encoder) || didRender
            }
        }

        encoder.endEncoding()
        if didRender {
            commandBuffer.present(drawable)
            commandBuffer.commit()
        }
        return didRender
    }

    private func buildPipelines() {
        let library: MTLLibrary?
        #if SWIFT_PACKAGE
        library = (try? device.makeDefaultLibrary(bundle: .module)) ?? (try? device.makeDefaultLibrary())
        #else
        library = try? device.makeDefaultLibrary()
        #endif
        guard let library = library else {
            print("IRMetalRenderer: failed to load default Metal library")
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

    private func buildVertexBuffer() {
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

    private func renderNV12(cvFrame: IRFFCVYUVVideoFrame, encoder: MTLRenderCommandEncoder) -> Bool {
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

    private func renderBGRA(cvFrame: IRFFCVYUVVideoFrame, encoder: MTLRenderCommandEncoder) -> Bool {
        guard let pipeline = pipelineRGB else { return false }
        guard let texture = makeBGRATexture(from: cvFrame) else { return false }
        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentTexture(texture, index: 0)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        return true
    }

    private func renderI420(yuvFrame: IRFFAVYUVVideoFrame, encoder: MTLRenderCommandEncoder) -> Bool {
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

    private func renderRGB(rgbFrame: IRVideoFrameRGB, encoder: MTLRenderCommandEncoder) -> Bool {
        guard let pipeline = pipelineRGB else { return false }
        guard let texture = makeRGBTexture(from: rgbFrame) else { return false }

        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentTexture(texture, index: 0)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        return true
    }

    private func makeRGBTexture(from rgbFrame: IRVideoFrameRGB) -> MTLTexture? {
        let width = rgbFrame.width
        let height = rgbFrame.height
        guard width > 0, height > 0 else { return nil }
        let bytesPerRow = Int(rgbFrame.linesize)
        guard bytesPerRow == width * 4 else { return nil }
        guard rgbFrame.rgb.count >= bytesPerRow * height else { return nil }

        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false)
        descriptor.usage = .shaderRead
        guard let texture = device.makeTexture(descriptor: descriptor) else { return nil }

        rgbFrame.rgb.withUnsafeBytes { rawBuffer in
            if let base = rawBuffer.baseAddress {
                texture.replace(region: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0, withBytes: base, bytesPerRow: bytesPerRow)
            }
        }

        return texture
    }

    func renderFish2Pano(frame: IRFFVideoFrame,
                         params: Fish2PanoParams,
                         texUVTextures: [MTLTexture],
                         to drawable: CAMetalDrawable,
                         drawableSize: CGSize,
                         viewport: CGRect,
                         contentMode: IRGLRenderContentMode,
                         outputSize: CGSize,
                         zoomScale: Float) -> Bool {
        guard let commandBuffer = commandQueue.makeCommandBuffer() else { return false }
        guard let renderPass = currentRenderPassDescriptor(drawable: drawable) else { return false }
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPass) else { return false }

        let originY = drawableSize.height - viewport.origin.y
        encoder.setViewport(MTLViewport(originX: Double(viewport.origin.x),
                                        originY: Double(originY),
                                        width: Double(viewport.size.width),
                                        height: -Double(viewport.size.height),
                                        znear: 0,
                                        zfar: 1))

        let targetSize = viewport.size
        let scale = computeScale(contentMode: contentMode, frameSize: outputSize, drawableSize: targetSize)
        var scaleVector = SIMD2<Float>(Float(scale.width), Float(scale.height)) * zoomScale

        encoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
        encoder.setVertexBytes(&scaleVector, length: MemoryLayout<SIMD2<Float>>.size, index: 1)

        var fishParams = params
        encoder.setFragmentBytes(&fishParams, length: MemoryLayout<Fish2PanoParams>.size, index: 0)

        for i in 0..<9 {
            let textureIndex = i + 4
            if i < texUVTextures.count {
                encoder.setFragmentTexture(texUVTextures[i], index: textureIndex)
            } else {
                encoder.setFragmentTexture(nil, index: textureIndex)
            }
        }

        var didRender = false
        if let cvFrame = frame as? IRFFCVYUVVideoFrame {
            if let pipeline = pipelineNV12Fish2Pano, let textures = makeNV12Textures(from: cvFrame) {
                encoder.setRenderPipelineState(pipeline)
                encoder.setFragmentTexture(textures.y, index: 0)
                encoder.setFragmentTexture(textures.uv, index: 1)
                encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
                didRender = true
            }
        } else if let yuvFrame = frame as? IRFFAVYUVVideoFrame {
            if let pipeline = pipelineI420Fish2Pano, let textures = makeI420Textures(from: yuvFrame) {
                encoder.setRenderPipelineState(pipeline)
                encoder.setFragmentTexture(textures.y, index: 0)
                encoder.setFragmentTexture(textures.u, index: 1)
                encoder.setFragmentTexture(textures.v, index: 2)
                encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
                didRender = true
            }
        } else if let rgbFrame = frame as? IRVideoFrameRGB {
            if let pipeline = pipelineRGBFish2Pano, let texture = makeRGBTexture(from: rgbFrame) {
                encoder.setRenderPipelineState(pipeline)
                encoder.setFragmentTexture(texture, index: 0)
                encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
                didRender = true
            }
        }

        encoder.endEncoding()
        if didRender {
            commandBuffer.present(drawable)
            commandBuffer.commit()
        }
        return didRender
    }

    func renderFisheye(frame: IRFFVideoFrame,
                       mesh: IRMetalFisheyeMesh,
                       mvp: simd_float4x4,
                       textureMatrix: simd_float4x4,
                       to drawable: CAMetalDrawable,
                       drawableSize: CGSize,
                       viewport: CGRect) -> Bool {
        guard let commandBuffer = commandQueue.makeCommandBuffer() else { return false }
        guard let renderPass = currentRenderPassDescriptor(drawable: drawable) else { return false }
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPass) else { return false }

        let originY = drawableSize.height - viewport.origin.y - viewport.size.height
        encoder.setViewport(MTLViewport(originX: Double(viewport.origin.x),
                                        originY: Double(originY),
                                        width: Double(viewport.size.width),
                                        height: Double(viewport.size.height),
                                        znear: 0,
                                        zfar: 1))
        encoder.setVertexBuffer(mesh.vertexBuffer, offset: 0, index: 0)
        var mvpMatrix = mvp
        var texMatrix = textureMatrix
        encoder.setVertexBytes(&mvpMatrix, length: MemoryLayout<simd_float4x4>.size, index: 1)
        encoder.setVertexBytes(&texMatrix, length: MemoryLayout<simd_float4x4>.size, index: 2)

        var didRender = false
        if let cvFrame = frame as? IRFFCVYUVVideoFrame {
            didRender = renderNV12Mesh(cvFrame: cvFrame, encoder: encoder, indexCount: mesh.indexCount, indexBuffer: mesh.indexBuffer)
                || renderBGRAMesh(cvFrame: cvFrame, encoder: encoder, indexCount: mesh.indexCount, indexBuffer: mesh.indexBuffer)
        } else if let yuvFrame = frame as? IRFFAVYUVVideoFrame {
            didRender = renderI420Mesh(yuvFrame: yuvFrame, encoder: encoder, indexCount: mesh.indexCount, indexBuffer: mesh.indexBuffer)
        }

        encoder.endEncoding()
        if didRender {
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
        guard !viewports.isEmpty, viewports.count == mvpList.count else { return false }
        guard let commandBuffer = commandQueue.makeCommandBuffer() else { return false }
        guard let renderPass = currentRenderPassDescriptor(drawable: drawable) else { return false }
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPass) else { return false }

        encoder.setVertexBuffer(mesh.vertexBuffer, offset: 0, index: 0)
        var texMatrix = textureMatrix
        encoder.setVertexBytes(&texMatrix, length: MemoryLayout<simd_float4x4>.size, index: 2)

        var didRender = false

        if let cvFrame = frame as? IRFFCVYUVVideoFrame {
            if let pipeline = pipelineNV12Mesh, let textures = makeNV12Textures(from: cvFrame) {
                encoder.setRenderPipelineState(pipeline)
                encoder.setFragmentTexture(textures.y, index: 0)
                encoder.setFragmentTexture(textures.uv, index: 1)
            } else if let pipeline = pipelineRGBMesh, let texture = makeBGRATexture(from: cvFrame) {
                encoder.setRenderPipelineState(pipeline)
                encoder.setFragmentTexture(texture, index: 0)
            } else {
                encoder.endEncoding()
                return false
            }

            for (index, viewport) in viewports.enumerated() {
                let originY = drawableSize.height - viewport.origin.y - viewport.size.height
                encoder.setViewport(MTLViewport(originX: Double(viewport.origin.x),
                                                originY: Double(originY),
                                                width: Double(viewport.size.width),
                                                height: Double(viewport.size.height),
                                                znear: 0,
                                                zfar: 1))
                var mvpMatrix = mvpList[index]
                encoder.setVertexBytes(&mvpMatrix, length: MemoryLayout<simd_float4x4>.size, index: 1)
                encoder.drawIndexedPrimitives(type: .triangle,
                                              indexCount: mesh.indexCount,
                                              indexType: .uint16,
                                              indexBuffer: mesh.indexBuffer,
                                              indexBufferOffset: 0)
            }
            didRender = true
        } else if let yuvFrame = frame as? IRFFAVYUVVideoFrame {
            guard let pipeline = pipelineI420Mesh, let textures = makeI420Textures(from: yuvFrame) else {
                encoder.endEncoding()
                return false
            }
            encoder.setRenderPipelineState(pipeline)
            encoder.setFragmentTexture(textures.y, index: 0)
            encoder.setFragmentTexture(textures.u, index: 1)
            encoder.setFragmentTexture(textures.v, index: 2)

            for (index, viewport) in viewports.enumerated() {
                let originY = drawableSize.height - viewport.origin.y - viewport.size.height
                encoder.setViewport(MTLViewport(originX: Double(viewport.origin.x),
                                                originY: Double(originY),
                                                width: Double(viewport.size.width),
                                                height: Double(viewport.size.height),
                                                znear: 0,
                                                zfar: 1))
                var mvpMatrix = mvpList[index]
                encoder.setVertexBytes(&mvpMatrix, length: MemoryLayout<simd_float4x4>.size, index: 1)
                encoder.drawIndexedPrimitives(type: .triangle,
                                              indexCount: mesh.indexCount,
                                              indexType: .uint16,
                                              indexBuffer: mesh.indexBuffer,
                                              indexBufferOffset: 0)
            }
            didRender = true
        }

        encoder.endEncoding()
        if didRender {
            commandBuffer.present(drawable)
            commandBuffer.commit()
        }
        return didRender
    }

    func renderDistortion(frame: IRFFVideoFrame,
                          leftMesh: IRMetalDistortionMesh,
                          rightMesh: IRMetalDistortionMesh,
                          to drawable: CAMetalDrawable,
                          drawableSize: CGSize,
                          contentMode: IRGLRenderContentMode) -> Bool {
        guard let commandBuffer = commandQueue.makeCommandBuffer() else { return false }
        guard let offscreen = makeDistortionOffscreenTexture(size: drawableSize) else { return false }

        let offscreenPass = MTLRenderPassDescriptor()
        offscreenPass.colorAttachments[0].texture = offscreen
        offscreenPass.colorAttachments[0].loadAction = .clear
        offscreenPass.colorAttachments[0].storeAction = .store
        offscreenPass.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 1)

        guard let offscreenEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: offscreenPass) else { return false }
        offscreenEncoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)

        let halfWidth = drawableSize.width / 2.0
        let halfSize = CGSize(width: halfWidth, height: drawableSize.height)

        func renderHalf(originX: Double, isLeft: Bool) -> Bool {
            // Distortion expects the offscreen texture to fill each eye half.
            var scaleVector = SIMD2<Float>(1.0, 1.0)
            offscreenEncoder.setVertexBytes(&scaleVector, length: MemoryLayout<SIMD2<Float>>.size, index: 1)
            if let buffer = isLeft ? vertexBufferLeft : vertexBufferRight {
                offscreenEncoder.setVertexBuffer(buffer, offset: 0, index: 0)
            } else {
                offscreenEncoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
            }
            offscreenEncoder.setViewport(MTLViewport(originX: originX,
                                                     originY: 0,
                                                     width: Double(halfWidth),
                                                     height: Double(drawableSize.height),
                                                     znear: 0,
                                                     zfar: 1))

            if let cvFrame = frame as? IRFFCVYUVVideoFrame {
                return renderNV12(cvFrame: cvFrame, encoder: offscreenEncoder)
                    || renderBGRA(cvFrame: cvFrame, encoder: offscreenEncoder)
            } else if let yuvFrame = frame as? IRFFAVYUVVideoFrame {
                return renderI420(yuvFrame: yuvFrame, encoder: offscreenEncoder)
            } else if let rgbFrame = frame as? IRVideoFrameRGB {
                return renderRGB(rgbFrame: rgbFrame, encoder: offscreenEncoder)
            }
            return false
        }

        let leftRendered = renderHalf(originX: 0, isLeft: true)
        let rightRendered = renderHalf(originX: Double(halfWidth), isLeft: false)
        offscreenEncoder.endEncoding()

        guard leftRendered || rightRendered else { return false }
        guard let renderPass = currentRenderPassDescriptor(drawable: drawable) else { return false }
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPass) else { return false }
        guard let pipelineDistortion = pipelineDistortion else { return false }

        encoder.setRenderPipelineState(pipelineDistortion)
        encoder.setFragmentTexture(offscreen, index: 0)
        encoder.setViewport(MTLViewport(originX: 0,
                                        originY: 0,
                                        width: Double(drawableSize.width),
                                        height: Double(drawableSize.height),
                                        znear: 0,
                                        zfar: 1))

        let scissorHeight = max(Int(drawableSize.height), 0)
        let leftWidth = max(Int(halfWidth), 0)
        let rightWidth = max(Int(drawableSize.width) - leftWidth, 0)

        encoder.setScissorRect(MTLScissorRect(x: 0, y: 0, width: leftWidth, height: scissorHeight))
        encoder.setVertexBuffer(leftMesh.vertexBuffer, offset: 0, index: 0)
        encoder.drawIndexedPrimitives(type: .triangleStrip,
                                      indexCount: leftMesh.indexCount,
                                      indexType: .uint16,
                                      indexBuffer: leftMesh.indexBuffer,
                                      indexBufferOffset: 0)

        encoder.setScissorRect(MTLScissorRect(x: leftWidth, y: 0, width: rightWidth, height: scissorHeight))
        encoder.setVertexBuffer(rightMesh.vertexBuffer, offset: 0, index: 0)
        encoder.drawIndexedPrimitives(type: .triangleStrip,
                                      indexCount: rightMesh.indexCount,
                                      indexType: .uint16,
                                      indexBuffer: rightMesh.indexBuffer,
                                      indexBufferOffset: 0)

        encoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
        return true
    }

    private func renderNV12Mesh(cvFrame: IRFFCVYUVVideoFrame,
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

    private func renderBGRAMesh(cvFrame: IRFFCVYUVVideoFrame,
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

    private func renderI420Mesh(yuvFrame: IRFFAVYUVVideoFrame,
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

    private func makeNV12Textures(from cvFrame: IRFFCVYUVVideoFrame) -> (y: MTLTexture, uv: MTLTexture)? {
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

    private func makeBGRATexture(from cvFrame: IRFFCVYUVVideoFrame) -> MTLTexture? {
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

    private func makeI420Textures(from yuvFrame: IRFFAVYUVVideoFrame) -> (y: MTLTexture, u: MTLTexture, v: MTLTexture)? {
        guard let yPtr = yuvFrame.luma, let uPtr = yuvFrame.chromaB, let vPtr = yuvFrame.chromaR else { return nil }
        let width = yuvFrame.width
        let height = yuvFrame.height
        guard width > 0, height > 0 else { return nil }

        guard let yTexture = makeTexture(width: width, height: height, pixelFormat: .r8Unorm, bytes: yPtr) else { return nil }
        guard let uTexture = makeTexture(width: width / 2, height: height / 2, pixelFormat: .r8Unorm, bytes: uPtr) else { return nil }
        guard let vTexture = makeTexture(width: width / 2, height: height / 2, pixelFormat: .r8Unorm, bytes: vPtr) else { return nil }
        return (y: yTexture, u: uTexture, v: vTexture)
    }


    private func makeTexture(width: Int, height: Int, pixelFormat: MTLPixelFormat, bytes: UnsafeRawPointer) -> MTLTexture? {
        guard width > 0, height > 0 else { return nil }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: pixelFormat, width: width, height: height, mipmapped: false)
        descriptor.usage = .shaderRead
        guard let texture = device.makeTexture(descriptor: descriptor) else { return nil }
        let bytesPerRow = width
        texture.replace(region: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0, withBytes: bytes, bytesPerRow: bytesPerRow)
        return texture
    }

    private func makeDistortionOffscreenTexture(size: CGSize) -> MTLTexture? {
        guard size.width > 0, size.height > 0 else { return nil }
        if let texture = distortionOffscreenTexture,
           distortionOffscreenSize == size {
            return texture
        }
        let width = Int(size.width)
        let height = Int(size.height)
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false)
        descriptor.usage = [.renderTarget, .shaderRead]
        guard let texture = device.makeTexture(descriptor: descriptor) else { return nil }
        distortionOffscreenTexture = texture
        distortionOffscreenSize = size
        return texture
    }

    private func currentRenderPassDescriptor(drawable: CAMetalDrawable) -> MTLRenderPassDescriptor? {
        let descriptor = MTLRenderPassDescriptor()
        descriptor.colorAttachments[0].texture = drawable.texture
        descriptor.colorAttachments[0].loadAction = .clear
        descriptor.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 1)
        descriptor.colorAttachments[0].storeAction = .store
        return descriptor
    }

    func renderClear(to drawable: CAMetalDrawable) {
        guard let commandBuffer = commandQueue.makeCommandBuffer() else { return }
        guard let renderPass = currentRenderPassDescriptor(drawable: drawable) else { return }
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPass) else { return }
        encoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    private func computeScale(contentMode: IRGLRenderContentMode, frameSize: CGSize, drawableSize: CGSize) -> CGSize {
        guard frameSize.width > 0, frameSize.height > 0, drawableSize.width > 0, drawableSize.height > 0 else {
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
