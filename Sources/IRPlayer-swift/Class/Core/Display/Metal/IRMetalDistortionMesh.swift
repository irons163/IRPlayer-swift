//
//  IRMetalDistortionMesh.swift
//  IRPlayer-swift
//
//  Created by Codex on 2026/3/12.
//

import Foundation
import Metal
import simd

enum IRDistortionModelType: Int, Hashable, Equatable, Sendable, RawRepresentable {
    case left
    case right
}

struct IRMetalDistortionVertex {
    var position: SIMD2<Float>
    var vignette: Float
    var redTexCoord: SIMD2<Float>
    var greenTexCoord: SIMD2<Float>
    var blueTexCoord: SIMD2<Float>
}

final class IRMetalDistortionMesh {
    let vertexBuffer: MTLBuffer
    let indexBuffer: MTLBuffer
    let indexCount: Int

    init?(device: MTLDevice, modelType: IRDistortionModelType) {
        guard let mesh = IRMetalDistortionMesh.buildMesh(modelType: modelType) else {
            return nil
        }
        guard !mesh.vertices.isEmpty, !mesh.indices.isEmpty else {
            return nil
        }
        guard let vertexLength = Self.bufferByteLength(elementCount: mesh.vertices.count, stride: MemoryLayout<IRMetalDistortionVertex>.stride),
              let indexLength = Self.bufferByteLength(elementCount: mesh.indices.count, stride: MemoryLayout<UInt16>.stride) else {
            return nil
        }
        guard let vbuf = device.makeBuffer(bytes: mesh.vertices, length: vertexLength, options: .storageModeShared),
              let ibuf = device.makeBuffer(bytes: mesh.indices, length: indexLength, options: .storageModeShared) else {
            return nil
        }
        self.vertexBuffer = vbuf
        self.indexBuffer = ibuf
        self.indexCount = mesh.indices.count
    }

