//
//  IRGLFish2PanoShaderParams.swift
//  IRPlayer-swift
//
//  Metal-only implementation (OpenGL-free)
//

import Foundation

private let DTOR: GLfloat = Float.pi / 180.0

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

    private var pixUV: UnsafeMutablePointer<UnsafeMutablePointer<GLfloat>?>?
    private var useTexUVs = false
    private var metalPixUVReady = false

    func consumePixUVIfReady() -> [UnsafeMutablePointer<GLfloat>]? {
        guard metalPixUVReady else { return nil }
        guard let texnum = Self.pixelMapTextureCount(antialias: antialias) else { return nil }
        guard let pixUV = pixUV else { return nil }

        var result: [UnsafeMutablePointer<GLfloat>] = []
        result.reserveCapacity(texnum)
        for i in 0..<texnum {
            guard let ptr = pixUV[i] else { return nil }
            result.append(ptr)
        }

        metalPixUVReady = false
        return result
    }

    override init() {
        super.init()
        setDefaultValues()
    }

    static func outputSize(forTextureWidth textureWidth: Int, height textureHeight: Int) -> (width: Int, height: Int)? {
        guard textureWidth > 0, textureHeight > 0 else { return nil }

        let outputWidth = GLint(1.422222222222222 * Double(textureWidth))
        let vapertureRadians = GLfloat(60.0) * DTOR
        let halfVaperture = 0.5 * vapertureRadians
        let deltaLongitudeRadians = 0.5 * (GLfloat(360.0) * DTOR)
        let outputHeight = GLint(Float(outputWidth) * tan(halfVaperture) / deltaLongitudeRadians)
        guard outputWidth > 0, outputHeight > 0 else { return nil }
        return (Int(outputWidth), Int(outputHeight))
    }

    static func pixelMapTextureCount(antialias: GLint) -> Int? {
        guard antialias > 0 else { return nil }

        let antialiasCount = Int(antialias)
        let (textureCount, overflow) = antialiasCount.multipliedReportingOverflow(by: antialiasCount)
        guard !overflow, textureCount > 0, textureCount <= Int(Int32.max) else { return nil }
        return textureCount
    }

    static func pixelMapCapacity(outputWidth: GLint, outputHeight: GLint) -> Int? {
        guard outputWidth > 0, outputHeight > 0 else { return nil }

        let (pixelCount, pixelCountOverflow) = Int(outputWidth).multipliedReportingOverflow(by: Int(outputHeight))
        guard !pixelCountOverflow else { return nil }

        let (capacity, capacityOverflow) = pixelCount.multipliedReportingOverflow(by: 2)
        guard !capacityOverflow, capacity > 0, capacity <= Int(Int32.max) else { return nil }
        return capacity
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

            if Self.outputSize(forTextureWidth: w, height: h) != nil {
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

        guard let size = Self.outputSize(forTextureWidth: Int(textureWidth), height: Int(textureHeight)) else {
            return
        }
        outputWidth = GLint(size.width)
        outputHeight = GLint(size.height)

        enableTransformX = 1
        enableTransformZ = 1
        transformZ = -90.0

        DispatchQueue.global(qos: .userInitiated).async {
            guard let texnum = Self.pixelMapTextureCount(antialias: self.antialias),
                  let pixelMapCapacity = Self.pixelMapCapacity(outputWidth: self.outputWidth, outputHeight: self.outputHeight) else {
                return
            }
            self.pixUV = .allocate(capacity: texnum)
            for i in 0..<texnum {
                self.pixUV?[i] = .allocate(capacity: pixelMapCapacity)
            }
            self.initPixelMaps()
            self.useTexUVs = true
            self.metalPixUVReady = true
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
