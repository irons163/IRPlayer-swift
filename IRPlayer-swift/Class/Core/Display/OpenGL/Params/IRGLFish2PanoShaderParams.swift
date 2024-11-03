//
//  IRGLFish2PanoShaderParams.swift
//  IRPlayer-swift
//
//  Created by irons on 2024/11/3.
//

import Foundation
import GLKit
import OpenGLES

class IRGLFish2PanoShaderParams: IRGLShaderParams {

    var preferredRotation: GLfloat = 0.0
    var fishaperture: GLfloat = 180.0
    var fishcenterx: GLint = -1
    var fishcentery: GLint = -1
    var fishradiush: GLint = -1
    var fishradiusv: GLint = -1
    var antialias: GLint = 1
    var vaperture: GLfloat = 60.0
    var lat1: GLfloat = -100.0
    var lat2: GLfloat = 100.0
    var long1: GLfloat = 0.0
    var long2: GLfloat = 360.0
    var enableTransformX: GLint = 0
    var enableTransformY: GLint = 0
    var enableTransformZ: GLint = 0
    var transformX: GLfloat = 0.0
    var transformY: GLfloat = 0.0
    var transformZ: GLfloat = -90.0
    var offsetX: GLfloat = 0.0

    private var uniformSamplers = [GLint](repeating: 0, count: 25)
    private var texUVs = [GLuint]()
    private var ltexUVs = [GLint]()
    private var pixUV: UnsafeMutablePointer<UnsafeMutablePointer<GLfloat>?>?
    private var uUseTexUVs: GLint = 0
    private var useTexUVs = false

    override init() {
        super.init()
        setDefaultValues()
    }

    override func resolveUniforms(_ program: GLuint) {
        uniformSamplers[0] = glGetUniformLocation(program, "preferredRotation")
        uniformSamplers[1] = glGetUniformLocation(program, "fishwidth")
        uniformSamplers[2] = glGetUniformLocation(program, "fishheight")
        uniformSamplers[3] = glGetUniformLocation(program, "fishaperture")
        uniformSamplers[4] = glGetUniformLocation(program, "fishcenterx")
        uniformSamplers[5] = glGetUniformLocation(program, "fishcentery")
        uniformSamplers[6] = glGetUniformLocation(program, "fishradiush")
        uniformSamplers[7] = glGetUniformLocation(program, "fishradiusv")
        uniformSamplers[8] = glGetUniformLocation(program, "panowidth")
        uniformSamplers[9] = glGetUniformLocation(program, "panoheight")
        uniformSamplers[10] = glGetUniformLocation(program, "antialias")
        uniformSamplers[11] = glGetUniformLocation(program, "vaperture")
        uniformSamplers[12] = glGetUniformLocation(program, "lat1")
        uniformSamplers[13] = glGetUniformLocation(program, "lat2")
        uniformSamplers[14] = glGetUniformLocation(program, "long1")
        uniformSamplers[15] = glGetUniformLocation(program, "long2")
        uniformSamplers[16] = glGetUniformLocation(program, "enableTransformX")
        uniformSamplers[17] = glGetUniformLocation(program, "enableTransformY")
        uniformSamplers[18] = glGetUniformLocation(program, "enableTransformZ")
        uniformSamplers[19] = glGetUniformLocation(program, "transformX")
        uniformSamplers[20] = glGetUniformLocation(program, "transformY")
        uniformSamplers[21] = glGetUniformLocation(program, "transformZ")
        uniformSamplers[22] = glGetUniformLocation(program, "offsetX")

        let texnum = antialias * antialias
        guard texnum > 0 && texnum <= 9 else {
            print("Antialias level should be an integer between 1 and 3.")
            return
        }

        texUVs = Array(repeating: 0, count: Int(texnum))
        ltexUVs = (0..<texnum).map { i in glGetUniformLocation(program, "texUV\(i)") }

        uUseTexUVs = glGetUniformLocation(program, "useTexUVs")
    }

