//
//  IRMetalFisheyeMesh.swift
//  IRPlayer-swift
//
//  Created by Codex on 2026/3/8.
//

import Foundation
import Metal
import simd

final class IRMetalFisheyeMesh {
    struct Vertex {
        let position: SIMD3<Float>
        let texCoord: SIMD2<Float>
    }

    struct Parameters: Equatable, Sendable {
        static let zero = Parameters(
            textureWidth: 0,
            textureHeight: 0,
            centerX: 0,
            centerY: 0,
            radius: 0
        )

        let textureWidth: Float
        let textureHeight: Float
        let centerX: Float
        let centerY: Float
        let radius: Float
    }

    let vertexBuffer: MTLBuffer
    let indexBuffer: MTLBuffer
    let indexCount: Int

    init?(device: MTLDevice, positions: [SIMD3<Float>], texcoords: [SIMD2<Float>], indices: [UInt16]) {
        guard positions.count == texcoords.count, !positions.isEmpty, !indices.isEmpty else { return nil }

        var vertices = [Vertex]()
        vertices.reserveCapacity(positions.count)
        for i in 0..<positions.count {
            vertices.append(Vertex(position: positions[i], texCoord: texcoords[i]))
        }

        guard let vertexLength = IRMetalMeshStorage.byteLength(
            elementCount: vertices.count,
            stride: MemoryLayout<Vertex>.stride
        ),
              let indexLength = IRMetalMeshStorage.byteLength(
                  elementCount: indices.count,
                  stride: MemoryLayout<UInt16>.stride
              ) else {
            return nil
        }

        guard let vBuffer = device.makeBuffer(bytes: vertices, length: vertexLength, options: .storageModeShared) else { return nil }
        guard let iBuffer = device.makeBuffer(bytes: indices, length: indexLength, options: .storageModeShared) else { return nil }

        vertexBuffer = vBuffer
        indexBuffer = iBuffer
        indexCount = indices.count
    }

    init?(device: MTLDevice, textureWidth: Float, textureHeight: Float, centerX: Float, centerY: Float, radius: Float) {
        let parameters = Self.resolveParameters(
            textureWidth: textureWidth,
            textureHeight: textureHeight,
            centerX: centerX,
            centerY: centerY,
            radius: radius
        )
        guard parameters.textureWidth > 0,
              parameters.textureHeight > 0,
              parameters.radius > 0 else {
            return nil
        }
        let tw = parameters.textureWidth
        let th = parameters.textureHeight
        let cx = parameters.centerX
        let cy = parameters.centerY
        let cr = parameters.radius

        let slices = 180
        let iMax = slices + 1
        let nVertices = iMax * iMax
        let angleStep: Float = .pi / Float(slices)
        let sphereRadius: Float = 800.0

        var positions = [SIMD3<Float>](repeating: .zero, count: nVertices)
        var texcoords = [SIMD2<Float>](repeating: .zero, count: nVertices)

        for i in 0..<iMax {
            let sini = sin(angleStep * Float(i))
            let cosi = cos(angleStep * Float(i))
            for j in 0..<iMax {
                let sinj = sin(angleStep * Float(j))
                let cosj = cos(angleStep * Float(j))
                let sinisinj = sinj * sini
                let sinicosj = cosj * sini

                let vertexIndex = i * iMax + j
                let texIndex = i * iMax + (iMax - j - 1)

                let x = sphereRadius * sinisinj
                let y = sphereRadius * sinicosj
                let z = sphereRadius * cosi

                let u = (cx - cr * sinicosj) / tw
                let v = (cr * cosi - cy) / th

                positions[vertexIndex] = SIMD3<Float>(x, y, z)
                texcoords[texIndex] = SIMD2<Float>(u, v)
            }
        }

        var vertices = [Vertex]()
        vertices.reserveCapacity(nVertices)
        for index in 0..<nVertices {
            vertices.append(Vertex(position: positions[index], texCoord: texcoords[index]))
        }

        var indices = [UInt16]()
        indices.reserveCapacity(slices * slices * 6)
        for i in 0..<slices {
            let i1 = i + 1
            for j in 0..<slices {
                let j1 = j + 1
                guard let first = IRMetalMeshStorage.index(
                    i * iMax + j
                ),
                      let second = IRMetalMeshStorage.index(
                          i1 * iMax + j
                      ),
                      let third = IRMetalMeshStorage.index(
                          i1 * iMax + j1
                      ),
                      let fourth = IRMetalMeshStorage.index(
                          i * iMax + j1
                      ) else {
                    return nil
                }
                indices.append(first)
                indices.append(second)
                indices.append(third)
                indices.append(first)
                indices.append(third)
                indices.append(fourth)
            }
        }

        guard let vertexLength = IRMetalMeshStorage.byteLength(
            elementCount: vertices.count,
            stride: MemoryLayout<Vertex>.stride
        ),
              let indexLength = IRMetalMeshStorage.byteLength(
                  elementCount: indices.count,
                  stride: MemoryLayout<UInt16>.stride
              ) else {
            return nil
        }

        guard let vBuffer = device.makeBuffer(bytes: vertices, length: vertexLength, options: .storageModeShared) else { return nil }
        guard let iBuffer = device.makeBuffer(bytes: indices, length: indexLength, options: .storageModeShared) else { return nil }

        vertexBuffer = vBuffer
        indexBuffer = iBuffer
        indexCount = indices.count
    }

    static func resolveParameters(
        textureWidth: Float,
        textureHeight: Float,
        centerX: Float,
        centerY: Float,
        radius: Float
    ) -> Parameters {
        guard textureWidth.isFinite,
              textureHeight.isFinite,
              centerX.isFinite,
              centerY.isFinite,
              radius.isFinite,
              textureWidth > 0,
              textureHeight > 0 else {
            return .zero
        }

        let remainingX = textureWidth - centerX
        let remainingY = textureHeight - centerY
        let circleFits =
            centerX > 0 &&
            centerY > 0 &&
            centerX <= textureWidth &&
            centerY <= textureHeight &&
            radius > 0 &&
            radius <= centerX &&
            radius <= centerY &&
            radius <= remainingX &&
            radius <= remainingY

        if circleFits {
            return Parameters(
                textureWidth: textureWidth,
                textureHeight: textureHeight,
                centerX: centerX,
                centerY: centerY,
                radius: radius
            )
        }

        return Parameters(
            textureWidth: textureWidth,
            textureHeight: textureHeight,
            centerX: textureWidth / 2,
            centerY: textureHeight / 2,
            radius: min(textureWidth, textureHeight) / 2
        )
    }
}
