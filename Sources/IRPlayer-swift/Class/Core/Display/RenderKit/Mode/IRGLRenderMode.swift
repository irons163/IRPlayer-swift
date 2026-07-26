//
//  IRGLRenderMode.swift
//  IRPlayer-swift
//
//  Created by irons on 2024/8/17.
//

import Foundation
import CoreGraphics
import Metal
import QuartzCore
import simd

public protocol IRGLRender: AnyObject {}

typealias IRGLRenderCompletion = @Sendable () -> Void

protocol IRGLRenderInternal: IRGLRender {
    func render(frame: IRFFVideoFrame,
                to drawable: CAMetalDrawable,
                contentMode: IRGLRenderContentMode,
                drawableSize: CGSize,
                zoomScale: Float,
                translation: SIMD2<Float>) -> Bool

    func renderMulti(frame: IRFFVideoFrame,
                     to drawable: CAMetalDrawable,
                     drawableSize: CGSize,
                     viewports: [CGRect],
                     contentModes: [IRGLRenderContentMode],
                     zoomScales: [Float],
                     translations: [SIMD2<Float>]) -> Bool

    func renderClear(to drawable: CAMetalDrawable)

    func renderFish2Pano(frame: IRFFVideoFrame,
                         params: IRMetalRenderer.Fish2PanoParams,
                         texUVTextures: [MTLTexture],
                         to drawable: CAMetalDrawable,
                         drawableSize: CGSize,
                         viewport: CGRect,
                         contentMode: IRGLRenderContentMode,
                         outputSize: CGSize,
                         zoomScale: Float,
                         translation: SIMD2<Float>) -> Bool

    func renderDistortion(frame: IRFFVideoFrame,
                          leftMesh: IRMetalDistortionMesh,
                          rightMesh: IRMetalDistortionMesh,
                          to drawable: CAMetalDrawable,
                          drawableSize: CGSize,
                          contentMode: IRGLRenderContentMode) -> Bool

    func renderFisheye(frame: IRFFVideoFrame,
                       mesh: IRMetalFisheyeMesh,
                       mvp: simd_float4x4,
                       textureMatrix: simd_float4x4,
                       to drawable: CAMetalDrawable,
                       drawableSize: CGSize,
                       viewport: CGRect) -> Bool

    func renderFisheyeMulti(frame: IRFFVideoFrame,
                            mesh: IRMetalFisheyeMesh,
                            mvpList: [simd_float4x4],
                            textureMatrix: simd_float4x4,
                            to drawable: CAMetalDrawable,
                            drawableSize: CGSize,
                            viewports: [CGRect]) -> Bool

    func render(frame: IRFFVideoFrame,
                to drawable: CAMetalDrawable,
                contentMode: IRGLRenderContentMode,
                drawableSize: CGSize,
                zoomScale: Float,
                translation: SIMD2<Float>,
                completion: @escaping IRGLRenderCompletion) -> Bool

    func renderMulti(frame: IRFFVideoFrame,
                     to drawable: CAMetalDrawable,
                     drawableSize: CGSize,
                     viewports: [CGRect],
                     contentModes: [IRGLRenderContentMode],
                     zoomScales: [Float],
                     translations: [SIMD2<Float>],
                     completion: @escaping IRGLRenderCompletion) -> Bool

    func renderClear(to drawable: CAMetalDrawable,
                     completion: @escaping IRGLRenderCompletion) -> Bool

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
                         completion: @escaping IRGLRenderCompletion) -> Bool

    func renderDistortion(frame: IRFFVideoFrame,
                          leftMesh: IRMetalDistortionMesh,
                          rightMesh: IRMetalDistortionMesh,
                          to drawable: CAMetalDrawable,
                          drawableSize: CGSize,
                          contentMode: IRGLRenderContentMode,
                          completion: @escaping IRGLRenderCompletion) -> Bool

    func renderFisheye(frame: IRFFVideoFrame,
                       mesh: IRMetalFisheyeMesh,
                       mvp: simd_float4x4,
                       textureMatrix: simd_float4x4,
                       to drawable: CAMetalDrawable,
                       drawableSize: CGSize,
                       viewport: CGRect,
                       completion: @escaping IRGLRenderCompletion) -> Bool

    func renderFisheyeMulti(frame: IRFFVideoFrame,
                            mesh: IRMetalFisheyeMesh,
                            mvpList: [simd_float4x4],
                            textureMatrix: simd_float4x4,
                            to drawable: CAMetalDrawable,
                            drawableSize: CGSize,
                            viewports: [CGRect],
                            completion: @escaping IRGLRenderCompletion) -> Bool
}

extension IRGLRenderInternal {
    func render(frame: IRFFVideoFrame,
                to drawable: CAMetalDrawable,
                contentMode: IRGLRenderContentMode,
                drawableSize: CGSize,
                zoomScale: Float,
                translation: SIMD2<Float>,
                completion: @escaping IRGLRenderCompletion) -> Bool {
        let submitted = render(
            frame: frame,
            to: drawable,
            contentMode: contentMode,
            drawableSize: drawableSize,
            zoomScale: zoomScale,
            translation: translation
        )
        if submitted {
            completion()
        }
        return submitted
    }

