//
//  IRGLViewRenderState.swift
//  IRPlayer-swift
//
//  Created by Codex on 2026/7/7.
//

import CoreGraphics
import Metal

final class IRGLViewRenderState {
    private(set) var fisheyeMesh: IRMetalFisheyeMesh?
    private(set) var vrMesh: IRMetalFisheyeMesh?
    private(set) var fisheyeController: IRGLTransformController3DFisheye?
    private(set) var fisheyeParameter: IRFisheyeParameter?
    private(set) var fisheyeLastSize: CGSize = .zero
    private(set) var fish2PanoParams: IRGLFish2PanoShaderParams?
    private(set) var fish2PanoTextures: [MTLTexture] = []
    private(set) var fish2PanoLastOutputSize: CGSize = .zero
    private(set) var fish2PanoLastAntialias: Int = 0
    private(set) var distortionLeftMesh: IRMetalDistortionMesh?
    private(set) var distortionRightMesh: IRMetalDistortionMesh?

    enum Fish2PanoTextureReadiness: Equatable {
        case invalid
        case waitingForTextures
        case ready(outputSize: CGSize, antialias: Int)
    }

    func reset() {
        fisheyeMesh = nil
        vrMesh = nil
        fisheyeController = nil
        fisheyeParameter = nil
        fisheyeLastSize = .zero
        resetFish2Pano()
        distortionLeftMesh = nil
        distortionRightMesh = nil
    }

    func configureFish2Pano(renderMode: IRGLRenderMode) {
        guard let program = renderMode.program as? IRGLProgram2DFisheye2Pano,
              let params = program.metalFish2PanoParams else {
            resetFish2Pano()
            return
        }

        if fish2PanoParams !== params {
            resetFish2Pano()
        }
        fish2PanoParams = params
    }

    func prepareFish2PanoTextures(device: MTLDevice?) -> Fish2PanoTextureReadiness? {
        guard let params = fish2PanoParams else { return nil }
        let outputWidth = Int(params.outputWidth)
        let outputHeight = Int(params.outputHeight)
        let antialias = Int(params.antialias)
        guard outputWidth > 0, outputHeight > 0, antialias > 0 else { return .invalid }

        let outputSize = CGSize(width: outputWidth, height: outputHeight)
        if outputSize != fish2PanoLastOutputSize || antialias != fish2PanoLastAntialias {
            fish2PanoTextures = []
            fish2PanoLastOutputSize = outputSize
            fish2PanoLastAntialias = antialias
        }

        let expectedTextureCount = antialias * antialias
        if let device, let pixUV = params.consumePixUVIfReady() {
            defer { params.releaseConsumedPixUV(pixUV) }

            guard pixUV.count == expectedTextureCount else {
                return .waitingForTextures
            }
            var newTextures: [MTLTexture] = []
            newTextures.reserveCapacity(expectedTextureCount)
            for i in 0..<expectedTextureCount {
                guard let texture = makeTexUVTexture(device: device,
                                                     width: outputWidth,
                                                     height: outputHeight,
                                                     data: pixUV[i]) else {
                    return .waitingForTextures
                }
                newTextures.append(texture)
            }
            fish2PanoTextures = newTextures
        }

        guard fish2PanoTextures.count == expectedTextureCount else {
            return .waitingForTextures
        }

        return .ready(outputSize: outputSize, antialias: antialias)
    }

    func configureFisheye(renderMode: IRGLRenderMode, viewportSize: CGSize) {
        guard renderMode is IRGLRenderMode3DFisheye else {
            resetFisheye()
            return
        }

        if let programController = renderMode.program?.tramsformController as? IRGLTransformController3DFisheye {
            fisheyeController = programController
        } else {
            let width = max(Int(viewportSize.width), 1)
            let height = max(Int(viewportSize.height), 1)
            fisheyeController = IRGLTransformController3DFisheye(viewportWidth: width,
                                                                 viewportHeight: height,
                                                                 tileType: .backward)
        }

        if let parameter = renderMode.parameter as? IRFisheyeParameter {
            fisheyeParameter = parameter
        } else {
            fisheyeParameter = Self.defaultFisheyeParameter()
        }
    }

    func resetFisheyeViewport(width: Int, height: Int, resetTransform: Bool) {
        fisheyeController?.resetViewport(width: width,
                                         height: height,
                                         resetTransform: resetTransform)
    }

    func updateFallbackFisheye(fx: Float, fy: Float, sx: Float, sy: Float) {
        fisheyeController?.update(fx: fx, fy: fy, sx: sx, sy: sy)
    }

    func scrollFallbackFisheye(dx: Float, dy: Float) {
        fisheyeController?.scroll(dx: dx, dy: dy)
    }

    func scrollFallbackFisheye(degreeX: Float, degreeY: Float) {
        fisheyeController?.scroll(degreeX: degreeX, degreeY: degreeY)
    }

    private func resetFish2Pano() {
        fish2PanoParams = nil
        fish2PanoTextures = []
        fish2PanoLastOutputSize = .zero
        fish2PanoLastAntialias = 0
    }

    private func resetFisheye() {
        fisheyeController = nil
        fisheyeMesh = nil
        fisheyeParameter = nil
        fisheyeLastSize = .zero
    }

    private func makeTexUVTexture(device: MTLDevice,
                                  width: Int,
                                  height: Int,
                                  data: UnsafeMutablePointer<GLfloat>) -> MTLTexture? {
        guard let layout = IRGLViewPolicy.texUVTextureLayout(width: width, height: height) else { return nil }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rg32Float,
                                                                  width: width,
                                                                  height: height,
                                                                  mipmapped: false)
        descriptor.usage = .shaderRead
        guard let texture = device.makeTexture(descriptor: descriptor) else { return nil }
        let region = MTLRegionMake2D(0, 0, width, height)
        texture.replace(region: region,
                        mipmapLevel: 0,
                        withBytes: data,
                        bytesPerRow: layout.bytesPerRow)
        return texture
    }

    static func defaultFisheyeParameter() -> IRFisheyeParameter {
        IRFisheyeParameter(width: 0,
                           height: 0,
                           up: false,
                           rx: 0,
                           ry: 0,
                           cx: 0,
                           cy: 0,
                           latmax: 0)
    }
}
