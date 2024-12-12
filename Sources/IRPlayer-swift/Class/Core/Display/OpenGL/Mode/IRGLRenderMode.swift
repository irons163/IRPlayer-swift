//
//  IRGLRenderMode.swift
//  IRPlayer-swift
//
//  Created by irons on 2024/8/17.
//

import Foundation

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
    public var renderer: IRGLRender? {
        didSet {
            configurationKeySequence.append(IRGLRenderModeConfigurationKey.setRenderer.rawValue)
        }
    }
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
        settingRenderer(key)
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

    private func settingRenderer(_ key: String) {
        guard key == IRGLRenderModeConfigurationKey.setRenderer.rawValue,
              let renderer = renderer else { return }
        program?.renderer = renderer
    }

    func update() {
        // Implement update logic here
    }
}

enum IRGLRenderModeConfigurationKey: String {
    case setDefaultScale = "setDefaultScale"
    case setWideDegreeX = "setWideDegreeX"
    case setWideDegreeY = "setWideDegreeY"
    case setContentMode = "setContentMode"
    case setScaleRange = "setScaleRange"
    case setScopeRange = "setScopeRange"
    case setRenderer = "setRenderer"
}
