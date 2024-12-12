//
//  IRGLShaderParams.swift
//  IRPlayer-swift
//
//  Created by irons on 2024/11/3.
//

import Foundation
import GLKit
import OpenGLES

protocol IRGLShaderParamsDelegate: AnyObject {
    func didUpdateOutputWH(_ w: Int, _ h: Int)
}

class IRGLShaderParams: NSObject {

    weak var delegate: IRGLShaderParamsDelegate?

    var textureWidth: GLint = 0
    var textureHeight: GLint = 0
    var outputWidth: GLint = 0
    var outputHeight: GLint = 0

    private var uTextureMatrix: GLint = 0

    func resolveUniforms(_ program: GLuint) {
        uTextureMatrix = glGetUniformLocation(program, "uTextureMatrix")
    }

    func prepareRender() {
        var texMatrix = GLKMatrix4MakeScale(1, -1, 1)
        glUniformMatrix4fv(uTextureMatrix, 1, GLboolean(GL_FALSE), texMatrix.array)
    }

    func updateTextureWidth(_ w: Int, height h: Int) {
        if textureWidth != GLint(w) || textureHeight != GLint(h) {
            textureWidth = GLint(w)
            textureHeight = GLint(h)
            outputWidth = GLint(w)
            outputHeight = GLint(h)

            delegate?.didUpdateOutputWH(w, h)
        }
    }
}

private extension GLKMatrix4 {
    var array: [GLfloat] {
        return (0..<16).map { self[$0] }
    }
}
