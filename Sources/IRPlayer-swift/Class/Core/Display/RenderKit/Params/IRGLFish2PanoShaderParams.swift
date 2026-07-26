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
        let requestGeneration: Int
        let configurationKey:
            IRGLFish2PanoPixelMapConfigurationKey
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
    private var publishedPixelMap:
        IRGLFish2PanoPixelMapGeneration?
    private var inFlightPixelMapGeneration: Int?
    private var requiredPixelMapConfiguration:
        IRGLFish2PanoPixelMapConfigurationKey?
    private var pixelMapReadyHandler:
        (@Sendable () -> Void)?

    var publishedPixelMapDiagnostics:
        IRGLFish2PanoPixelMapDiagnostics?
    {
        pixelMapStateLock.lock()
        defer { pixelMapStateLock.unlock() }
        return publishedPixelMap?.diagnostics
    }

    func pixelMapIfReady()
        -> IRGLFish2PanoPixelMapGeneration?
    {
        pixelMapStateLock.lock()
        defer { pixelMapStateLock.unlock() }
        return publishedPixelMap
    }

    func requiredPixelMapConfigurationKey()
        -> IRGLFish2PanoPixelMapConfigurationKey?
    {
        pixelMapStateLock.lock()
        defer { pixelMapStateLock.unlock() }
        return requiredPixelMapConfiguration
    }

    func acknowledgePixelMap(
        _ pixelMap: IRGLFish2PanoPixelMapGeneration
    ) {
        pixelMapStateLock.lock()
        defer { pixelMapStateLock.unlock() }
        guard publishedPixelMap === pixelMap else {
            return
        }
        publishedPixelMap = nil
    }

    func setPixelMapReadyHandler(
        _ handler: (@Sendable () -> Void)?
    ) {
        pixelMapStateLock.lock()
        pixelMapReadyHandler = handler
        let shouldNotify = publishedPixelMap != nil
        pixelMapStateLock.unlock()
        if shouldNotify {
            handler?()
        }
    }

    func takePixelMapIfReady()
        -> IRGLFish2PanoPixelMapGeneration?
    {
        guard let pixelMap = pixelMapIfReady() else {
            return nil
        }
        acknowledgePixelMap(pixelMap)
        return pixelMap
    }

    func ensurePixelMapRequested() {
        guard Self.outputSize(
            forTextureWidth: Int(textureWidth),
            height: Int(textureHeight)
        ) != nil else {
            return
        }
        schedulePixelMap(replacingCurrentRequest: false)
    }

    private func beginPixelMapGeneration(
        replacingCurrentRequest: Bool,
        requiredConfiguration:
            IRGLFish2PanoPixelMapConfigurationKey?
    ) -> Int? {
        pixelMapStateLock.lock()
        defer { pixelMapStateLock.unlock() }
        if !replacingCurrentRequest,
           (publishedPixelMap != nil
                || inFlightPixelMapGeneration != nil) {
            return nil
        }
        let (nextGeneration, overflow) =
            pixelMapGeneration.addingReportingOverflow(1)
        guard !overflow else {
            publishedPixelMap = nil
            inFlightPixelMapGeneration = nil
            requiredPixelMapConfiguration = nil
            return nil
        }
        pixelMapGeneration = nextGeneration
        publishedPixelMap = nil
        inFlightPixelMapGeneration = nextGeneration
        requiredPixelMapConfiguration =
            requiredConfiguration
        return pixelMapGeneration
    }

    private func finishPixelMapGeneration(
        _ generation: Int
    ) {
        pixelMapStateLock.lock()
        if pixelMapGeneration == generation,
           inFlightPixelMapGeneration == generation {
            inFlightPixelMapGeneration = nil
        }
        pixelMapStateLock.unlock()
    }

    private func publish(
        _ pixelMap: IRGLFish2PanoPixelMapGeneration
    ) {
        pixelMapStateLock.lock()
        guard pixelMap.requestGeneration
                == pixelMapGeneration,
              pixelMap.configurationKey
                == requiredPixelMapConfiguration else {
            pixelMapStateLock.unlock()
            return
        }
        publishedPixelMap = pixelMap
        inFlightPixelMapGeneration = nil
        let readyHandler = pixelMapReadyHandler
        pixelMapStateLock.unlock()
        readyHandler?()
    }

    private func isCurrentPixelMapGeneration(
        _ generation: Int
    ) -> Bool {
        pixelMapStateLock.lock()
        defer { pixelMapStateLock.unlock() }
        return generation == pixelMapGeneration
    }

    override init() {
        super.init()
        setDefaultValues()
    }

    static func outputSize(forTextureWidth textureWidth: Int, height textureHeight: Int) -> (width: Int, height: Int)? {
        IRGLFish2PanoPixelMapGeneration.outputSize(
            forTextureWidth: textureWidth,
            height: textureHeight
        )
    }

    static func pixelMapTextureCount(antialias: GLint) -> Int? {
        IRGLFish2PanoPixelMapGeneration.textureCount(
            antialias: Int(antialias)
        )
    }

    static func pixelMapCapacity(outputWidth: GLint, outputHeight: GLint) -> Int? {
        IRGLFish2PanoPixelMapGeneration.elementCount(
            outputWidth: Int(outputWidth),
            outputHeight: Int(outputHeight)
        )
    }

    static func pixelMapUVOffset(outputWidth: GLint, outputHeight: GLint, x: Int, y: Int) -> Int? {
        IRGLFish2PanoPixelMapGeneration.uvOffset(
            outputWidth: Int(outputWidth),
            outputHeight: Int(outputHeight),
            x: x,
            y: y
        )
    }

    private static func makePixelMap(
        configuration: PixelMapConfiguration,
        shouldContinue: () -> Bool
    ) -> IRGLFish2PanoPixelMapGeneration? {
        guard shouldContinue() else {
            return nil
        }
        var pixelMaps = (0..<configuration.textureCount)
            .map { _ in
                Array<GLfloat>(
                    repeating: -1,
                    count: configuration.elementCapacity
                )
            }
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
            guard shouldContinue() else {
                return nil
            }
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
                            pixelMaps: &pixelMaps
                        )
                    }
                }
            }
        }
        return IRGLFish2PanoPixelMapGeneration(
            requestGeneration:
                configuration.requestGeneration,
            configurationKey:
                configuration.configurationKey,
            maps: pixelMaps
        )
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
        pixelMaps: inout [[GLfloat]]
    ) {
        guard pixelMaps.indices.contains(index),
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

        pixelMaps[index][uvOffset] = GLfloat(u)
        pixelMaps[index][uvOffset + 1] = GLfloat(v)
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
        schedulePixelMap(replacingCurrentRequest: true)
    }

    private func schedulePixelMap(
        replacingCurrentRequest: Bool
    ) {
        lat1 = 0.0
        lat2 = 60.0
        vaperture = abs(lat2 - lat1)
        long1 = 0.0
        long2 = 360.0

        guard let size = Self.outputSize(
            forTextureWidth: Int(textureWidth),
            height: Int(textureHeight)
        ) else {
            finishUnavailablePixelMapRequest(
                replacingCurrentRequest:
                    replacingCurrentRequest
            )
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
            finishUnavailablePixelMapRequest(
                replacingCurrentRequest:
                    replacingCurrentRequest
            )
            return
        }
        let configurationKey =
            IRGLFish2PanoPixelMapConfigurationKey(
                inputTextureWidth: Int(textureWidth),
                inputTextureHeight:
                    Int(textureHeight),
                outputWidth: Int(outputWidth),
                outputHeight: Int(outputHeight),
                antialias: Int(antialias),
                fishAperture: fishaperture,
                fishCenterX: Int(fishcenterx),
                fishCenterY: Int(fishcentery),
                fishRadiusH: Int(fishradiush),
                latitudeStart: lat1,
                latitudeEnd: lat2,
                longitudeStart: long1,
                longitudeEnd: long2,
                transformX: transformX,
                transformY: transformY,
                transformZ: transformZ
            )
        guard let jobGeneration =
                beginPixelMapGeneration(
                    replacingCurrentRequest:
                        replacingCurrentRequest,
                    requiredConfiguration:
                        configurationKey
                ) else {
            return
        }
        let configuration = PixelMapConfiguration(
            requestGeneration: jobGeneration,
            configurationKey: configurationKey,
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
            guard let self else {
                return
            }
            guard let pixelMap = Self.makePixelMap(
                configuration: configuration,
                shouldContinue: {
                    self.isCurrentPixelMapGeneration(
                        configuration.requestGeneration
                    )
                }
            ) else {
                self.finishPixelMapGeneration(
                    configuration.requestGeneration
                )
                return
            }
            self.publish(pixelMap)
        }
    }

    private func finishUnavailablePixelMapRequest(
        replacingCurrentRequest: Bool
    ) {
        guard let generation =
                beginPixelMapGeneration(
                    replacingCurrentRequest:
                        replacingCurrentRequest,
                    requiredConfiguration: nil
                ) else {
            return
        }
        finishPixelMapGeneration(generation)
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
