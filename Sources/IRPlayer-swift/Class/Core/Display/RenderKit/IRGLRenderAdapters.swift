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

fileprivate final class IRGLRenderAdapter: IRGLRenderInternal {
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

    func render(frame: IRFFVideoFrame,
                to drawable: CAMetalDrawable,
                contentMode: IRGLRenderContentMode,
                drawableSize: CGSize,
                zoomScale: Float,
                translation: SIMD2<Float>,
                completion: @escaping IRGLRenderCompletion) -> Bool {
        renderer?.render(
            frame: frame,
            to: drawable,
            contentMode: contentMode,
            drawableSize: drawableSize,
            zoomScale: zoomScale,
            translation: translation,
            completion: completion
        ) ?? false
    }

    func renderMulti(frame: IRFFVideoFrame,
                     to drawable: CAMetalDrawable,
                     drawableSize: CGSize,
                     viewports: [CGRect],
                     contentModes: [IRGLRenderContentMode],
                     zoomScales: [Float],
                     translations: [SIMD2<Float>],
                     completion: @escaping IRGLRenderCompletion) -> Bool {
        renderer?.renderMulti(
            frame: frame,
            to: drawable,
            drawableSize: drawableSize,
            viewports: viewports,
            contentModes: contentModes,
            zoomScales: zoomScales,
            translations: translations,
            completion: completion
        ) ?? false
    }

    func renderClear(to drawable: CAMetalDrawable,
                     completion: @escaping IRGLRenderCompletion) -> Bool {
        renderer?.renderClear(
            to: drawable,
            completion: completion
        ) ?? false
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
                         translation: SIMD2<Float>,
                         completion: @escaping IRGLRenderCompletion) -> Bool {
        renderer?.renderFish2Pano(
            frame: frame,
            params: params,
            texUVTextures: texUVTextures,
            to: drawable,
            drawableSize: drawableSize,
            viewport: viewport,
            contentMode: contentMode,
            outputSize: outputSize,
            zoomScale: zoomScale,
            translation: translation,
            completion: completion
        ) ?? false
    }

    func renderDistortion(frame: IRFFVideoFrame,
                          leftMesh: IRMetalDistortionMesh,
                          rightMesh: IRMetalDistortionMesh,
                          to drawable: CAMetalDrawable,
                          drawableSize: CGSize,
                          contentMode: IRGLRenderContentMode,
                          completion: @escaping IRGLRenderCompletion) -> Bool {
        renderer?.renderDistortion(
            frame: frame,
            leftMesh: leftMesh,
            rightMesh: rightMesh,
            to: drawable,
            drawableSize: drawableSize,
            contentMode: contentMode,
            completion: completion
        ) ?? false
    }

    func renderFisheye(frame: IRFFVideoFrame,
                       mesh: IRMetalFisheyeMesh,
                       mvp: simd_float4x4,
                       textureMatrix: simd_float4x4,
                       to drawable: CAMetalDrawable,
                       drawableSize: CGSize,
                       viewport: CGRect,
                       completion: @escaping IRGLRenderCompletion) -> Bool {
        renderer?.renderFisheye(
            frame: frame,
            mesh: mesh,
            mvp: mvp,
            textureMatrix: textureMatrix,
            to: drawable,
            drawableSize: drawableSize,
            viewport: viewport,
            completion: completion
        ) ?? false
    }

    func renderFisheyeMulti(frame: IRFFVideoFrame,
                            mesh: IRMetalFisheyeMesh,
                            mvpList: [simd_float4x4],
                            textureMatrix: simd_float4x4,
                            to drawable: CAMetalDrawable,
                            drawableSize: CGSize,
                            viewports: [CGRect],
                            completion: @escaping IRGLRenderCompletion) -> Bool {
        renderer?.renderFisheyeMulti(
            frame: frame,
            mesh: mesh,
            mvpList: mvpList,
            textureMatrix: textureMatrix,
            to: drawable,
            drawableSize: drawableSize,
            viewports: viewports,
            completion: completion
        ) ?? false
    }
}

fileprivate protocol IRGLRenderAdapterOwner:
    IRGLRenderInternal
{
    var adapter: IRGLRenderAdapter { get }
}

extension IRGLRenderAdapterOwner {
    func render(frame: IRFFVideoFrame,
                to drawable: CAMetalDrawable,
                contentMode: IRGLRenderContentMode,
                drawableSize: CGSize,
                zoomScale: Float,
                translation: SIMD2<Float>) -> Bool {
        adapter.render(
            frame: frame,
            to: drawable,
            contentMode: contentMode,
            drawableSize: drawableSize,
            zoomScale: zoomScale,
            translation: translation
        )
    }

    func renderMulti(frame: IRFFVideoFrame,
                     to drawable: CAMetalDrawable,
                     drawableSize: CGSize,
                     viewports: [CGRect],
                     contentModes: [IRGLRenderContentMode],
                     zoomScales: [Float],
                     translations: [SIMD2<Float>]) -> Bool {
        adapter.renderMulti(
            frame: frame,
            to: drawable,
            drawableSize: drawableSize,
            viewports: viewports,
            contentModes: contentModes,
            zoomScales: zoomScales,
            translations: translations
        )
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
        adapter.renderFish2Pano(
            frame: frame,
            params: params,
            texUVTextures: texUVTextures,
            to: drawable,
            drawableSize: drawableSize,
            viewport: viewport,
            contentMode: contentMode,
            outputSize: outputSize,
            zoomScale: zoomScale,
            translation: translation
        )
    }