    func initPixelMaps() {
        let transX = transformX * DTOR
        let transY = transformY * DTOR
        let transZ = transformZ * DTOR
        let tlat1 = tan(lat1 * DTOR)
        let tlat2 = tan(lat2 * DTOR)
        let lng1 = long1 * DTOR
        let dlng = long2 * DTOR - lng1
        let raperture = 2.0 / (fishaperture * DTOR)
        let y0 = (tlat1 + tlat2) / (tlat1 - tlat2)

        for y in 0..<outputHeight {
            for x in 0..<outputWidth {
                for i in 0..<antialias {
                    let fractionX = Float(x) + Float(i) / Float(antialias)
                    let xx = fractionX / Float(outputWidth)
                    let longitude = lng1 + xx * dlng
                    for j in 0..<antialias {
                        let fractionY = Float(y) + Float(j) / Float(antialias)
                        let normalizedY = 2.0 * fractionY / Float(outputHeight)
                        let yy = normalizedY - 1.0
                        let latitude: Float
                        if yy > y0 {
                            latitude = (1.0 - y0) == 0 ? 0 : atan((yy - y0) * tlat2 / (1.0 - y0))
                        } else {
                            latitude = (-1.0 - y0) == 0 ? 0 : atan((yy - y0) * tlat1 / (-1.0 - y0))
                        }
                        setPixelFactors(latitude, longitude, Int(antialias * i + j), Int(x), Int(y), transX, transY, transZ, raperture)
                    }
                }
            }
        }
    }

