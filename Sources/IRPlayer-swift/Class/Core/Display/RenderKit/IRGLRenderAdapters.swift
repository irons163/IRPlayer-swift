//
//  IRGLRenderAdapters.swift
//  IRPlayer-swift
//
//  Created by Codex on 2026/3/14.
//

import Foundation
import Metal
import QuartzCore
import simd

private final class IRGLRenderAdapter: IRGLRenderInternal {
    private let renderer: IRMetalRenderer?

    init() {
        if let device = MTLCreateSystemDefaultDevice() {
            self.renderer = IRMetalRenderer(device: device)
        } else {
            self.renderer = nil
        }
    }

    func render(frame: IRFFVideoFrame,
                to drawable: CAMetalDrawable,
                contentMode: IRGLRenderContentMode,
                drawableSize: CGSize,
                zoomScale: Float,
                translation: SIMD2<Float>) -> Bool {
        renderer?.render(frame: frame, to: drawable, contentMode: contentMode, drawableSize: drawableSize, zoomScale: zoomScale, translation: translation) ?? false
    }

    func renderMulti(frame: IRFFVideoFrame,
                     to drawable: CAMetalDrawable,
                     drawableSize: CGSize,
                     viewports: [CGRect],
                     contentModes: [IRGLRenderContentMode],
                     zoomScales: [Float],
                     translations: [SIMD2<Float>]) -> Bool {
        renderer?.renderMulti(frame: frame,
                              to: drawable,
                              drawableSize: drawableSize,
                              viewports: viewports,
                              contentModes: contentModes,
                              zoomScales: zoomScales,
                              translations: translations) ?? false
    }

    func renderClear(to drawable: CAMetalDrawable) {
        renderer?.renderClear(to: drawable)
    }

    func renderFish2Pano(frame: IRFFVideoFrame,
                         params: IRMetalRenderer.Fish2PanoParams,
                         texUVTextures: [MTLTexture],
                         to drawable: CAMetalDrawable,
                         drawableSize: CGSize,
                         viewport: CGRect,
                         contentMode: IRGLRenderContentMode,
                         outputSize: CGSize,
                         zoomScale: Float,
                         translation: SIMD2<Float>) -> Bool {
        renderer?.renderFish2Pano(frame: frame,
                                 params: params,
                                 texUVTextures: texUVTextures,
                                 to: drawable,
                                 drawableSize: drawableSize,
                                 viewport: viewport,
                                 contentMode: contentMode,
                                 outputSize: outputSize,
                                  zoomScale: zoomScale,
                                  translation: translation) ?? false
    }

    func renderDistortion(frame: IRFFVideoFrame,
                          leftMesh: IRMetalDistortionMesh,
                          rightMesh: IRMetalDistortionMesh,
                          to drawable: CAMetalDrawable,
                          drawableSize: CGSize,
                          contentMode: IRGLRenderContentMode) -> Bool {
        renderer?.renderDistortion(frame: frame,
                                 leftMesh: leftMesh,
                                 rightMesh: rightMesh,
                                 to: drawable,
                                 drawableSize: drawableSize,
                                 contentMode: contentMode) ?? false
    }

    func renderFisheye(frame: IRFFVideoFrame,
                       mesh: IRMetalFisheyeMesh,
                       mvp: simd_float4x4,
                       textureMatrix: simd_float4x4,
                       to drawable: CAMetalDrawable,
                       drawableSize: CGSize,
                       viewport: CGRect) -> Bool {
        renderer?.renderFisheye(frame: frame,
                             mesh: mesh,
                             mvp: mvp,
                             textureMatrix: textureMatrix,
                             to: drawable,
                             drawableSize: drawableSize,
                             viewport: viewport) ?? false
    }