    func renderDistortion(frame: IRFFVideoFrame,
                          leftMesh: IRMetalDistortionMesh,
                          rightMesh: IRMetalDistortionMesh,
                          to drawable: CAMetalDrawable,
                          drawableSize: CGSize,
                          contentMode: IRGLRenderContentMode) -> Bool {
        adapter.renderDistortion(
            frame: frame,
            leftMesh: leftMesh,
            rightMesh: rightMesh,
            to: drawable,
            drawableSize: drawableSize,
            contentMode: contentMode
        )
    }

    func renderFisheye(frame: IRFFVideoFrame,
                       mesh: IRMetalFisheyeMesh,
                       mvp: simd_float4x4,
                       textureMatrix: simd_float4x4,
                       to drawable: CAMetalDrawable,
                       drawableSize: CGSize,
                       viewport: CGRect) -> Bool {
        adapter.renderFisheye(
            frame: frame,
            mesh: mesh,
            mvp: mvp,
            textureMatrix: textureMatrix,
            to: drawable,
            drawableSize: drawableSize,
            viewport: viewport
        )
    }

    func renderFisheyeMulti(frame: IRFFVideoFrame,
                            mesh: IRMetalFisheyeMesh,
                            mvpList: [simd_float4x4],
                            textureMatrix: simd_float4x4,
                            to drawable: CAMetalDrawable,
                            drawableSize: CGSize,
                            viewports: [CGRect]) -> Bool {
        adapter.renderFisheyeMulti(
            frame: frame,
            mesh: mesh,
            mvpList: mvpList,
            textureMatrix: textureMatrix,
            to: drawable,
            drawableSize: drawableSize,
            viewports: viewports
        )
    }

    func render(frame: IRFFVideoFrame,
                to drawable: CAMetalDrawable,
                contentMode: IRGLRenderContentMode,
                drawableSize: CGSize,
                zoomScale: Float,
                translation: SIMD2<Float>,
                completion: @escaping IRGLRenderCompletion) -> Bool {
        adapter.render(
            frame: frame,
            to: drawable,
            contentMode: contentMode,
            drawableSize: drawableSize,
            zoomScale: zoomScale,
            translation: translation,
            completion: completion
        )
    }

    func renderMulti(frame: IRFFVideoFrame,
                     to drawable: CAMetalDrawable,
                     drawableSize: CGSize,
                     viewports: [CGRect],
                     contentModes: [IRGLRenderContentMode],
                     zoomScales: [Float],
                     translations: [SIMD2<Float>],
                     completion: @escaping IRGLRenderCompletion) -> Bool {
        adapter.renderMulti(
            frame: frame,
            to: drawable,
            drawableSize: drawableSize,
            viewports: viewports,
            contentModes: contentModes,
            zoomScales: zoomScales,
            translations: translations,
            completion: completion
        )
    }

    func renderClear(to drawable: CAMetalDrawable,
                     completion: @escaping IRGLRenderCompletion) -> Bool {
        adapter.renderClear(
            to: drawable,
            completion: completion
        )
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
                         translation: SIMD2<Float>,
                         completion: @escaping IRGLRenderCompletion) -> Bool {
        adapter.renderFish2Pano(
            frame: frame,
            params: params,
            texUVTextures: texUVTextures,
            to: drawable,
            drawableSize: drawableSize,
            viewport: viewport,
            contentMode: contentMode,
            outputSize: outputSize,
            zoomScale: zoomScale,
            translation: translation,
            completion: completion
        )
    }

    func renderDistortion(frame: IRFFVideoFrame,
                          leftMesh: IRMetalDistortionMesh,
                          rightMesh: IRMetalDistortionMesh,
                          to drawable: CAMetalDrawable,
                          drawableSize: CGSize,
                          contentMode: IRGLRenderContentMode,
                          completion: @escaping IRGLRenderCompletion) -> Bool {
        adapter.renderDistortion(
            frame: frame,
            leftMesh: leftMesh,
            rightMesh: rightMesh,
            to: drawable,
            drawableSize: drawableSize,
            contentMode: contentMode,
            completion: completion
        )
    }

    func renderFisheye(frame: IRFFVideoFrame,
                       mesh: IRMetalFisheyeMesh,
                       mvp: simd_float4x4,
                       textureMatrix: simd_float4x4,
                       to drawable: CAMetalDrawable,
                       drawableSize: CGSize,
                       viewport: CGRect,
                       completion: @escaping IRGLRenderCompletion) -> Bool {
        adapter.renderFisheye(
            frame: frame,
            mesh: mesh,
            mvp: mvp,
            textureMatrix: textureMatrix,
            to: drawable,
            drawableSize: drawableSize,
            viewport: viewport,
            completion: completion
        )
    }

    func renderFisheyeMulti(frame: IRFFVideoFrame,
                            mesh: IRMetalFisheyeMesh,
                            mvpList: [simd_float4x4],
                            textureMatrix: simd_float4x4,
                            to drawable: CAMetalDrawable,
                            drawableSize: CGSize,
                            viewports: [CGRect],
                            completion: @escaping IRGLRenderCompletion) -> Bool {
        adapter.renderFisheyeMulti(
            frame: frame,
            mesh: mesh,
            mvpList: mvpList,
            textureMatrix: textureMatrix,
            to: drawable,
            drawableSize: drawableSize,
            viewports: viewports,
            completion: completion
        )
    }
}

public final class IRGLRenderNV12: IRGLRender {
    fileprivate let adapter = IRGLRenderAdapter()

    public init() {}
}

extension IRGLRenderNV12: IRGLRenderAdapterOwner {}

public final class IRGLRenderYUV: IRGLRender {
    fileprivate let adapter = IRGLRenderAdapter()

    public init() {}
}

extension IRGLRenderYUV: IRGLRenderAdapterOwner {}
