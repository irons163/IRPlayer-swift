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
}

protocol IRGLRenderModeDelegate: AnyObject {
    func programDidCreate(_ program: IRGLProgram2D)
}

public class IRGLRenderMode: NSObject {

    weak var delegate: IRGLRenderModeDelegate?
    public var shiftController: IRePTZShiftController
    public var wideDegreeX: Float = 0.0 {
        didSet {
            configurationKeySequence.append(IRGLRenderModeConfigurationKey.setWideDegreeX.rawValue)
        }
    }
    public var wideDegreeY: Float = 0.0 {
        didSet {
            configurationKeySequence.append(IRGLRenderModeConfigurationKey.setWideDegreeY.rawValue)
        }
    }
    var defaultScale: Float = 1.0 {
        didSet {
            configurationKeySequence.append(IRGLRenderModeConfigurationKey.setDefaultScale.rawValue)
        }
    }
    public var aspect: Float = 0.0
    var scaleRange: IRGLScaleRange? {
        didSet {
            configurationKeySequence.append(IRGLRenderModeConfigurationKey.setScaleRange.rawValue)
        }
    }
    var scopeRange: IRGLScopeRange? {
        didSet {
            configurationKeySequence.append(IRGLRenderModeConfigurationKey.setScopeRange.rawValue)
        }
    }
    public var contentMode: IRGLRenderContentMode = .scaleAspectFit {
        didSet {
            configurationKeySequence.append(IRGLRenderModeConfigurationKey.setContentMode.rawValue)
        }
    }
    public var parameter: IRMediaParameter?
    public var name: String = ""
    public var program: IRGLProgram2D?
    public var renderer: IRGLRender?
    public var programFactory: IRGLProgram2DFactory {
        return IRGLProgram2DFactory()
    }
    private var configurationKeySequence: [String] = []

    public override init() {
        shiftController = IRePTZShiftController()
        name = ""
        defaultScale = 1.0
        configurationKeySequence = []
    }

    func setting() {
        guard program != nil else { return }
        for key in configurationKeySequence {
            settingConfig(key)
        }
    }

    private func settingConfig(_ key: String) {
        settingDefaultScale(key)
        settingWideDegreeX(key)
        settingWideDegreeY(key)
        settingContentMode(key)
        settingScaleRange(key)
        settingScopeRange(key)
    }

    private func settingDefaultScale(_ key: String) {
        if key != IRGLRenderModeConfigurationKey.setDefaultScale.rawValue { return }
        program?.setDefaultScale(defaultScale)
    }

    private func settingWideDegreeX(_ key: String) {
        if key != IRGLRenderModeConfigurationKey.setWideDegreeX.rawValue { return }
        // program?.setWideDegreeX(wideDegreeX)
    }

    private func settingWideDegreeY(_ key: String) {
        guard key == IRGLRenderModeConfigurationKey.setWideDegreeY.rawValue else { return }
        // program?.setWideDegreeY(wideDegreeY)
    }

    private func settingContentMode(_ key: String) {
        guard key == IRGLRenderModeConfigurationKey.setContentMode.rawValue else { return }
        program?.contentMode = contentMode
    }

    private func settingScaleRange(_ key: String) {
        guard key == IRGLRenderModeConfigurationKey.setScaleRange.rawValue else { return }
        program?.tramsformController?.scaleRange = scaleRange
    }

    private func settingScopeRange(_ key: String) {
        guard key == IRGLRenderModeConfigurationKey.setScopeRange.rawValue else { return }
        program?.tramsformController?.scopeRange = scopeRange
    }

    func update() {
        // Implement update logic here
    }
}

enum IRGLRenderModeConfigurationKey: String, Hashable, Equatable, Sendable, RawRepresentable {
    case setDefaultScale = "setDefaultScale"
    case setWideDegreeX = "setWideDegreeX"
    case setWideDegreeY = "setWideDegreeY"
    case setContentMode = "setContentMode"
    case setScaleRange = "setScaleRange"
    case setScopeRange = "setScopeRange"
}
