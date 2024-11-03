//
//  IRGLFish2PerspShaderParams.swift
//  IRPlayer-swift
//
//  Created by irons on 2024/11/3.
//

import Foundation
import GLKit
import OpenGLES

class IRGLFish2PerspShaderParams: IRGLShaderParams {

    var preferredRotation: GLfloat = 0.0
    var fishaperture: GLfloat = 180.0
    var fishcenterx: GLint = -1
    var fishcentery: GLint = -1
    var fishradiush: GLint = -1
    var fishradiusv: GLint = -1
    var antialias: GLint = 2
    var enableTransformX: GLint = 1
    var enableTransformY: GLint = 1
    var enableTransformZ: GLint = 1
    var transformX: GLfloat = 0.0
    var transformY: GLfloat = -90.0
    var transformZ: GLfloat = 0.0
    var fishfov: GLfloat = GLfloat(180.0 * DTOR)
    var perspfov: GLfloat = GLfloat(100.0 * DTOR)

    override var outputWidth: GLint {
        didSet {
            if self.outputWidth != oldValue {
                glUniform1i(uniformSamplers[8], self.outputWidth)
            }
        }
    }
    override var outputHeight: GLint {
        didSet {
            if self.outputHeight != oldValue {
                glUniform1i(uniformSamplers[9], self.outputHeight)
            }
        }
    }
    override var textureWidth: GLint {
        didSet {
            if self.textureWidth != oldValue {
                glUniform1i(uniformSamplers[1], self.textureWidth)
            }
        }
    }
    override var textureHeight: GLint {
        didSet {
            if self.textureHeight != oldValue {
                glUniform1i(uniformSamplers[2], self.textureHeight)
            }
        }
    }

    private var uniformSamplers = [GLint](repeating: 0, count: 19)
    private var uTextureMatrix: GLint = 0

    override init() {
        super.init()
        setDefaultValues()
    }

    override func resolveUniforms(_ program: GLuint) {
        uTextureMatrix = glGetUniformLocation(program, "uTextureMatrix")

        uniformSamplers[0] = glGetUniformLocation(program, "preferredRotation")
        uniformSamplers[1] = glGetUniformLocation(program, "fishwidth")
        uniformSamplers[2] = glGetUniformLocation(program, "fishheight")
        uniformSamplers[3] = glGetUniformLocation(program, "fishaperture")
        uniformSamplers[4] = glGetUniformLocation(program, "fishcenterx")
        uniformSamplers[5] = glGetUniformLocation(program, "fishcentery")
        uniformSamplers[6] = glGetUniformLocation(program, "fishradiush")
        uniformSamplers[7] = glGetUniformLocation(program, "fishradiusv")
        uniformSamplers[8] = glGetUniformLocation(program, "perspectivewidth")
        uniformSamplers[9] = glGetUniformLocation(program, "perspectiveheight")
        uniformSamplers[10] = glGetUniformLocation(program, "antialias")
        uniformSamplers[11] = glGetUniformLocation(program, "fishfov")
        uniformSamplers[12] = glGetUniformLocation(program, "perspfov")
        uniformSamplers[13] = glGetUniformLocation(program, "enableTransformX")
        uniformSamplers[14] = glGetUniformLocation(program, "enableTransformY")
        uniformSamplers[15] = glGetUniformLocation(program, "enableTransformZ")
        uniformSamplers[16] = glGetUniformLocation(program, "transformX")
        uniformSamplers[17] = glGetUniformLocation(program, "transformY")
        uniformSamplers[18] = glGetUniformLocation(program, "transformZ")
    }

    override func prepareRender() {
        glUniform1f(uniformSamplers[0], preferredRotation)
        glUniform1i(uniformSamplers[1], textureWidth)
        glUniform1i(uniformSamplers[2], textureHeight)
        glUniform1f(uniformSamplers[3], fishaperture)
        glUniform1i(uniformSamplers[4], fishcenterx)
        glUniform1i(uniformSamplers[5], fishcentery)
        glUniform1i(uniformSamplers[6], fishradiush)
        glUniform1i(uniformSamplers[7], fishradiusv)
        glUniform1i(uniformSamplers[8], outputWidth)
        glUniform1i(uniformSamplers[9], outputHeight)
        glUniform1i(uniformSamplers[10], antialias)
        glUniform1f(uniformSamplers[11], fishfov)
        glUniform1f(uniformSamplers[12], perspfov)
        glUniform1i(uniformSamplers[13], enableTransformX)
        glUniform1i(uniformSamplers[14], enableTransformY)
        glUniform1i(uniformSamplers[15], enableTransformZ)
        glUniform1f(uniformSamplers[16], transformX)
        glUniform1f(uniformSamplers[17], transformY)
        glUniform1f(uniformSamplers[18], transformZ)

        var texMatrix = GLKMatrix4MakeScale(1, -1, 1)
        glUniformMatrix4fv(uTextureMatrix, 1, GLboolean(GL_FALSE), texMatrix.array)
    }

    func setDefaultValues() {
        textureWidth = -1
        textureHeight = -1
        fishaperture = 180.0
        fishcenterx = -1
        fishcentery = -1
        fishradiush = -1
        fishradiusv = -1
        outputWidth = 1024
        outputHeight = -1
        antialias = 2
        fishfov = GLfloat(180.0 * DTOR)
        perspfov = GLfloat(100.0 * DTOR)
    }

    func setFishfov(_ fishfov: GLfloat) {
        if self.fishfov != fishfov {
            self.fishfov = fishfov
            glUniform1f(uniformSamplers[11], self.fishfov)
        }
    }

    func setPerspfov(_ perspfov: GLfloat) {
        if self.perspfov != perspfov {
            self.perspfov = perspfov
            glUniform1f(uniformSamplers[12], self.perspfov)
        }
    }

    override func updateTextureWidth(_ w: Int, height h: Int) {
        textureWidth = GLint(w)
        textureHeight = GLint(h)
        updateOutputWH()
        delegate?.didUpdateOutputWH(Int(outputWidth), Int(outputHeight))
    }

    func updateOutputWH() {
        outputWidth = 1280
        outputHeight = 720
        fishcenterx = 680
        fishcentery = 545
        fishradiush = 515
        enableTransformX = 1
        enableTransformY = 1
        enableTransformZ = 1
        let fishfovDegree: GLfloat = 180
        fishfov = min(fishfovDegree, 360.0) * Float(DTOR)
        let perspfovDegree: GLfloat = 100
        perspfov = min(perspfovDegree, 170.0) * Float(DTOR)
    }
}

private extension GLKMatrix4 {
    var array: [GLfloat] {
        return (0..<16).map { self[$0] }
    }
}