    func renderFisheyeMulti(frame: IRFFVideoFrame,
                            mesh: IRMetalFisheyeMesh,
                            mvpList: [simd_float4x4],
                            textureMatrix: simd_float4x4,
                            to drawable: CAMetalDrawable,
                            drawableSize: CGSize,
                            viewports: [CGRect]) -> Bool {
        renderer?.renderFisheyeMulti(frame: frame,
                                   mesh: mesh,
                                   mvpList: mvpList,
                                   textureMatrix: textureMatrix,
                                   to: drawable,
                                   drawableSize: drawableSize,
                                   viewports: viewports) ?? false
    }
}

public final class IRGLRenderNV12: IRGLRender {
    private let adapter = IRGLRenderAdapter()

    public init() {}
}

extension IRGLRenderNV12: IRGLRenderInternal {
    func render(frame: IRFFVideoFrame,
                to drawable: CAMetalDrawable,
                contentMode: IRGLRenderContentMode,
                drawableSize: CGSize,
                zoomScale: Float,
                translation: SIMD2<Float>) -> Bool {
        adapter.render(frame: frame, to: drawable, contentMode: contentMode, drawableSize: drawableSize, zoomScale: zoomScale, translation: translation)
    }

    func renderMulti(frame: IRFFVideoFrame,
                     to drawable: CAMetalDrawable,
                     drawableSize: CGSize,
                     viewports: [CGRect],
                     contentModes: [IRGLRenderContentMode],
                     zoomScales: [Float],
                     translations: [SIMD2<Float>]) -> Bool {
        adapter.renderMulti(frame: frame, to: drawable, drawableSize: drawableSize, viewports: viewports, contentModes: contentModes, zoomScales: zoomScales, translations: translations)
    }

    func renderClear(to drawable: CAMetalDrawable) {
        adapter.renderClear(to: drawable)
    }

    func renderFish2Pano(frame: IRFFVideoFrame,
                         params: IRMetalRenderer.Fish2PanoParams,
                         texUVTextures: [MTLTexture],
                         to drawable: CAMetalDrawable,
                         drawableSize: CGSize,
                         viewport: CGRect,
                         contentMode: IRGLRenderContentMode,
                         outputSize: CGSize,
                         zoomScale: Float,
                         translation: SIMD2<Float>) -> Bool {
        adapter.renderFish2Pano(frame: frame,
                              params: params,
                              texUVTextures: texUVTextures,
                              to: drawable,
                              drawableSize: drawableSize,
                              viewport: viewport,
                              contentMode: contentMode,
                              outputSize: outputSize,
                               zoomScale: zoomScale,
                               translation: translation)
    }

    func renderDistortion(frame: IRFFVideoFrame,
                          leftMesh: IRMetalDistortionMesh,
                          rightMesh: IRMetalDistortionMesh,
                          to drawable: CAMetalDrawable,
                          drawableSize: CGSize,
                          contentMode: IRGLRenderContentMode) -> Bool {
        adapter.renderDistortion(frame: frame,
                              leftMesh: leftMesh,
                              rightMesh: rightMesh,
                              to: drawable,
                              drawableSize: drawableSize,
                              contentMode: contentMode)
    }

    func renderFisheye(frame: IRFFVideoFrame,
                       mesh: IRMetalFisheyeMesh,
                       mvp: simd_float4x4,
                       textureMatrix: simd_float4x4,
                       to drawable: CAMetalDrawable,
                       drawableSize: CGSize,
                       viewport: CGRect) -> Bool {
        adapter.renderFisheye(frame: frame,
                            mesh: mesh,
                            mvp: mvp,
                            textureMatrix: textureMatrix,
                            to: drawable,
                            drawableSize: drawableSize,
                            viewport: viewport)
    }

    func renderFisheyeMulti(frame: IRFFVideoFrame,
                            mesh: IRMetalFisheyeMesh,
                            mvpList: [simd_float4x4],
                            textureMatrix: simd_float4x4,
                            to drawable: CAMetalDrawable,
                            drawableSize: CGSize,
                            viewports: [CGRect]) -> Bool {
        adapter.renderFisheyeMulti(frame: frame,
                                 mesh: mesh,
                                 mvpList: mvpList,
                                 textureMatrix: textureMatrix,
                                 to: drawable,
                                 drawableSize: drawableSize,
                                 viewports: viewports)
    }
}

