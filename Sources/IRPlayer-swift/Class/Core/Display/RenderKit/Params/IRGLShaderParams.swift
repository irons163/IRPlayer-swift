//
//  IRGLShaderParams.swift
//  IRPlayer-swift
//
//  Metal-only implementation (OpenGL-free)
//

import Foundation

protocol IRGLShaderParamsDelegate: AnyObject {
    func didUpdateOutputWH(_ w: Int, _ h: Int)
}

class IRGLShaderParams: NSObject {

    weak var delegate: IRGLShaderParamsDelegate?

    var textureWidth: GLint = 0
    var textureHeight: GLint = 0
    var outputWidth: GLint = 0
    var outputHeight: GLint = 0

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
