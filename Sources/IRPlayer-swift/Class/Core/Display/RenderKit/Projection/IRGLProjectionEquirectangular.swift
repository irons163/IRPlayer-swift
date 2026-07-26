//
//  IRGLProjectionEquirectangular.swift
//  IRPlayer-swift
//
//  Metal-only implementation (OpenGL-free)
//

import Foundation
import simd

final class IRGLProjectionEquirectangular:
    IRGLProjection,
    @unchecked Sendable
{
    struct Diagnostics: Equatable {
        let generation: UInt64
        let hasMesh: Bool
        let vertexCount: Int
        let indexCount: Int
    }

    private let lock = NSLock()
    private var mesh: IRGLProjectionMesh?
    private var generation: UInt64 = 0

    var diagnostics: Diagnostics {
        lock.lock()
        defer { lock.unlock() }
        return Diagnostics(
            generation: generation,
            hasMesh: mesh != nil,
            vertexCount: mesh?.positions.count ?? 0,
            indexCount: mesh?.indices.count ?? 0
        )
    }

    init(
        textureWidth: Float,
        height: Float,
        centerX: Float,
        centerY: Float,
        radius: Float
    ) {
        rebuild(
            textureWidth: textureWidth,
            textureHeight: height,
            centerX: centerX,
            centerY: centerY,
            radius: radius
        )
    }

    func update(with parameter: IRMediaParameter) {
        guard let parameter = parameter as? IRFisheyeParameter else {
            return
        }
        rebuild(
            textureWidth: parameter.width,
            textureHeight: parameter.height,
            centerX: parameter.cx,
            centerY: parameter.cy,
            radius: parameter.ry
        )
    }

    func updateVertex() {
        // Metal consumes the exported immutable mesh.
    }

    func draw() {
        // Rendering is owned by the Metal renderer.
    }

    func exportMesh() -> (
        positions: [SIMD3<Float>],
        texcoords: [SIMD2<Float>],
        indices: [UInt16]
    )? {
        lock.lock()
        let mesh = mesh
        lock.unlock()
        return mesh?.exported
    }

    private func rebuild(
        textureWidth: Float,
        textureHeight: Float,
        centerX: Float,
        centerY: Float,
        radius: Float
    ) {
        guard let geometry =
            IRGLProjectionMeshBuilder
                .normalizedEquirectangularGeometry(
                    textureWidth: textureWidth,
                    textureHeight: textureHeight,
                    centerX: centerX,
                    centerY: centerY,
                    radius: radius
                ),
              let candidate =
                IRGLProjectionMeshBuilder
                    .makeEquirectangularMesh(
                        geometry: geometry
                    ) else {
            return
        }

        lock.lock()
        mesh = candidate
        generation &+= 1
        lock.unlock()
    }
}
