//
//  IRGLProjectionMesh.swift
//  IRPlayer-swift
//
//  Created by Codex on 2026/7/24.
//

import Foundation
import simd

struct IRGLProjectionMesh: Equatable, Sendable {
    let positions: [SIMD3<Float>]
    let texcoords: [SIMD2<Float>]
    let indices: [UInt16]

    init?(
        positions: [SIMD3<Float>],
        texcoords: [SIMD2<Float>],
        indices: [UInt16]
    ) {
        guard !positions.isEmpty,
              positions.count == texcoords.count,
              !indices.isEmpty,
              indices.count.isMultiple(of: 3),
              positions.allSatisfy({
                  $0.x.isFinite
                      && $0.y.isFinite
                      && $0.z.isFinite
              }),
              texcoords.allSatisfy({
                  $0.x.isFinite && $0.y.isFinite
              }),
              indices.allSatisfy({
                  Int($0) < positions.count
              }) else {
            return nil
        }
        self.positions = positions
        self.texcoords = texcoords
        self.indices = indices
    }

    var exported: (
        positions: [SIMD3<Float>],
        texcoords: [SIMD2<Float>],
        indices: [UInt16]
    ) {
        (positions, texcoords, indices)
    }
}

struct IRGLProjectionMeshPlan: Equatable, Sendable {
    let rowLength: Int
    let vertexCount: Int
    let indexCount: Int
}

struct IRGLEquirectangularGeometry: Equatable, Sendable {
    let textureWidth: Float
    let textureHeight: Float
    let centerX: Float
    let centerY: Float
    let radius: Float
}

enum IRGLProjectionMeshBuilder {
    private enum IndexWinding {
        case vr
        case equirectangular
    }

    static let vrSlices = 200
    static let vrParallels = vrSlices / 2
    static let equirectangularSlices = 180
    static let equirectangularSphereRadius: Float = 800

    static func checkedProduct(
        _ lhs: Int,
        _ rhs: Int
    ) -> Int? {
        guard lhs > 0, rhs > 0 else { return nil }
        let (value, overflow) = lhs.multipliedReportingOverflow(
            by: rhs
        )
        return !overflow && value > 0 ? value : nil
    }

    static func checkedSum(
        _ lhs: Int,
        _ rhs: Int
    ) -> Int? {
        guard lhs >= 0, rhs >= 0 else { return nil }
        let (value, overflow) = lhs.addingReportingOverflow(rhs)
        return !overflow && value >= 0 ? value : nil
    }

    static func uint16Index(
        _ value: Int,
        vertexCount: Int
    ) -> UInt16? {
        guard value >= 0,
              value < vertexCount,
              value <= Int(UInt16.max) else {
            return nil
        }
        return UInt16(value)
    }

    static func vrPlan(
        slices: Int,
        parallels: Int
    ) -> IRGLProjectionMeshPlan? {
        guard slices > 0, parallels > 0,
              let rowLength = checkedSum(slices, 1),
              let rowCount = checkedSum(parallels, 1),
              let vertexCount = checkedProduct(
                  rowLength,
                  rowCount
              ),
              let quadCount = checkedProduct(slices, parallels),
              let indexCount = checkedProduct(quadCount, 6),
              vertexCount - 1 <= Int(UInt16.max) else {
            return nil
        }
        return IRGLProjectionMeshPlan(
            rowLength: rowLength,
            vertexCount: vertexCount,
            indexCount: indexCount
        )
    }

    static func equirectangularPlan(
        slices: Int
    ) -> IRGLProjectionMeshPlan? {
        guard slices > 0,
              let rowLength = checkedSum(slices, 1),
              let vertexCount = checkedProduct(
                  rowLength,
                  rowLength
              ),
              let quadCount = checkedProduct(slices, slices),
              let indexCount = checkedProduct(quadCount, 6),
              vertexCount - 1 <= Int(UInt16.max) else {
            return nil
        }
        return IRGLProjectionMeshPlan(
            rowLength: rowLength,
            vertexCount: vertexCount,
            indexCount: indexCount
        )
    }

