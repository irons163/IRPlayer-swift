//
//  IRGLTransformControllerDistortion.swift
//  IRPlayer-swift
//
//  Created by irons on 2024/9/7.
//

import Foundation
import GLKit

class IRGLTransformControllerDistortion: IRGLTransformControllerVR {
    private var leftViewMatrix = GLKMatrix4Identity
    private var rightViewMatrix = GLKMatrix4Identity

    override func getModelViewProjectionMatrix() -> GLKMatrix4 {
        let distance: Float = 0.012
        let mv = GLKMatrix4Multiply(leftViewMatrix, modelMatrix) // VM = V x M;
        let mvp = GLKMatrix4Multiply(projectMatrix, mv) // PVM = P x VM;
        return mvp
    }

    func getModelViewProjectionMatrix2() -> GLKMatrix4 {
        let distance: Float = 0.012
        let mv = GLKMatrix4Multiply(rightViewMatrix, modelMatrix) // VM = V x M;
        let mvp = GLKMatrix4Multiply(projectMatrix, mv) // PVM = P x VM;
        return mvp
    }

    override func updateVertices() {
        let distance: Float = 0.012
        super.updateVertices()

        leftViewMatrix = GLKMatrix4MakeLookAt(camera[0] - distance, camera[1], camera[2], 0, 0, 0, 0, 1, 0)
        rightViewMatrix = GLKMatrix4MakeLookAt(camera[0] + distance, camera[1], camera[2], 0, 0, 0, 0, 1, 0)
    }
}

