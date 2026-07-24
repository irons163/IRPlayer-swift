//
//  IRGLProjectionEquirectangularTests.swift
//  IRPlayer-swiftTests
//
//  Created by Codex on 2026/6/2.
//

import Foundation
import XCTest
#if SWIFT_PACKAGE
@testable import IRPlayerSwift
#else
@testable import IRPlayer_swift
#endif

final class IRGLProjectionEquirectangularTests: XCTestCase {
    func testMeshRejectsEmptyStorage() {
        XCTAssertNil(
            IRGLProjectionMesh(
                positions: [],
                texcoords: [],
                indices: []
            )
        )
    }

    func testMeshRejectsMismatchedVertexStorage() {
        XCTAssertNil(
            IRGLProjectionMesh(
                positions: [SIMD3<Float>(0, 0, 0)],
                texcoords: [],
                indices: [0]
            )
        )
    }

    func testMeshRejectsOutOfRangeIndices() {
        XCTAssertNil(
            IRGLProjectionMesh(
                positions: [SIMD3<Float>(0, 0, 0)],
                texcoords: [SIMD2<Float>(0, 0)],
                indices: [1]
            )
        )
    }

    func testMeshRejectsIncompleteTriangleIndices() {
        XCTAssertNil(
            IRGLProjectionMesh(
                positions: [SIMD3<Float>(0, 0, 0)],
                texcoords: [SIMD2<Float>(0, 0)],
                indices: [0, 0]
            )
        )
    }

    func testMeshRejectsNonFiniteAttributes() {
        XCTAssertNil(
            IRGLProjectionMesh(
                positions: [SIMD3<Float>(.nan, 0, 0)],
                texcoords: [SIMD2<Float>(0, 0)],
                indices: [0, 0, 0]
            )
        )
        XCTAssertNil(
            IRGLProjectionMesh(
                positions: [SIMD3<Float>(0, 0, 0)],
                texcoords: [SIMD2<Float>(.infinity, 0)],
                indices: [0, 0, 0]
            )
        )
    }

    func testMeshAcceptsOneCompleteTriangle() throws {
        let positions = [
            SIMD3<Float>(0, 0, 0),
            SIMD3<Float>(1, 0, 0),
            SIMD3<Float>(0, 1, 0)
        ]
        let texcoords = [
            SIMD2<Float>(0, 0),
            SIMD2<Float>(1, 0),
            SIMD2<Float>(0, 1)
        ]
        let mesh = try XCTUnwrap(
            IRGLProjectionMesh(
                positions: positions,
                texcoords: texcoords,
                indices: [0, 1, 2]
            )
        )

        XCTAssertEqual(mesh.positions, positions)
        XCTAssertEqual(mesh.texcoords, texcoords)
        XCTAssertEqual(mesh.indices, [0, 1, 2])
    }

    func testCheckedArithmeticRejectsInvalidAndOverflowingCounts() {
        XCTAssertNil(
            IRGLProjectionMeshBuilder.checkedProduct(0, 1)
        )
        XCTAssertNil(
            IRGLProjectionMeshBuilder.checkedProduct(1, 0)
        )
        XCTAssertNil(
            IRGLProjectionMeshBuilder.checkedProduct(Int.max, 2)
        )
        XCTAssertNil(
            IRGLProjectionMeshBuilder.checkedSum(-1, 1)
        )
        XCTAssertNil(
            IRGLProjectionMeshBuilder.checkedSum(Int.max, 1)
        )
        XCTAssertEqual(
            IRGLProjectionMeshBuilder.checkedProduct(4, 3),
            12
        )
        XCTAssertEqual(
            IRGLProjectionMeshBuilder.checkedSum(4, 3),
            7
        )
    }

    func testEquirectangularPlanValidatesUInt16Capacity() throws {
        XCTAssertNil(
            IRGLProjectionMeshBuilder.equirectangularPlan(
                slices: 0
            )
        )
        XCTAssertNil(
            IRGLProjectionMeshBuilder.equirectangularPlan(
                slices: 256
            )
        )
        XCTAssertNil(
            IRGLProjectionMeshBuilder.equirectangularPlan(
                slices: Int.max
            )
        )
        XCTAssertEqual(
            IRGLProjectionMeshBuilder.equirectangularPlan(
                slices: 255
            )?.vertexCount,
            65_536
        )

        let plan = try XCTUnwrap(
            IRGLProjectionMeshBuilder.equirectangularPlan(
                slices: 180
            )
        )
        XCTAssertEqual(plan.rowLength, 181)
        XCTAssertEqual(plan.vertexCount, 32_761)
        XCTAssertEqual(plan.indexCount, 194_400)
    }

