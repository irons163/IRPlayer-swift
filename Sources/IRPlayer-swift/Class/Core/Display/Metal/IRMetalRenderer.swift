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

enum IRMetalRuntimeDebugOutput {
    #if IRMetalRuntimeDebugOutputEnable
    static let isEnabled = true
    #else
    static let isEnabled = false
    #endif

    static func write(_ message: @autoclosure () -> String) {
        guard isEnabled else { return }
        IRPlayerImp.Logger.libraryLogger.debug(message())
    }
}

final class IRMetalRenderer {
    struct QuadVertex: Equatable {
        let position: SIMD2<Float>
        let texCoord: SIMD2<Float>
    }

    enum QuadTextureRange: CaseIterable, Equatable {
        case full
        case left
        case right
    }

    enum MetalViewportOrientation {
        case topLeftFlipped
        case bottomLeft
    }

    struct Fish2PanoParams {
        var fishwidth: Int32
        var fishheight: Int32
        var panowidth: Int32
        var panoheight: Int32
        var antialias: Int32
        var offsetX: Float
        var _padding: SIMD2<Float> = .zero
    }

    static func fish2PanoInputsAreValid(params: Fish2PanoParams, texUVTextureCount: Int) -> Bool {
        guard params.fishwidth > 0,
              params.fishheight > 0,
              params.panowidth > 0,
              params.panoheight > 0,
              params.antialias > 0,
              params.offsetX.isFinite,
              texUVTextureCount > 0 else {
            return false
        }

        let antialias = Int(params.antialias)
        let (requiredTextureCount, overflow) =
            antialias.multipliedReportingOverflow(by: antialias)
        guard !overflow,
              requiredTextureCount > 0,
              requiredTextureCount <= 9 else {
            return false
        }
        return texUVTextureCount == requiredTextureCount
    }

    let device: MTLDevice
    let commandQueue: MTLCommandQueue
    let resources: IRMetalRendererResources
    let distortionTargets: IRMetalDistortionTargetSession

    let pixelRendererNV12 = IRMetalPixelRendererNV12()
    let pixelRendererI420 = IRMetalPixelRendererI420()
    let pixelRendererRGB = IRMetalPixelRendererRGB()

    init?(device: MTLDevice) {
        guard let commandQueue = device.makeCommandQueue() else {
            return nil
        }
        switch IRMetalRendererResources.make(device: device) {
        case let .success(resources):
            self.device = device
            self.commandQueue = commandQueue
            self.resources = resources
            self.distortionTargets =
                IRMetalDistortionTargetSession(device: device)
        case .failure:
            return nil
        }
    }

    private init(
        device: MTLDevice,
        commandQueue: MTLCommandQueue,
        resources: IRMetalRendererResources
    ) {
        self.device = device
        self.commandQueue = commandQueue
        self.resources = resources
        distortionTargets = IRMetalDistortionTargetSession(
            device: device
        )
    }

    static func make(
        device: MTLDevice,
        commandQueue: MTLCommandQueue,
        dependencies: IRMetalRendererResourceDependencies = .system
    ) -> Result<IRMetalRenderer, IRMetalRendererBuildFailure> {
        switch IRMetalRendererResources.make(
            device: device,
            dependencies: dependencies
        ) {
        case let .success(resources):
            return .success(
                IRMetalRenderer(
                    device: device,
                    commandQueue: commandQueue,
                    resources: resources
                )
            )
        case let .failure(failure):
            return .failure(failure)
        }
    }

    var textureCache: CVMetalTextureCache {
        resources.textureCache
    }

    var pipelineNV12: MTLRenderPipelineState {
        resources.pipelines.nv12
    }

    var pipelineI420: MTLRenderPipelineState {
        resources.pipelines.i420
    }

    var pipelineRGB: MTLRenderPipelineState {
        resources.pipelines.rgb
    }

    var pipelineNV12Mesh: MTLRenderPipelineState {
        resources.pipelines.nv12Mesh
    }

    var pipelineI420Mesh: MTLRenderPipelineState {
        resources.pipelines.i420Mesh
    }

    var pipelineRGBMesh: MTLRenderPipelineState {
        resources.pipelines.rgbMesh
    }

    var pipelineNV12Fish2Pano: MTLRenderPipelineState {
        resources.pipelines.nv12Fish2Pano
    }

