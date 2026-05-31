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

        guard let vertexLength = Self.bufferByteLength(elementCount: vertices.count, stride: MemoryLayout<Vertex>.stride),
              let indexLength = Self.bufferByteLength(elementCount: indices.count, stride: MemoryLayout<UInt16>.stride) else { return nil }

        guard let vBuffer = device.makeBuffer(bytes: vertices, length: vertexLength, options: .storageModeShared) else { return nil }
        guard let iBuffer = device.makeBuffer(bytes: indices, length: indexLength, options: .storageModeShared) else { return nil }

        vertexBuffer = vBuffer
        indexBuffer = iBuffer
        indexCount = indices.count
    }

    init?(device: MTLDevice, textureWidth: Float, textureHeight: Float, centerX: Float, centerY: Float, radius: Float) {
        let (tw, th, cx, cy, cr) = IRMetalFisheyeMesh.resolveParams(textureWidth: textureWidth, textureHeight: textureHeight, centerX: centerX, centerY: centerY, radius: radius)
        guard tw > 0, th > 0, cr > 0 else { return nil }

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
                guard let first = Self.indexValue(i * iMax + j),
                      let second = Self.indexValue(i1 * iMax + j),
                      let third = Self.indexValue(i1 * iMax + j1),
                      let fourth = Self.indexValue(i * iMax + j1) else { return nil }
                indices.append(first)
                indices.append(second)
                indices.append(third)
                indices.append(first)
                indices.append(third)
                indices.append(fourth)
            }
        }

        guard let vertexLength = Self.bufferByteLength(elementCount: vertices.count, stride: MemoryLayout<Vertex>.stride),
              let indexLength = Self.bufferByteLength(elementCount: indices.count, stride: MemoryLayout<UInt16>.stride) else { return nil }

        guard let vBuffer = device.makeBuffer(bytes: vertices, length: vertexLength, options: .storageModeShared) else { return nil }
        guard let iBuffer = device.makeBuffer(bytes: indices, length: indexLength, options: .storageModeShared) else { return nil }

        vertexBuffer = vBuffer
        indexBuffer = iBuffer
        indexCount = indices.count
    }

    static func resolveParams(textureWidth: Float, textureHeight: Float, centerX: Float, centerY: Float, radius: Float) -> (textureWidth: Float, textureHeight: Float, centerX: Float, centerY: Float, radius: Float) {
        let tw = textureWidth
        let th = textureHeight
        var cx = centerX
        var cy = centerY
        var cr = radius

        if tw <= 0 || th <= 0 {
            return (0, 0, 0, 0, 0)
        }

        if cr == 0 || cx == 0 || cy == 0 || cr > tw / 2 || cr > th / 2 || cr + cx > tw || cr + cy > th {
            cx = tw / 2
            cy = th / 2
            cr = min(tw, th) / 2
        }

        return (tw, th, cx, cy, cr)
    }

    static func bufferByteLength(elementCount: Int, stride: Int) -> Int? {
        guard elementCount > 0, stride > 0 else { return nil }

        let (byteLength, overflow) = elementCount.multipliedReportingOverflow(by: stride)
        guard !overflow, byteLength > 0 else { return nil }

        return byteLength
    }

    static func indexValue(_ value: Int) -> UInt16? {
        guard value >= 0, value <= Int(UInt16.max) else { return nil }
        return UInt16(value)
    }
}
