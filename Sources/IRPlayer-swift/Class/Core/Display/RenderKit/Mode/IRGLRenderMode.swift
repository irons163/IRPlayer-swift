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
        switch IRGLRenderModeSettingPolicy.action(for: key) {
        case .defaultScale:
            program?.setDefaultScale(defaultScale)
        case .wideDegreeX:
            break
        case .wideDegreeY:
            break
        case .contentMode:
            program?.contentMode = contentMode
        case .scaleRange:
            program?.tramsformController?.scaleRange = scaleRange
        case .scopeRange:
            program?.tramsformController?.scopeRange = scopeRange
        case .none:
            break
        }
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