    func testGeometryNormalizationPreservesValidInput() throws {
        let geometry = try XCTUnwrap(
            IRGLProjectionMeshBuilder
                .normalizedEquirectangularGeometry(
                    textureWidth: 1440,
                    textureHeight: 1080,
                    centerX: 720,
                    centerY: 540,
                    radius: 520
                )
        )

        XCTAssertEqual(
            geometry,
            IRGLEquirectangularGeometry(
                textureWidth: 1440,
                textureHeight: 1080,
                centerX: 720,
                centerY: 540,
                radius: 520
            )
        )
    }

    func testGeometryNormalizationFallsBackToImageBounds() throws {
        let geometry = try XCTUnwrap(
            IRGLProjectionMeshBuilder
                .normalizedEquirectangularGeometry(
                    textureWidth: 1440,
                    textureHeight: 1080,
                    centerX: 1,
                    centerY: 1,
                    radius: 0
                )
        )

        XCTAssertEqual(geometry.centerX, 720)
        XCTAssertEqual(geometry.centerY, 540)
        XCTAssertEqual(geometry.radius, 540)
    }

    func testGeometryNormalizationRejectsUnavailableDimensions() {
        XCTAssertNil(
            IRGLProjectionMeshBuilder
                .normalizedEquirectangularGeometry(
                    textureWidth: 0,
                    textureHeight: 1080,
                    centerX: 720,
                    centerY: 540,
                    radius: 520
                )
        )
        XCTAssertNil(
            IRGLProjectionMeshBuilder
                .normalizedEquirectangularGeometry(
                    textureWidth: .nan,
                    textureHeight: 1080,
                    centerX: 720,
                    centerY: 540,
                    radius: 520
                )
        )
        XCTAssertNil(
            IRGLProjectionMeshBuilder
                .normalizedEquirectangularGeometry(
                    textureWidth: 1440,
                    textureHeight: .infinity,
                    centerX: 720,
                    centerY: 540,
                    radius: 520
                )
        )
    }

    func testGeometryNormalizationRejectsNegativeSentinels() {
        XCTAssertNil(
            IRGLProjectionMeshBuilder
                .normalizedEquirectangularGeometry(
                    textureWidth: 1440,
                    textureHeight: 1080,
                    centerX: 720,
                    centerY: 540,
                    radius: -1
                )
        )
        XCTAssertNil(
            IRGLProjectionMeshBuilder
                .normalizedEquirectangularGeometry(
                    textureWidth: 1440,
                    textureHeight: 1080,
                    centerX: -1,
                    centerY: 540,
                    radius: 520
                )
        )
    }

    func testProjectionExportsCompatibleGeometryAndWinding() throws {
        let projection = makeProjection()
        let mesh = try XCTUnwrap(projection.exportMesh())

        XCTAssertEqual(mesh.positions.count, 32_761)
        XCTAssertEqual(mesh.texcoords.count, 32_761)
        XCTAssertEqual(mesh.indices.count, 194_400)
        XCTAssertEqual(mesh.positions[0].x, 0, accuracy: 0.0001)
        XCTAssertEqual(mesh.positions[0].y, 0, accuracy: 0.0001)
        XCTAssertEqual(mesh.positions[0].z, 800, accuracy: 0.0001)
        XCTAssertEqual(mesh.texcoords[0].x, 0.5, accuracy: 0.0001)
        XCTAssertEqual(
            mesh.texcoords[0].y,
            -20.0 / 1080.0,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            mesh.indices.prefix(6).map(Int.init),
            [0, 181, 182, 0, 182, 1]
        )
        XCTAssertEqual(mesh.indices.last, 32_579)
    }

    func testInvalidInitialGeometryPublishesNoGeneration() {
        let projection = IRGLProjectionEquirectangular(
            textureWidth: 0,
            height: 0,
            centerX: 1,
            centerY: 1,
            radius: 1
        )

        XCTAssertNil(projection.exportMesh())
        XCTAssertEqual(
            projection.diagnostics,
            .init(
                generation: 0,
                hasMesh: false,
                vertexCount: 0,
                indexCount: 0
            )
        )
    }

    func testFisheyeUpdatePublishesNewGenerationAndKeepsSnapshot() throws {
        let projection = makeProjection()
        let firstDiagnostics = projection.diagnostics
        let firstMesh = try XCTUnwrap(projection.exportMesh())
        let retainedTexcoords = firstMesh.texcoords

        projection.update(
            with: makeFisheyeParameter(radius: 480)
        )

        let secondDiagnostics = projection.diagnostics
        let secondMesh = try XCTUnwrap(projection.exportMesh())
        XCTAssertEqual(firstDiagnostics.generation, 1)
        XCTAssertEqual(secondDiagnostics.generation, 2)
        XCTAssertEqual(firstMesh.positions, secondMesh.positions)
        XCTAssertNotEqual(firstMesh.texcoords, secondMesh.texcoords)
        XCTAssertEqual(firstMesh.texcoords, retainedTexcoords)
        XCTAssertEqual(firstMesh.indices, secondMesh.indices)
    }