    func renderMulti(frame: IRFFVideoFrame,
                     to drawable: CAMetalDrawable,
                     drawableSize: CGSize,
                     viewports: [CGRect],
                     contentModes: [IRGLRenderContentMode],
                     zoomScales: [Float],
                     translations: [SIMD2<Float>],
                     completion: @escaping IRGLRenderCompletion) -> Bool {
        let submitted = renderMulti(
            frame: frame,
            to: drawable,
            drawableSize: drawableSize,
            viewports: viewports,
            contentModes: contentModes,
            zoomScales: zoomScales,
            translations: translations
        )
        if submitted {
            completion()
        }
        return submitted
    }

    func renderClear(to drawable: CAMetalDrawable,
                     completion: @escaping IRGLRenderCompletion) -> Bool {
        renderClear(to: drawable)
        completion()
        return true
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
        let submitted = renderFish2Pano(
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
        if submitted {
            completion()
        }
        return submitted
    }

    func renderDistortion(frame: IRFFVideoFrame,
                          leftMesh: IRMetalDistortionMesh,
                          rightMesh: IRMetalDistortionMesh,
                          to drawable: CAMetalDrawable,
                          drawableSize: CGSize,
                          contentMode: IRGLRenderContentMode,
                          completion: @escaping IRGLRenderCompletion) -> Bool {
        let submitted = renderDistortion(
            frame: frame,
            leftMesh: leftMesh,
            rightMesh: rightMesh,
            to: drawable,
            drawableSize: drawableSize,
            contentMode: contentMode
        )
        if submitted {
            completion()
        }
        return submitted
    }

    func renderFisheye(frame: IRFFVideoFrame,
                       mesh: IRMetalFisheyeMesh,
                       mvp: simd_float4x4,
                       textureMatrix: simd_float4x4,
                       to drawable: CAMetalDrawable,
                       drawableSize: CGSize,
                       viewport: CGRect,
                       completion: @escaping IRGLRenderCompletion) -> Bool {
        let submitted = renderFisheye(
            frame: frame,
            mesh: mesh,
            mvp: mvp,
            textureMatrix: textureMatrix,
            to: drawable,
            drawableSize: drawableSize,
            viewport: viewport
        )
        if submitted {
            completion()
        }
        return submitted
    }

    func renderFisheyeMulti(frame: IRFFVideoFrame,
                            mesh: IRMetalFisheyeMesh,
                            mvpList: [simd_float4x4],
                            textureMatrix: simd_float4x4,
                            to drawable: CAMetalDrawable,
                            drawableSize: CGSize,
                            viewports: [CGRect],
                            completion: @escaping IRGLRenderCompletion) -> Bool {
        let submitted = renderFisheyeMulti(
            frame: frame,
            mesh: mesh,
            mvpList: mvpList,
            textureMatrix: textureMatrix,
            to: drawable,
            drawableSize: drawableSize,
            viewports: viewports
        )
        if submitted {
            completion()
        }
        return submitted
    }
}

protocol IRGLRenderModeDelegate: AnyObject {
    func programDidCreate(_ program: IRGLProgram2D)
}

public class IRGLRenderMode: NSObject {

    private enum ConfigurationChange: Equatable {
        case defaultScale
        case contentMode
        case scaleRange
        case scopeRange
    }

    weak var delegate: IRGLRenderModeDelegate?
    public var shiftController: IRePTZShiftController
    public var wideDegreeX: Float = 0.0
    public var wideDegreeY: Float = 0.0
    var defaultScale: Float = 1.0 {
        didSet {
            record(.defaultScale)
        }
    }
    public var aspect: Float = 0.0
    var scaleRange: IRGLScaleRange? {
        didSet {
            record(.scaleRange)
        }
    }
    var scopeRange: IRGLScopeRange? {
        didSet {
            record(.scopeRange)
        }
    }
    public var contentMode: IRGLRenderContentMode = .scaleAspectFit {
        didSet {
            record(.contentMode)
        }
    }
    public var parameter: IRMediaParameter?
    public var name: String = ""
    public var program: IRGLProgram2D?
    public var renderer: IRGLRender?
    public var programFactory: IRGLProgram2DFactory {
        return IRGLProgram2DFactory()
    }
    private var configurationChanges: [ConfigurationChange] = []

    public override init() {
        shiftController = IRePTZShiftController()
        name = ""
        defaultScale = 1.0
        configurationChanges = []
    }

    func setting() {
        guard program != nil else { return }
        for change in configurationChanges {
            apply(change)
        }
    }

    private func record(_ change: ConfigurationChange) {
        configurationChanges.removeAll { $0 == change }
        configurationChanges.append(change)
    }

    private func apply(_ change: ConfigurationChange) {
        switch change {
        case .defaultScale:
            program?.setDefaultScale(defaultScale)
        case .contentMode:
            program?.contentMode = contentMode
        case .scaleRange:
            program?.tramsformController?.scaleRange = scaleRange
        case .scopeRange:
            program?.tramsformController?.scopeRange = scopeRange
        }
    }

    func update() {
        // Implement update logic here
    }
}
