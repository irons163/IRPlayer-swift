//
//  IRGLFish2PerspShaderParamsPolicy.swift
//  IRPlayer-swift
//
//  Created by Codex on 2026/6/2.
//

import Foundation

enum IRGLFish2PerspShaderParamsPolicy {
    struct OutputConfiguration {
        let outputWidth: GLint
        let outputHeight: GLint
        let fishCenterX: GLint
        let fishCenterY: GLint
        let fishRadiusH: GLint
        let enableTransformX: GLint
        let enableTransformY: GLint
        let enableTransformZ: GLint
        let fishFov: GLfloat
        let perspFov: GLfloat
    }

    private static let degreesToRadians: GLfloat = Float.pi / 180.0

    static func outputConfiguration() -> OutputConfiguration {
        let fishFovDegree: GLfloat = 180
        let perspFovDegree: GLfloat = 100
        return OutputConfiguration(
            outputWidth: 1280,
            outputHeight: 720,
            fishCenterX: 680,
            fishCenterY: 545,
            fishRadiusH: 515,
            enableTransformX: 1,
            enableTransformY: 1,
            enableTransformZ: 1,
            fishFov: min(fishFovDegree, 360.0) * degreesToRadians,
            perspFov: min(perspFovDegree, 170.0) * degreesToRadians
        )
    }
}