public final class IRGLRenderYUV: IRGLRender {
    private let adapter = IRGLRenderAdapter()

    public init() {}
}

extension IRGLRenderYUV: IRGLRenderInternal {
    func render(frame: IRFFVideoFrame,
                to drawable: CAMetalDrawable,
                contentMode: IRGLRenderContentMode,
                drawableSize: CGSize,
                zoomScale: Float,
                translation: SIMD2<Float>) -> Bool {
        adapter.render(frame: frame, to: drawable, contentMode: contentMode, drawableSize: drawableSize, zoomScale: zoomScale, translation: translation)
    }

    func renderMulti(frame: IRFFVideoFrame,
                     to drawable: CAMetalDrawable,
                     drawableSize: CGSize,
                     viewports: [CGRect],
                     contentModes: [IRGLRenderContentMode],
                     zoomScales: [Float],
                     translations: [SIMD2<Float>]) -> Bool {
        adapter.renderMulti(frame: frame, to: drawable, drawableSize: drawableSize, viewports: viewports, contentModes: contentModes, zoomScales: zoomScales, translations: translations)
    }

    func renderClear(to drawable: CAMetalDrawable) {
        adapter.renderClear(to: drawable)
    }

    func renderFish2Pano(frame: IRFFVideoFrame,
                         params: IRMetalRenderer.Fish2PanoParams,
                         texUVTextures: [MTLTexture],
                         to drawable: CAMetalDrawable,
                         drawableSize: CGSize,
                         viewport: CGRect,
                         contentMode: IRGLRenderContentMode,
                         outputSize: CGSize,
                         zoomScale: Float,
                         translation: SIMD2<Float>) -> Bool {
        adapter.renderFish2Pano(frame: frame,
                              params: params,
                              texUVTextures: texUVTextures,
                              to: drawable,
                              drawableSize: drawableSize,
                              viewport: viewport,
                              contentMode: contentMode,
                              outputSize: outputSize,
                               zoomScale: zoomScale,
                               translation: translation)
    }

    func renderDistortion(frame: IRFFVideoFrame,
                          leftMesh: IRMetalDistortionMesh,
                          rightMesh: IRMetalDistortionMesh,
                          to drawable: CAMetalDrawable,
                          drawableSize: CGSize,
                          contentMode: IRGLRenderContentMode) -> Bool {
        adapter.renderDistortion(frame: frame,
                              leftMesh: leftMesh,
                              rightMesh: rightMesh,
                              to: drawable,
                              drawableSize: drawableSize,
                              contentMode: contentMode)
    }

    func renderFisheye(frame: IRFFVideoFrame,
                       mesh: IRMetalFisheyeMesh,
                       mvp: simd_float4x4,
                       textureMatrix: simd_float4x4,
                       to drawable: CAMetalDrawable,
                       drawableSize: CGSize,
                       viewport: CGRect) -> Bool {
        adapter.renderFisheye(frame: frame,
                            mesh: mesh,
                            mvp: mvp,
                            textureMatrix: textureMatrix,
                            to: drawable,
                            drawableSize: drawableSize,
                            viewport: viewport)
    }

    func renderFisheyeMulti(frame: IRFFVideoFrame,
                            mesh: IRMetalFisheyeMesh,
                            mvpList: [simd_float4x4],
                            textureMatrix: simd_float4x4,
                            to drawable: CAMetalDrawable,
                            drawableSize: CGSize,
                            viewports: [CGRect]) -> Bool {
        adapter.renderFisheyeMulti(frame: frame,
                                 mesh: mesh,
                                 mvpList: mvpList,
                                 textureMatrix: textureMatrix,
                                 to: drawable,
                                 drawableSize: drawableSize,
                                 viewports: viewports)
    }
}