    func testInvalidUpdatePreservesPublishedGeneration() throws {
        let projection = makeProjection()
        let diagnostics = projection.diagnostics
        let firstMesh = try XCTUnwrap(projection.exportMesh())

        projection.update(
            with: makeFisheyeParameter(
                width: .nan,
                radius: 480
            )
        )

        let secondMesh = try XCTUnwrap(projection.exportMesh())
        XCTAssertEqual(projection.diagnostics, diagnostics)
        XCTAssertEqual(secondMesh.positions, firstMesh.positions)
        XCTAssertEqual(secondMesh.texcoords, firstMesh.texcoords)
        XCTAssertEqual(secondMesh.indices, firstMesh.indices)
    }

    func testNonFisheyeUpdatePreservesPublishedGeneration() throws {
        let projection = makeProjection()
        let diagnostics = projection.diagnostics
        let firstMesh = try XCTUnwrap(projection.exportMesh())

        projection.update(
            with: IRMediaParameter(width: 320, height: 180)
        )

        let secondMesh = try XCTUnwrap(projection.exportMesh())
        XCTAssertEqual(projection.diagnostics, diagnostics)
        XCTAssertEqual(secondMesh.positions, firstMesh.positions)
        XCTAssertEqual(secondMesh.texcoords, firstMesh.texcoords)
        XCTAssertEqual(secondMesh.indices, firstMesh.indices)
    }

    func testNoOpRendererHooksPreservePublishedGeneration() throws {
        let projection = makeProjection()
        let diagnostics = projection.diagnostics

        projection.updateVertex()
        projection.draw()

        XCTAssertEqual(projection.diagnostics, diagnostics)
        XCTAssertNotNil(projection.exportMesh())
    }

    func testIndependentProjectionsDoNotShareMutableGeneration() {
        let first = makeProjection()
        let second = makeProjection()

        first.update(with: makeFisheyeParameter(radius: 480))

        XCTAssertEqual(first.diagnostics.generation, 2)
        XCTAssertEqual(second.diagnostics.generation, 1)
    }

    func testConcurrentUpdateAndExportRemainGenerationCoherent() {
        let projection = makeProjection()
        let invalidExports =
            LockedEquirectangularProjectionTestValue(0)

        DispatchQueue.concurrentPerform(iterations: 24) { index in
            if index.isMultiple(of: 4) {
                projection.update(
                    with: IRFisheyeParameter(
                        width: 1440,
                        height: 1080,
                        up: false,
                        rx: index.isMultiple(of: 8)
                            ? 480
                            : 500,
                        ry: index.isMultiple(of: 8)
                            ? 480
                            : 500,
                        cx: 720,
                        cy: 540,
                        latmax: 80
                    )
                )
                return
            }

            guard let mesh = projection.exportMesh(),
                  mesh.positions.count == 32_761,
                  mesh.texcoords.count == 32_761,
                  mesh.indices.count == 194_400,
                  mesh.indices.prefix(6).map(Int.init)
                    == [0, 181, 182, 0, 182, 1],
                  mesh.indices.last == 32_579 else {
                invalidExports.withValue { $0 += 1 }
                return
            }
        }

        XCTAssertEqual(invalidExports.value, 0)
        XCTAssertEqual(projection.diagnostics.generation, 7)
    }

    func testProjectionConstructionProducesNoDebugOutput() {
        let output = captureStandardOutput {
            _ = makeProjection()
        }

        XCTAssertEqual(output, "")
    }

    private func makeProjection()
        -> IRGLProjectionEquirectangular
    {
        IRGLProjectionEquirectangular(
            textureWidth: 1440,
            height: 1080,
            centerX: 720,
            centerY: 540,
            radius: 520
        )
    }

    private func makeFisheyeParameter(
        width: Float = 1440,
        height: Float = 1080,
        radius: Float
    ) -> IRFisheyeParameter {
        IRFisheyeParameter(
            width: width,
            height: height,
            up: false,
            rx: radius,
            ry: radius,
            cx: 720,
            cy: 540,
            latmax: 80
        )
    }
}

private final class LockedEquirectangularProjectionTestValue<Value>:
    @unchecked Sendable
{
    private let lock = NSLock()
    private var storage: Value

    init(_ value: Value) {
        storage = value
    }

    var value: Value {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func withValue(_ body: (inout Value) -> Void) {
        lock.lock()
        body(&storage)
        lock.unlock()
    }
}
