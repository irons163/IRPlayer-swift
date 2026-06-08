//
//  IRGLRenderModeFactory.swift
//  IRPlayer-swift
//
//  Created by irons on 2024/8/17.
//

import Foundation

class IRGLRenderModeFactory: NSObject {

    static func createNormalModes(with parameter: IRMediaParameter?) -> [IRGLRenderMode] {
        IRGLRenderModeFactoryPolicy.normalModePlan().map {
            makeMode(for: $0, parameter: parameter)
        }
    }

    static func createFisheyeModes(with parameter: IRMediaParameter?) -> [IRGLRenderMode] {
        IRGLRenderModeFactoryPolicy.fisheyeModePlan().map {
            makeMode(for: $0, parameter: parameter)
        }
    }

    static func createVRMode(with parameter: IRMediaParameter?) -> IRGLRenderMode {
        let mode = IRGLRenderModeVR()
        mode.parameter = parameter
        return mode
    }

    static func createDistortionMode(with parameter: IRMediaParameter?) -> IRGLRenderMode {
        let mode = IRGLRenderModeDistortion()
        mode.parameter = parameter
        return mode
    }

    static func createFisheyeMode(with parameter: IRMediaParameter?) -> IRGLRenderMode {
        let mode = IRGLRenderMode3DFisheye()
        mode.parameter = parameter
        return mode
    }

    static func createPanoramaMode(with parameter: IRMediaParameter?) -> IRGLRenderMode {
        makeMode(for: IRGLRenderModeFactoryPolicy.panoramaModePlan(),
                 parameter: parameter)
    }

    private static func makeMode(for plan: IRGLRenderModeFactoryPolicy.ModePlan,
                                 parameter: IRMediaParameter?) -> IRGLRenderMode {
        let mode: IRGLRenderMode

        switch plan {
        case .normal2D:
            mode = IRGLRenderMode2D()
        case let .normal2DNamed(name, shiftEnabled):
            let normal = IRGLRenderMode2D()
            normal.name = name
            normal.shiftController.enabled = shiftEnabled
            mode = normal
        case let .panorama(name, wideDegreeX, wideDegreeY):
            let panorama = IRGLRenderMode2DFisheye2Pano()
            panorama.name = name
            panorama.contentMode = .scaleAspectFill
            panorama.wideDegreeX = wideDegreeX
            panorama.wideDegreeY = wideDegreeY
            mode = panorama
        case let .fisheye3D(name):
            let fisheye = IRGLRenderMode3DFisheye()
            fisheye.name = name
            mode = fisheye
        case let .multi4P(name):
            let multi4P = IRGLRenderModeMulti4P()
            multi4P.name = name
            mode = multi4P
        }

        mode.parameter = parameter
        return mode
    }
}