    private static func buildMesh(modelType: IRDistortionModelType) -> (vertices: [IRMetalDistortionVertex], indices: [UInt16])? {
        var xEyeOffsetScreen: Float = 0.523064613
        let yEyeOffsetScreen: Float = 0.80952388
        let viewportWidthTexture: Float = 1.43138313
        let viewportHeightTexture: Float = 1.51814604
        var viewportXTexture: Float = 0
        let viewportYTexture: Float = 0
        let textureWidth: Float = 2.86276627
        let textureHeight: Float = 1.51814604
        var xEyeOffsetTexture: Float = 0.592283607
        let yEyeOffsetTexture: Float = 0.839099586
        let screenWidth: Float = 2.47470069
        let screenHeight: Float = 1.39132345

        switch modelType {
        case .left:
            break
        case .right:
            xEyeOffsetScreen = 1.95163608
            viewportXTexture = 1.43138313
            xEyeOffsetTexture = 2.27048278
        }

        let rows = 40
        let cols = 40
        let vignetteSizeTanAngle: Float = 0.05

        var vertices: [IRMetalDistortionVertex] = []
        vertices.reserveCapacity(rows * cols)

        for row in 0..<rows {
            for col in 0..<cols {
                let uTextureBlue = Float(col) / 39.0 * (viewportWidthTexture / textureWidth) + viewportXTexture / textureWidth
                let vTextureBlue = Float(row) / 39.0 * (viewportHeightTexture / textureHeight) + viewportYTexture / textureHeight

                let xTexture = uTextureBlue * textureWidth - xEyeOffsetTexture
                let yTexture = vTextureBlue * textureHeight - yEyeOffsetTexture
                let rTexture = sqrtf(xTexture * xTexture + yTexture * yTexture)

                let textureToScreenBlue = (rTexture > 0.0) ? blueDistortInverse(radius: rTexture) / rTexture : 1.0

                let xScreen = xTexture * textureToScreenBlue
                let yScreen = yTexture * textureToScreenBlue

                let uScreen = (xScreen + xEyeOffsetScreen) / screenWidth
                let vScreen = (yScreen + yEyeOffsetScreen) / screenHeight
                let rScreen = rTexture * textureToScreenBlue

                let screenToTextureGreen = (rScreen > 0.0) ? distortionFactor(radius: rScreen) : 1.0
                let uTextureGreen = (xScreen * screenToTextureGreen + xEyeOffsetTexture) / textureWidth
                let vTextureGreen = (yScreen * screenToTextureGreen + yEyeOffsetTexture) / textureHeight

                let screenToTextureRed = (rScreen > 0.0) ? distortionFactor(radius: rScreen) : 1.0
                let uTextureRed = (xScreen * screenToTextureRed + xEyeOffsetTexture) / textureWidth
                let vTextureRed = (yScreen * screenToTextureRed + yEyeOffsetTexture) / textureHeight

                let vignetteSizeTexture = vignetteSizeTanAngle / textureToScreenBlue
                let dxTexture = clamp(value: xTexture + xEyeOffsetTexture, min: viewportXTexture + vignetteSizeTexture, max: viewportXTexture + viewportWidthTexture - vignetteSizeTexture)
                let dyTexture = clamp(value: yTexture + yEyeOffsetTexture, min: viewportYTexture + vignetteSizeTexture, max: viewportYTexture + viewportHeightTexture - vignetteSizeTexture)
                let drTexture = sqrtf(dxTexture * dxTexture + dyTexture * dyTexture)

                let vignette = 1.0 - clamp(value: drTexture / vignetteSizeTexture, min: 0.0, max: 1.0)

                let position = SIMD2<Float>(2.0 * uScreen - 1.0, 2.0 * vScreen - 1.0)
                let vertex = IRMetalDistortionVertex(position: position,
                                                     vignette: vignette,
                                                     redTexCoord: SIMD2<Float>(uTextureRed, vTextureRed),
                                                     greenTexCoord: SIMD2<Float>(uTextureGreen, vTextureGreen),
                                                     blueTexCoord: SIMD2<Float>(uTextureBlue, vTextureBlue))
                vertices.append(vertex)
            }
        }

        var indices: [UInt16] = []
        indices.reserveCapacity((rows - 1) * (2 * cols + 1))
        var vertexOffset = 0
        for row in 0..<(rows - 1) {
            if row > 0, let last = indices.last {
                indices.append(last)
            }
            for col in 0..<cols {
                if col > 0 {
                    if row % 2 == 0 {
                        vertexOffset += 1
                    } else {
                        vertexOffset -= 1
                    }
                }
                guard let first = Self.indexValue(vertexOffset),
                      let second = Self.indexValue(vertexOffset + cols) else { return nil }
                indices.append(first)
                indices.append(second)
            }
            vertexOffset += cols
        }

        return (vertices: vertices, indices: indices)
    }

    private static func blueDistortInverse(radius: Float) -> Float {
        var r0 = radius / 0.9
        var r = radius * 0.9
        var dr0 = radius - distort(radius: r0)
        while abs(r - r0) > 0.0001 {
            let dr = radius - distort(radius: r)
            let r2 = r - dr * ((r - r0) / (dr - dr0))
            r0 = r
            r = r2
            dr0 = dr
        }
        return r
    }

    private static func distort(radius: Float) -> Float {
        return radius * distortionFactor(radius: radius)
    }

    private static func distortionFactor(radius: Float) -> Float {
        let coefficients: [Float] = [0.441000015, 0.156000003]
        var result: Float = 1.0
        var rFactor: Float = 1.0
        let squaredRadius = radius * radius
        for coefficient in coefficients {
            rFactor *= squaredRadius
            result += coefficient * rFactor
        }
        return result
    }

    private static func clamp(value: Float, min: Float, max: Float) -> Float {
        return Swift.max(min, Swift.min(max, value))
    }

    static func bufferByteLength(elementCount: Int, stride: Int) -> Int? {
        IRMetalDistortionMeshPolicy.bufferByteLength(elementCount: elementCount, stride: stride)
    }

    static func indexValue(_ value: Int) -> UInt16? {
        IRMetalDistortionMeshPolicy.indexValue(value)
    }
}