    static func normalizedEquirectangularGeometry(
        textureWidth: Float,
        textureHeight: Float,
        centerX: Float,
        centerY: Float,
        radius: Float
    ) -> IRGLEquirectangularGeometry? {
        guard textureWidth.isFinite,
              textureHeight.isFinite,
              centerX.isFinite,
              centerY.isFinite,
              radius.isFinite,
              textureWidth > 0,
              textureHeight > 0,
              centerX >= 0,
              centerY >= 0,
              radius >= 0 else {
            return nil
        }

        var normalizedCenterX = centerX
        var normalizedCenterY = centerY
        var normalizedRadius = radius
        if normalizedRadius == 0
            || normalizedCenterX == 0
            || normalizedCenterY == 0
            || normalizedRadius > textureWidth / 2
            || normalizedRadius > textureHeight / 2
            || normalizedRadius > normalizedCenterX
            || normalizedRadius > normalizedCenterY
            || normalizedRadius + normalizedCenterX > textureWidth
            || normalizedRadius + normalizedCenterY > textureHeight {
            normalizedCenterX = textureWidth / 2
            normalizedCenterY = textureHeight / 2
            normalizedRadius = min(
                textureWidth,
                textureHeight
            ) / 2
        }

        guard isValidEquirectangularGeometry(
            textureWidth: textureWidth,
            textureHeight: textureHeight,
            centerX: normalizedCenterX,
            centerY: normalizedCenterY,
            radius: normalizedRadius
        ) else {
            return nil
        }
        return IRGLEquirectangularGeometry(
            textureWidth: textureWidth,
            textureHeight: textureHeight,
            centerX: normalizedCenterX,
            centerY: normalizedCenterY,
            radius: normalizedRadius
        )
    }

    static func isValidEquirectangularGeometry(
        textureWidth: Float,
        textureHeight: Float,
        centerX: Float,
        centerY: Float,
        radius: Float
    ) -> Bool {
        textureWidth.isFinite
            && textureHeight.isFinite
            && centerX.isFinite
            && centerY.isFinite
            && radius.isFinite
            && textureWidth > 0
            && textureHeight > 0
            && radius > 0
            && centerX > 0
            && centerY > 0
            && radius <= centerX
            && radius <= centerY
            && radius <= textureWidth
            && radius <= textureHeight
            && centerX + radius <= textureWidth
            && centerY + radius <= textureHeight
    }

    static func makeVRMesh(
        slices: Int = vrSlices,
        parallels: Int = vrParallels
    ) -> IRGLProjectionMesh? {
        guard let plan = vrPlan(
            slices: slices,
            parallels: parallels
        ) else {
            return nil
        }

        var positions: [SIMD3<Float>] = []
        positions.reserveCapacity(plan.vertexCount)
        var texcoords: [SIMD2<Float>] = []
        texcoords.reserveCapacity(plan.vertexCount)
        let step = (2 * Float.pi) / Float(slices)

        for parallel in 0...parallels {
            let parallelAngle = step * Float(parallel)
            let sine = sin(parallelAngle)
            let cosine = cos(parallelAngle)
            for slice in 0...slices {
                let sliceAngle = step * Float(slice)
                positions.append(
                    SIMD3<Float>(
                        sine * cos(sliceAngle),
                        cosine,
                        sine * sin(sliceAngle)
                    )
                )
                texcoords.append(
                    SIMD2<Float>(
                        Float(slice) / Float(slices),
                        1 - Float(parallel) / Float(parallels)
                    )
                )
            }
        }

        guard let indices = makeIndices(
            slices: slices,
            rows: parallels,
            rowLength: plan.rowLength,
            vertexCount: plan.vertexCount,
            capacity: plan.indexCount,
            winding: .vr
        ) else {
            return nil
        }
        return IRGLProjectionMesh(
            positions: positions,
            texcoords: texcoords,
            indices: indices
        )
    }

