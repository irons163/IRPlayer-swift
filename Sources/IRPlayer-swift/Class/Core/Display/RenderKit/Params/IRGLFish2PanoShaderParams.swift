//
//  IRGLFish2PanoShaderParams.swift
//  IRPlayer-swift
//
//  Metal-only implementation (OpenGL-free)
//

import Foundation

private let DTOR: GLfloat = Float.pi / 180.0

class IRGLFish2PanoShaderParams: IRGLShaderParams {

    private struct PixelMapConfiguration {
        let textureWidth: Int
        let textureHeight: Int
        let fishAperture: GLfloat
        let fishCenterX: Int
        let fishCenterY: Int
        let fishRadiusH: Int
        let antialias: Int
        let latitudeStart: GLfloat
        let latitudeEnd: GLfloat
        let longitudeStart: GLfloat
        let longitudeEnd: GLfloat
        let transformX: GLfloat
        let transformY: GLfloat
        let transformZ: GLfloat
        let outputWidth: Int
        let outputHeight: Int
        let textureCount: Int
        let elementCapacity: Int
    }

    private final class PixelMap: @unchecked Sendable {
        let pointers: [UnsafeMutablePointer<GLfloat>]

        init(textureCount: Int, elementCapacity: Int) {
            var pointers: [UnsafeMutablePointer<GLfloat>] = []
            pointers.reserveCapacity(textureCount)
            for _ in 0..<textureCount {
                let pointer = UnsafeMutablePointer<GLfloat>.allocate(capacity: elementCapacity)
                pointer.initialize(repeating: -1, count: elementCapacity)
                pointers.append(pointer)
            }
            self.pointers = pointers
        }

        deinit {
            for pointer in pointers {
                pointer.deallocate()
            }
        }

        func matches(_ consumed: [UnsafeMutablePointer<GLfloat>]) -> Bool {
            guard pointers.count == consumed.count else { return false }
            return zip(pointers, consumed).allSatisfy { $0 == $1 }
        }
    }

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

    private let pixelMapQueue = DispatchQueue(label: "irplayer.fish2pano.pixelmap")
    private let pixelMapStateLock = NSLock()
    private var pixelMapGeneration = 0
    private var publishedPixelMap: PixelMap?
    private var consumedPixelMaps: [PixelMap] = []

    func consumePixUVIfReady() -> [UnsafeMutablePointer<GLfloat>]? {
        pixelMapStateLock.lock()
        defer { pixelMapStateLock.unlock() }
        guard let pixelMap = publishedPixelMap else { return nil }
        publishedPixelMap = nil
        consumedPixelMaps.append(pixelMap)
        return pixelMap.pointers
    }

    func releaseConsumedPixUV(_ consumed: [UnsafeMutablePointer<GLfloat>]) {
        pixelMapStateLock.lock()
        defer { pixelMapStateLock.unlock() }
        guard let index = consumedPixelMaps.firstIndex(where: { $0.matches(consumed) }) else {
            return
        }
        consumedPixelMaps.remove(at: index)
    }

    private func nextPixelMapGeneration() -> Int {
        pixelMapStateLock.lock()
        defer { pixelMapStateLock.unlock() }
        pixelMapGeneration += 1
        return pixelMapGeneration
    }

    private func publish(_ pixelMap: PixelMap, generation: Int) {
        pixelMapStateLock.lock()
        defer { pixelMapStateLock.unlock() }
        guard generation == pixelMapGeneration else { return }
        publishedPixelMap = pixelMap
    }

    override init() {
        super.init()
        setDefaultValues()
    }

    static func outputSize(forTextureWidth textureWidth: Int, height textureHeight: Int) -> (width: Int, height: Int)? {
        return IRGLFish2PanoShaderParamsPolicy.outputSize(forTextureWidth: textureWidth, height: textureHeight)
    }

    static func pixelMapTextureCount(antialias: GLint) -> Int? {
        return IRGLFish2PanoShaderParamsPolicy.pixelMapTextureCount(antialias: antialias)
    }

    static func pixelMapCapacity(outputWidth: GLint, outputHeight: GLint) -> Int? {
        return IRGLFish2PanoShaderParamsPolicy.pixelMapCapacity(outputWidth: outputWidth, outputHeight: outputHeight)
    }

    static func pixelMapUVOffset(outputWidth: GLint, outputHeight: GLint, x: Int, y: Int) -> Int? {
        return IRGLFish2PanoShaderParamsPolicy.pixelMapUVOffset(outputWidth: outputWidth,
                                                               outputHeight: outputHeight,
                                                               x: x,
                                                               y: y)
    }

