//
//  IRGLProjectionVR.swift
//  IRPlayer-swift
//
//  Metal-only implementation (OpenGL-free)
//

import Foundation
import simd

final class IRGLProjectionVR: IRGLProjection {
    struct MeshSnapshot: Equatable, Sendable {
        let generation: UInt64
        let mesh: IRGLProjectionMesh
    }

    private static let sharedMesh: IRGLProjectionMesh = {
        guard let mesh =
            IRGLProjectionMeshBuilder.makeVRMesh() else {
            preconditionFailure(
                "The built-in VR mesh configuration is invalid."
            )
        }
        return mesh
    }()

    private static let sharedMeshGeneration: UInt64 = 1

    private(set) var index_count: Int
    private(set) var vertex_count: Int

    init(textureWidth _: Float, height _: Float) {
        index_count = Self.sharedMesh.indices.count
        vertex_count = Self.sharedMesh.positions.count
    }

    func update(with _: IRMediaParameter) {
        // VR sphere geometry is independent of media dimensions.
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
        meshSnapshot().mesh.exported
    }

    func meshSnapshot() -> MeshSnapshot {
        MeshSnapshot(
            generation: Self.sharedMeshGeneration,
            mesh: Self.sharedMesh
        )
    }
}
