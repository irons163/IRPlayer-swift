//
//  IRGLRenderModeFactory.swift
//  IRPlayer-swift
//
//  Created by irons on 2024/8/17.
//

import Foundation

class IRGLRenderModeFactory: NSObject {

    static func createNormalModes(with parameter: IRMediaParameter?) -> [IRGLRenderMode] {
        let mode = IRGLRenderMode2D()
        mode.parameter = parameter
        return [mode]
    }

    static func createFisheyeModes(with parameter: IRMediaParameter?) -> [IRGLRenderMode] {
        let normal = IRGLRenderMode2D()
        let fisheye2Pano = IRGLRenderMode2DFisheye2Pano()
        let fisheye = IRGLRenderMode3DFisheye()
        let fisheye4P = IRGLRenderModeMulti4P()

        normal.shiftController.enabled = false
        fisheye2Pano.contentMode = .scaleAspectFill
        fisheye2Pano.wideDegreeX = 360
        fisheye2Pano.wideDegreeY = 20

        let modes: [IRGLRenderMode] = [
            fisheye2Pano,
            fisheye,
            fisheye4P,
            normal
        ]

        for mode in modes {
            mode.parameter = parameter
        }

        normal.name = "Rawdata"
        fisheye2Pano.name = "Panorama"
        fisheye.name = "Onelen"
        fisheye4P.name = "Fourlens"

        return modes
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
        let mode = IRGLRenderMode2DFisheye2Pano()
        mode.parameter = parameter
        mode.contentMode = .scaleAspectFill
        mode.wideDegreeX = 360
        mode.wideDegreeY = 20
        return mode
    }
}