    func setPixelFactors(_ latitude: Float, _ longitude: Float, _ index: Int, _ x: Int, _ y: Int, _ transX: Float, _ transY: Float, _ transZ: Float, _ raperture: Float) {
        var p = XYZ(x: cos(latitude) * cos(longitude), y: cos(latitude) * sin(longitude), z: sin(latitude))

        if transX != 0 { p = PRotateX(p, transX) }
        if transY != 0 { p = PRotateY(p, transY) }
        if transZ != 0 { p = PRotateZ(p, transZ) }

        let theta = atan2(p.y, p.x)
        let phi = atan2(sqrt(p.x * p.x + p.y * p.y), p.z)
        let r = phi * raperture

        let u = Float(fishcenterx) + Float(fishradiush) * r * cos(theta)
        if u < 0 || u >= Float(textureWidth) {
            pixUV?[index]?[(Int(outputWidth) * y + x) * 2] = -1
            pixUV?[index]?[(Int(outputWidth) * y + x) * 2 + 1] = -1
            return
        }

        let v = Float(textureHeight) - Float(fishcentery) + Float(fishradiush) * r * sin(theta)
        if v < 0 || v >= Float(textureHeight) {
            pixUV?[index]?[(Int(outputWidth) * y + x) * 2] = -1
            pixUV?[index]?[(Int(outputWidth) * y + x) * 2 + 1] = -1
            return
        }

        pixUV?[index]?[(Int(outputWidth) * y + x) * 2] = GLfloat(u)
        pixUV?[index]?[(Int(outputWidth) * y + x) * 2 + 1] = GLfloat(v)
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
        glUniform1f(uniformSamplers[11], vaperture)
        glUniform1f(uniformSamplers[12], lat1)
        glUniform1f(uniformSamplers[13], lat2)
        glUniform1f(uniformSamplers[14], long1)
        glUniform1f(uniformSamplers[15], long2)
        glUniform1i(uniformSamplers[16], enableTransformX)
        glUniform1i(uniformSamplers[17], enableTransformY)
        glUniform1i(uniformSamplers[18], enableTransformZ)
        glUniform1f(uniformSamplers[19], transformX)
        glUniform1f(uniformSamplers[20], transformY)
        glUniform1f(uniformSamplers[21], transformZ)
        glUniform1f(uniformSamplers[22], offsetX)

        if useTexUVs {
            let texnum = texUVs.count
            for i in 0..<texnum {
                glActiveTexture(GLenum(GL_TEXTURE4 + GLint(i)))
                var tex: GLuint = 0
                glGenTextures(1, &tex)

                texUVs[i] = tex
                glBindTexture(GLenum(GL_TEXTURE_2D), tex)

                glTexParameterf(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_MIN_FILTER), GLfloat(GL_LINEAR))
                glTexParameterf(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_MAG_FILTER), GLfloat(GL_LINEAR))
                glTexParameteri(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_WRAP_S), GLint(GL_CLAMP_TO_EDGE))
                glTexParameteri(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_WRAP_T), GLint(GL_CLAMP_TO_EDGE))

                glTexImage2D(GLenum(GL_TEXTURE_2D), 0, GL_RG32F, outputWidth, outputHeight, 0, GLenum(GL_RG), GLenum(GL_FLOAT), pixUV?[i])
                glUniform1i(ltexUVs[i], GLint(i + 4))
            }

            glUniform1i(uUseTexUVs, 1)
            useTexUVs = false
        } else {
            let texnum = texUVs.count
            for i in 0..<texnum {
                glActiveTexture(GLenum(GL_TEXTURE4 + GLint(i)))
                glBindTexture(GLenum(GL_TEXTURE_2D), texUVs[i])
                glUniform1i(ltexUVs[i], GLint(i + 4))
            }
        }
    }

    func setDefaultValues() {
        textureWidth = 0
        textureHeight = 0
        fishaperture = 180.0
        fishcenterx = -1
        fishcentery = -1
        fishradiush = -1
        fishradiusv = -1
        outputWidth = 1024
        outputHeight = 0
        antialias = 1
        vaperture = 60.0
        lat1 = -100.0
        lat2 = 100.0
        long1 = 0.0
        long2 = 360.0
    }

    override func updateTextureWidth(_ w: Int, height h: Int) {
        if textureWidth != GLint(w) || textureHeight != GLint(h) {
            textureWidth = GLint(w)
            textureHeight = GLint(h)
            fishcenterx = textureWidth / 2
            fishcentery = textureHeight / 2
            fishradiush = textureWidth / 2
            fishradiusv = textureHeight / 2

            if w != 0 && h != 0 {
                updateOutputWH()
                delegate?.didUpdateOutputWH(Int(outputWidth), Int(outputHeight))
            }
        }
    }

    func updateOutputWH() {
        lat1 = 0.0
        lat2 = 60.0
        vaperture = abs(lat2 - lat1)
        long1 = 0.0
        long2 = 360.0

        let long1Radians = long1 * DTOR
        let long2Radians = long2 * DTOR
        let deltaLongitudeRadians = 0.5 * (long2Radians - long1Radians)
        let vapertureRadians = vaperture * DTOR
        let halfVaperture = 0.5 * vapertureRadians

        outputWidth = GLint(1.422222222222222 * Double(textureWidth))
        outputHeight = GLint(Float(outputWidth) * tan(halfVaperture) / deltaLongitudeRadians)

        enableTransformX = 1
        enableTransformZ = 1
        transformZ = -90.0

        DispatchQueue.global(qos: .userInitiated).async {
            let texnum = self.ltexUVs.count
            self.pixUV = .allocate(capacity: texnum)
            for i in 0..<texnum {
                self.pixUV?[i] = .allocate(capacity: Int(self.outputWidth * self.outputHeight * 2))
            }
            self.initPixelMaps()
            self.useTexUVs = true
        }
    }
}

struct XYZ {
    var x: GLfloat
    var y: GLfloat
    var z: GLfloat
}

func PRotateX(_ p: XYZ, _ theta: GLfloat) -> XYZ {
    let costheta = cos(theta)
    let sintheta = sin(theta)
    return XYZ(x: p.x, y: p.y * costheta + p.z * sintheta, z: -p.y * sintheta + p.z * costheta)
}

func PRotateY(_ p: XYZ, _ theta: GLfloat) -> XYZ {
    let costheta = cos(theta)
    let sintheta = sin(theta)
    return XYZ(x: p.x * costheta - p.z * sintheta, y: p.y, z: p.x * sintheta + p.z * costheta)
}

func PRotateZ(_ p: XYZ, _ theta: GLfloat) -> XYZ {
    let costheta = cos(theta)
    let sintheta = sin(theta)
    return XYZ(x: p.x * costheta + p.y * sintheta, y: -p.x * sintheta + p.y * costheta, z: p.z)
}
