//
//  IRGLTransformControllerDistortion.swift
//  IRPlayer-swift
//
//  Metal-only implementation (OpenGL-free)
//

import Foundation
import simd

class IRGLTransformControllerDistortion: IRGLTransformControllerVR {
    private var leftViewMatrix = IRMatrix4.identity()
    private var rightViewMatrix = IRMatrix4.identity()

    override func getModelViewProjectionMatrix() -> simd_float4x4 {
        let mv = IRMatrix4.multiply(leftViewMatrix, modelMatrix) // VM = V x M;
        let mvp = IRMatrix4.multiply(projectMatrix, mv) // PVM = P x VM;
        return mvp
    }

    func getModelViewProjectionMatrix2() -> simd_float4x4 {
        let mv = IRMatrix4.multiply(rightViewMatrix, modelMatrix) // VM = V x M;
        let mvp = IRMatrix4.multiply(projectMatrix, mv) // PVM = P x VM;
        return mvp
    }

    override func updateVertices() {
        let distance: Float = 0.012
        super.updateVertices()

        leftViewMatrix = IRMatrix4.makeLookAt(SIMD3<Float>(camera[0] - distance, camera[1], camera[2]),
                                              SIMD3<Float>(0, 0, 0),
                                              SIMD3<Float>(0, 1, 0))
        rightViewMatrix = IRMatrix4.makeLookAt(SIMD3<Float>(camera[0] + distance, camera[1], camera[2]),
                                               SIMD3<Float>(0, 0, 0),
                                               SIMD3<Float>(0, 1, 0))
    }
}
