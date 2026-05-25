//
//  IRGLFish2PerspShaderParams.swift
//  IRPlayer-swift
//
//  Metal-only implementation (OpenGL-free)
//

import Foundation

private let DTOR: GLfloat = Float.pi / 180.0

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

    override init() {
        super.init()
        setDefaultValues()
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
        }
    }

    func setPerspfov(_ perspfov: GLfloat) {
        if self.perspfov != perspfov {
            self.perspfov = perspfov
        }
    }

    override func updateTextureWidth(_ w: Int, height h: Int) {
        guard let nextTextureWidth = Self.boundedGLint(from: Double(w)),
              let nextTextureHeight = Self.boundedGLint(from: Double(h)) else {
            return
        }

        textureWidth = nextTextureWidth
        textureHeight = nextTextureHeight
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