    static func makeEquirectangularMesh(
        geometry: IRGLEquirectangularGeometry,
        slices: Int = equirectangularSlices
    ) -> IRGLProjectionMesh? {
        guard isValidEquirectangularGeometry(
            textureWidth: geometry.textureWidth,
            textureHeight: geometry.textureHeight,
            centerX: geometry.centerX,
            centerY: geometry.centerY,
            radius: geometry.radius
        ),
        let plan = equirectangularPlan(slices: slices) else {
            return nil
        }

        var positions: [SIMD3<Float>] = []
        positions.reserveCapacity(plan.vertexCount)
        var texcoords: [SIMD2<Float>] = []
        texcoords.reserveCapacity(plan.vertexCount)
        let angleStep = Float.pi / Float(slices)

        for latitude in 0...slices {
            let latitudeAngle = angleStep * Float(latitude)
            let latitudeSine = sin(latitudeAngle)
            let latitudeCosine = cos(latitudeAngle)
            for longitude in 0...slices {
                let longitudeAngle =
                    angleStep * Float(longitude)
                let sineProduct =
                    sin(longitudeAngle) * latitudeSine
                let cosineProduct =
                    cos(longitudeAngle) * latitudeSine
                positions.append(
                    SIMD3<Float>(
                        equirectangularSphereRadius * sineProduct,
                        equirectangularSphereRadius * cosineProduct,
                        equirectangularSphereRadius * latitudeCosine
                    )
                )

                let reversedLongitude =
                    plan.rowLength - longitude - 1
                let reversedCosineProduct =
                    cos(angleStep * Float(reversedLongitude))
                        * latitudeSine
                texcoords.append(
                    SIMD2<Float>(
                        (
                            geometry.centerX
                                - geometry.radius
                                    * reversedCosineProduct
                        ) / geometry.textureWidth,
                        (
                            geometry.radius * latitudeCosine
                                - geometry.centerY
                        ) / geometry.textureHeight
                    )
                )
            }
        }

        guard let indices = makeIndices(
            slices: slices,
            rows: slices,
            rowLength: plan.rowLength,
            vertexCount: plan.vertexCount,
            capacity: plan.indexCount,
            winding: .equirectangular
        ) else {
            return nil
        }
        return IRGLProjectionMesh(
            positions: positions,
            texcoords: texcoords,
            indices: indices
        )
    }

    private static func makeIndices(
        slices: Int,
        rows: Int,
        rowLength: Int,
        vertexCount: Int,
        capacity: Int,
        winding: IndexWinding
    ) -> [UInt16]? {
        var indices: [UInt16] = []
        indices.reserveCapacity(capacity)

        for row in 0..<rows {
            for column in 0..<slices {
                let first = row * rowLength + column
                let second = first + rowLength
                guard let firstIndex = uint16Index(
                    first,
                    vertexCount: vertexCount
                ),
                let secondIndex = uint16Index(
                    second,
                    vertexCount: vertexCount
                ),
                let firstNextIndex = uint16Index(
                    first + 1,
                    vertexCount: vertexCount
                ),
                let secondNextIndex = uint16Index(
                    second + 1,
                    vertexCount: vertexCount
                ) else {
                    return nil
                }
                switch winding {
                case .vr:
                    indices.append(contentsOf: [
                        firstIndex,
                        secondIndex,
                        firstNextIndex,
                        secondIndex,
                        secondNextIndex,
                        firstNextIndex
                    ])
                case .equirectangular:
                    indices.append(contentsOf: [
                        firstIndex,
                        secondIndex,
                        secondNextIndex,
                        firstIndex,
                        secondNextIndex,
                        firstNextIndex
                    ])
                }
            }
        }
        return indices.count == capacity ? indices : nil
    }
}
