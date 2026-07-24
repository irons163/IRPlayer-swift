//
//  IRGLRenderModeFactory.swift
//  IRPlayer-swift
//
//  Created by irons on 2024/8/17.
//

import Foundation

class IRGLRenderModeFactory: NSObject {

    static func createNormalModes(with parameter: IRMediaParameter?) -> [IRGLRenderMode] {
        [makeNormalMode(parameter: parameter)]
    }

    static func createFisheyeModes(with parameter: IRMediaParameter?) -> [IRGLRenderMode] {
        [
            makePanoramaMode(
                name: "Panorama",
                parameter: parameter
            ),
            makeFisheyeMode(
                name: "Onelen",
                parameter: parameter
            ),
            makeMulti4PMode(
                name: "Fourlens",
                parameter: parameter
            ),
            makeNormalMode(
                name: "Rawdata",
                shiftEnabled: false,
                parameter: parameter
            )
        ]
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
        makePanoramaMode(name: "", parameter: parameter)
    }

    private static func makeNormalMode(
        name: String = "",
        shiftEnabled: Bool = true,
        parameter: IRMediaParameter?
    ) -> IRGLRenderMode {
        let mode = IRGLRenderMode2D()
        mode.name = name
        mode.shiftController.enabled = shiftEnabled
        mode.parameter = parameter
        return mode
    }

    private static func makePanoramaMode(
        name: String,
        parameter: IRMediaParameter?
    ) -> IRGLRenderMode {
        let mode = IRGLRenderMode2DFisheye2Pano()
        mode.name = name
        mode.contentMode = .scaleAspectFill
        mode.wideDegreeX = 360
        mode.wideDegreeY = 20
        mode.parameter = parameter
        return mode
    }

    private static func makeFisheyeMode(
        name: String,
        parameter: IRMediaParameter?
    ) -> IRGLRenderMode {
        let mode = IRGLRenderMode3DFisheye()
        mode.name = name
        mode.parameter = parameter
        return mode
    }

    private static func makeMulti4PMode(
        name: String,
        parameter: IRMediaParameter?
    ) -> IRGLRenderMode {
        let mode = IRGLRenderModeMulti4P()
        mode.name = name
        mode.parameter = parameter
        return mode
    }
}
