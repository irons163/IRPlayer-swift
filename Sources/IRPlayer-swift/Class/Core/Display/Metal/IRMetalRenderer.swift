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
        IRMetalRendererScalePolicy.computeScale(contentMode: contentMode,
                                                frameSize: frameSize,
                                                drawableSize: drawableSize)
    }

    static func quadVertices(textureRange: QuadTextureRange) -> [QuadVertex] {
        IRMetalRendererGeometryPolicy.quadVertices(textureRange: textureRange)
    }

    static func metalViewport(drawableSize: CGSize,
                              viewport: CGRect,
                              orientation: MetalViewportOrientation) -> MTLViewport {
        IRMetalRendererGeometryPolicy.metalViewport(drawableSize: drawableSize,
                                                    viewport: viewport,
                                                    orientation: orientation)
    }
}

extension IRMetalRenderer: IRGLRenderInternal {}
