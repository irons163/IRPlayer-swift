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

    static func boundedGLint(from value: Double) -> GLint? {
        return IRGLShaderParamsPolicy.boundedGLint(from: value)
    }

    func updateTextureWidth(_ w: Int, height h: Int) {
        guard let nextTextureWidth = Self.boundedGLint(from: Double(w)),
              let nextTextureHeight = Self.boundedGLint(from: Double(h)) else {
            return
        }

        if textureWidth != nextTextureWidth || textureHeight != nextTextureHeight {
            textureWidth = nextTextureWidth
            textureHeight = nextTextureHeight
            outputWidth = nextTextureWidth
            outputHeight = nextTextureHeight
            delegate?.didUpdateOutputWH(w, h)
        }
    }
}