    private static func makePixelMap(configuration: PixelMapConfiguration) -> PixelMap {
        let pixelMap = PixelMap(
            textureCount: configuration.textureCount,
            elementCapacity: configuration.elementCapacity
        )
        let transX = configuration.transformX * DTOR
        let transY = configuration.transformY * DTOR
        let transZ = configuration.transformZ * DTOR
        let tlat1 = tan(configuration.latitudeStart * DTOR)
        let tlat2 = tan(configuration.latitudeEnd * DTOR)
        let lng1 = configuration.longitudeStart * DTOR
        let dlng = configuration.longitudeEnd * DTOR - lng1
        let raperture = 2.0 / (configuration.fishAperture * DTOR)
        let y0 = (tlat1 + tlat2) / (tlat1 - tlat2)

        for y in 0..<configuration.outputHeight {
            for x in 0..<configuration.outputWidth {
                for i in 0..<configuration.antialias {
                    let fractionX = Float(x) + Float(i) / Float(configuration.antialias)
                    let xx = fractionX / Float(configuration.outputWidth)
                    let longitude = lng1 + xx * dlng
                    for j in 0..<configuration.antialias {
                        let fractionY = Float(y) + Float(j) / Float(configuration.antialias)
                        let normalizedY = 2.0 * fractionY / Float(configuration.outputHeight)
                        let yy = normalizedY - 1.0
                        let latitude: Float
                        if yy > y0 {
                            latitude = (1.0 - y0) == 0 ? 0 : atan((yy - y0) * tlat2 / (1.0 - y0))
                        } else {
                            latitude = (-1.0 - y0) == 0 ? 0 : atan((yy - y0) * tlat1 / (-1.0 - y0))
                        }
                        writePixelFactors(
                            latitude: latitude,
                            longitude: longitude,
                            index: configuration.antialias * i + j,
                            x: x,
                            y: y,
                            transX: transX,
                            transY: transY,
                            transZ: transZ,
                            radiusScale: raperture,
                            configuration: configuration,
                            pixelMap: pixelMap
                        )
                    }
                }
            }
        }
        return pixelMap
    }

    private static func writePixelFactors(
        latitude: Float,
        longitude: Float,
        index: Int,
        x: Int,
        y: Int,
        transX: Float,
        transY: Float,
        transZ: Float,
        radiusScale: Float,
        configuration: PixelMapConfiguration,
        pixelMap: PixelMap
    ) {
        guard pixelMap.pointers.indices.contains(index),
              let uvOffset = pixelMapUVOffset(
                outputWidth: GLint(configuration.outputWidth),
                outputHeight: GLint(configuration.outputHeight),
                x: x,
                y: y
              ) else {
            return
        }
        var p = XYZ(x: cos(latitude) * cos(longitude), y: cos(latitude) * sin(longitude), z: sin(latitude))

        if transX != 0 { p = PRotateX(p, transX) }
        if transY != 0 { p = PRotateY(p, transY) }
        if transZ != 0 { p = PRotateZ(p, transZ) }

        let theta = atan2(p.y, p.x)
        let phi = atan2(sqrt(p.x * p.x + p.y * p.y), p.z)
        let r = phi * radiusScale

        let u = Float(configuration.fishCenterX) + Float(configuration.fishRadiusH) * r * cos(theta)
        if u < 0 || u >= Float(configuration.textureWidth) {
            return
        }

        let v = Float(configuration.textureHeight - configuration.fishCenterY)
            + Float(configuration.fishRadiusH) * r * sin(theta)
        if v < 0 || v >= Float(configuration.textureHeight) {
            return
        }

        pixelMap.pointers[index][uvOffset] = GLfloat(u)
        pixelMap.pointers[index][uvOffset + 1] = GLfloat(v)
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
        guard let nextTextureWidth = Self.boundedGLint(from: Double(w)),
              let nextTextureHeight = Self.boundedGLint(from: Double(h)) else {
            return
        }

        if textureWidth != nextTextureWidth || textureHeight != nextTextureHeight {
            textureWidth = nextTextureWidth
            textureHeight = nextTextureHeight
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
        let jobGeneration = nextPixelMapGeneration()

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

        guard let textureCount = Self.pixelMapTextureCount(antialias: antialias),
              let elementCapacity = Self.pixelMapCapacity(
                outputWidth: outputWidth,
                outputHeight: outputHeight
              ) else {
            return
        }
        let configuration = PixelMapConfiguration(
            textureWidth: Int(textureWidth),
            textureHeight: Int(textureHeight),
            fishAperture: fishaperture,
            fishCenterX: Int(fishcenterx),
            fishCenterY: Int(fishcentery),
            fishRadiusH: Int(fishradiush),
            antialias: Int(antialias),
            latitudeStart: lat1,
            latitudeEnd: lat2,
            longitudeStart: long1,
            longitudeEnd: long2,
            transformX: transformX,
            transformY: transformY,
            transformZ: transformZ,
            outputWidth: Int(outputWidth),
            outputHeight: Int(outputHeight),
            textureCount: textureCount,
            elementCapacity: elementCapacity
        )

        pixelMapQueue.async { [weak self] in
            let pixelMap = Self.makePixelMap(configuration: configuration)
            self?.publish(pixelMap, generation: jobGeneration)
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
