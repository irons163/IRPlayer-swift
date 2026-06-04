//
//  IRGLProjectionVR.swift
//  IRPlayer-swift
//
//  Metal-only implementation (OpenGL-free)
//

import Foundation
import simd

class IRGLProjectionVR: IRGLProjection {

    var index_count: Int = 0
    var vertex_count: Int = 0

    private static var vertex_buffer_data: UnsafeMutablePointer<GLfloat>? = nil
    private static var index_buffer_data: UnsafeMutablePointer<GLushort>? = nil
    private static var texture_buffer_data: UnsafeMutablePointer<GLfloat>? = nil

    private static let slices_count = 200
    private static let parallels_count = slices_count / 2

    private static let index_count = slices_count * parallels_count * 6
    private static let vertex_count = (slices_count + 1) * (parallels_count + 1)

    init(textureWidth w: Float, height h: Float) {
        setupModel()
    }

    func update(with parameter: IRMediaParameter) {
        // No-op
    }

    func updateVertex() {
        // No-op for Metal
    }

    func draw() {
        // No-op for Metal
    }

    func exportMesh() -> (positions: [SIMD3<Float>], texcoords: [SIMD2<Float>], indices: [UInt16])? {
        if IRGLProjectionVR.vertex_buffer_data == nil || IRGLProjectionVR.texture_buffer_data == nil || IRGLProjectionVR.index_buffer_data == nil {
            ensureVRData()
        }
        guard let vbuf = IRGLProjectionVR.vertex_buffer_data,
              let tbuf = IRGLProjectionVR.texture_buffer_data,
              let ibuf = IRGLProjectionVR.index_buffer_data else {
            return nil
        }

        var positions: [SIMD3<Float>] = []
        positions.reserveCapacity(IRGLProjectionVR.vertex_count)
        for i in 0..<IRGLProjectionVR.vertex_count {
            let base = i * 3
            positions.append(SIMD3<Float>(vbuf[base], vbuf[base + 1], vbuf[base + 2]))
        }

        var texcoords: [SIMD2<Float>] = []
        texcoords.reserveCapacity(IRGLProjectionVR.vertex_count)
        for i in 0..<IRGLProjectionVR.vertex_count {
            let base = i * 2
            texcoords.append(SIMD2<Float>(tbuf[base], tbuf[base + 1]))
        }

        var indices: [UInt16] = []
        indices.reserveCapacity(IRGLProjectionVR.index_count)
        for i in 0..<IRGLProjectionVR.index_count {
            indices.append(ibuf[i])
        }

        return (positions: positions, texcoords: texcoords, indices: indices)
    }
}

extension IRGLProjectionVR {

    private func setupModel() {
        ensureVRData()
        index_count = IRGLProjectionVR.index_count
        vertex_count = IRGLProjectionVR.vertex_count
    }

    private func ensureVRData() {
        guard IRGLProjectionVR.vertex_buffer_data == nil ||
              IRGLProjectionVR.texture_buffer_data == nil ||
              IRGLProjectionVR.index_buffer_data == nil else {
            return
        }

        let step: Float = (2.0 * .pi) / Float(IRGLProjectionVR.slices_count)
        let radius: Float = 1.0

        IRGLProjectionVR.index_buffer_data = UnsafeMutablePointer<GLushort>.allocate(capacity: IRGLProjectionVR.index_count)
        IRGLProjectionVR.vertex_buffer_data = UnsafeMutablePointer<GLfloat>.allocate(capacity: IRGLProjectionVR.vertex_count * 3)
        IRGLProjectionVR.texture_buffer_data = UnsafeMutablePointer<GLfloat>.allocate(capacity: IRGLProjectionVR.vertex_count * 2)

        var runCount = 0
        for i in 0...IRGLProjectionVR.parallels_count {
            for j in 0...IRGLProjectionVR.slices_count {
                let x = radius * sin(step * Float(i)) * cos(step * Float(j))
                let y = radius * cos(step * Float(i))
                let z = radius * sin(step * Float(i)) * sin(step * Float(j))

                IRGLProjectionVR.vertex_buffer_data?[runCount * 3] = x
                IRGLProjectionVR.vertex_buffer_data?[runCount * 3 + 1] = y
                IRGLProjectionVR.vertex_buffer_data?[runCount * 3 + 2] = z

                IRGLProjectionVR.texture_buffer_data?[runCount * 2] = Float(j) / Float(IRGLProjectionVR.slices_count)
                IRGLProjectionVR.texture_buffer_data?[runCount * 2 + 1] = 1.0 - Float(i) / Float(IRGLProjectionVR.parallels_count)

                runCount += 1
            }
        }

        var index = 0
        for i in 0..<IRGLProjectionVR.parallels_count {
            for j in 0..<IRGLProjectionVR.slices_count {
                let first = i * (IRGLProjectionVR.slices_count + 1) + j
                let second = first + IRGLProjectionVR.slices_count + 1

                guard let firstIndex = Self.glIndex(first),
                      let secondIndex = Self.glIndex(second),
                      let firstNextIndex = Self.glIndex(first + 1),
                      let secondNextIndex = Self.glIndex(second + 1) else {
                    Self.releaseVRData()
                    return
                }

                IRGLProjectionVR.index_buffer_data?[index] = firstIndex
                index += 1
                IRGLProjectionVR.index_buffer_data?[index] = secondIndex
                index += 1
                IRGLProjectionVR.index_buffer_data?[index] = firstNextIndex
                index += 1

                IRGLProjectionVR.index_buffer_data?[index] = secondIndex
                index += 1
                IRGLProjectionVR.index_buffer_data?[index] = secondNextIndex
                index += 1
                IRGLProjectionVR.index_buffer_data?[index] = firstNextIndex
                index += 1
            }
        }
    }

    private static func releaseVRData() {
        index_buffer_data?.deallocate()
        vertex_buffer_data?.deallocate()
        texture_buffer_data?.deallocate()

        index_buffer_data = nil
        vertex_buffer_data = nil
        texture_buffer_data = nil
    }

    static func glIndex(_ value: Int) -> GLushort? {
        return IRGLProjectionVRPolicy.glIndex(value)
    }
}