    var pipelineI420Fish2Pano: MTLRenderPipelineState {
        resources.pipelines.i420Fish2Pano
    }

    var pipelineRGBFish2Pano: MTLRenderPipelineState {
        resources.pipelines.rgbFish2Pano
    }

    var pipelineDistortion: MTLRenderPipelineState {
        resources.pipelines.distortion
    }

    var vertexBuffer: MTLBuffer {
        resources.quadBuffers.full
    }

    var vertexBufferLeft: MTLBuffer {
        resources.quadBuffers.left
    }

    var vertexBufferRight: MTLBuffer {
        resources.quadBuffers.right
    }

    var distortionTargetDiagnostics:
        IRMetalDistortionTargetDiagnostics {
        distortionTargets.diagnostics
    }

    var distortionTargetSnapshot: MTLTexture? {
        distortionTargets.targetSnapshot
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
        let identity = CGSize(width: 1, height: 1)
        guard frameSize.width.isFinite,
              frameSize.height.isFinite,
              drawableSize.width.isFinite,
              drawableSize.height.isFinite,
              frameSize.width > 0,
              frameSize.height > 0,
              drawableSize.width > 0,
              drawableSize.height > 0 else {
            return identity
        }

        let sx = drawableSize.width / frameSize.width
        let sy = drawableSize.height / frameSize.height
        guard sx.isFinite, sy.isFinite, sx > 0, sy > 0 else {
            return identity
        }

        let scale: CGSize
        switch contentMode {
        case .scaleAspectFit:
            let value = min(sx, sy)
            scale = CGSize(
                width: value / sx,
                height: value / sy
            )
        case .scaleAspectFill:
            let value = max(sx, sy)
            scale = CGSize(
                width: value / sx,
                height: value / sy
            )
        case .scaleToFill:
            return identity
        @unknown default:
            return identity
        }

        guard scale.width.isFinite,
              scale.height.isFinite,
              scale.width > 0,
              scale.height > 0 else {
            return identity
        }
        return scale
    }

    static func quadVertices(textureRange: QuadTextureRange) -> [QuadVertex] {
        let minU: Float
        let maxU: Float
        switch textureRange {
        case .full:
            minU = 0
            maxU = 1
        case .left:
            minU = 0
            maxU = 0.5
        case .right:
            minU = 0.5
            maxU = 1
        }

        return [
            QuadVertex(
                position: SIMD2<Float>(-1, -1),
                texCoord: SIMD2<Float>(minU, 1)
            ),
            QuadVertex(
                position: SIMD2<Float>(1, -1),
                texCoord: SIMD2<Float>(maxU, 1)
            ),
            QuadVertex(
                position: SIMD2<Float>(-1, 1),
                texCoord: SIMD2<Float>(minU, 0)
            ),
            QuadVertex(
                position: SIMD2<Float>(1, 1),
                texCoord: SIMD2<Float>(maxU, 0)
            )
        ]
    }

    static func metalViewport(
        drawableSize: CGSize,
        viewport: CGRect,
        orientation: MetalViewportOrientation
    ) -> MTLViewport {
        let empty = MTLViewport(
            originX: 0,
            originY: 0,
            width: 0,
            height: 0,
            znear: 0,
            zfar: 1
        )
        guard drawableSize.width.isFinite,
              drawableSize.height.isFinite,
              viewport.origin.x.isFinite,
              viewport.origin.y.isFinite,
              viewport.size.width.isFinite,
              viewport.size.height.isFinite,
              drawableSize.width > 0,
              drawableSize.height > 0,
              viewport.size.width > 0,
              viewport.size.height > 0 else {
            return empty
        }

        let originY: CGFloat
        let height: CGFloat
        switch orientation {
        case .topLeftFlipped:
            originY =
                drawableSize.height - viewport.origin.y
            height = -viewport.size.height
        case .bottomLeft:
            originY =
                drawableSize.height -
                viewport.origin.y -
                viewport.size.height
            height = viewport.size.height
        }
        guard originY.isFinite, height.isFinite else {
            return empty
        }

        return MTLViewport(
            originX: Double(viewport.origin.x),
            originY: Double(originY),
            width: Double(viewport.size.width),
            height: Double(height),
            znear: 0,
            zfar: 1
        )
    }
}

extension IRMetalRenderer: IRGLRenderInternal {}
