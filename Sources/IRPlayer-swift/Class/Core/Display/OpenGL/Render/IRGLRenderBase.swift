//
//  IRGLRenderBase.swift
//  IRPlayer-swift
//
//  Created by irons on 2024/8/18.
//

import Foundation
import OpenGLES
import GLKit

@objc public protocol IRGLRender {
    var modelviewProj: GLKMatrix4 { get set }
    func isValid() -> Bool
    func resolveUniforms(_ program: GLuint)
    func setVideoFrame(_ frame: IRFFVideoFrame)
//    func setModelviewProj(_ modelviewProj: GLKMatrix4)
    func prepareRender(_ program: GLuint) -> Bool
    func releaseRender()
}

let kIRColorConversion601: [GLfloat] = [
    1.164,  1.164, 1.164,
    0.0, -0.392, 2.017,
    1.596, -0.813,   0.0
]

let kIRColorConversion709: [GLfloat] = [
    1.164,  1.164, 1.164,
    0.0, -0.213, 2.112,
    1.793, -0.533,   0.0
]

@objcMembers public class IRGLRenderBase: NSObject, IRGLRender {

    public var modelviewProj: GLKMatrix4 = GLKMatrix4Identity
    private var uniformMatrix: GLint = 0

    public func isValid() -> Bool {
        return false
    }

    public func resolveUniforms(_ program: GLuint) {
        uniformMatrix = glGetUniformLocation(program, "modelViewProjectionMatrix")
    }

    public func setVideoFrame(_ frame: IRFFVideoFrame) {
        // Implement as needed
    }

    public func prepareRender(_ program: GLuint) -> Bool {
        glUniformMatrix4fv(uniformMatrix, 1, GLboolean(GL_FALSE), &modelviewProj.m.0)
        return true
    }

    public func releaseRender() {
        // Implement as needed
    }
}
