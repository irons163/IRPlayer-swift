//
//  IRGLProjectionVRTests.swift
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

final class IRGLProjectionVRTests: XCTestCase {
    func testVRPlanValidatesCountsAndUInt16Capacity() throws {
        XCTAssertNil(
            IRGLProjectionMeshBuilder.vrPlan(
                slices: 0,
                parallels: 1
            )
        )
        XCTAssertNil(
            IRGLProjectionMeshBuilder.vrPlan(
                slices: Int.max,
                parallels: 2
            )
        )
        XCTAssertNil(
            IRGLProjectionMeshBuilder.vrPlan(
                slices: 256,
                parallels: 256
            )
        )

        let plan = try XCTUnwrap(
            IRGLProjectionMeshBuilder.vrPlan(
                slices: 200,
                parallels: 100
            )
        )
        XCTAssertEqual(plan.rowLength, 201)
        XCTAssertEqual(plan.vertexCount, 20_301)
        XCTAssertEqual(plan.indexCount, 120_000)
    }

    func testUInt16IndexRequiresExistingRepresentableVertex() {
        XCTAssertNil(
            IRGLProjectionMeshBuilder.uint16Index(
                -1,
                vertexCount: 10
            )
        )
        XCTAssertNil(
            IRGLProjectionMeshBuilder.uint16Index(
                10,
                vertexCount: 10
            )
        )
        XCTAssertNil(
            IRGLProjectionMeshBuilder.uint16Index(
                Int(UInt16.max) + 1,
                vertexCount: Int(UInt16.max) + 2
            )
        )
        XCTAssertEqual(
            IRGLProjectionMeshBuilder.uint16Index(
                Int(UInt16.max),
                vertexCount: Int(UInt16.max) + 1
            ),
            UInt16.max
        )
    }

    func testProjectionExportsGeneratedMesh() throws {
        let projection = IRGLProjectionVR(
            textureWidth: 1440,
            height: 1080
        )

        let mesh = try XCTUnwrap(projection.exportMesh())

        XCTAssertEqual(projection.vertex_count, 20_301)
        XCTAssertEqual(projection.index_count, 120_000)
        XCTAssertEqual(mesh.positions.count, projection.vertex_count)
        XCTAssertEqual(mesh.texcoords.count, projection.vertex_count)
        XCTAssertEqual(mesh.indices.count, projection.index_count)
        XCTAssertEqual(mesh.positions[0].x, 0, accuracy: 0.0001)
        XCTAssertEqual(mesh.positions[0].y, 1, accuracy: 0.0001)
        XCTAssertEqual(mesh.positions[0].z, 0, accuracy: 0.0001)
        XCTAssertEqual(mesh.texcoords[0].x, 0, accuracy: 0.0001)
        XCTAssertEqual(mesh.texcoords[0].y, 1, accuracy: 0.0001)
        XCTAssertEqual(
            mesh.indices.prefix(6).map(Int.init),
            [0, 201, 1, 201, 202, 1]
        )
    }

    func testConcurrentInstancesExportOneCoherentSharedMesh() {
        let invalidExports = LockedVRProjectionTestValue(0)

        DispatchQueue.concurrentPerform(iterations: 200) { _ in
            let projection = IRGLProjectionVR(
                textureWidth: 640,
                height: 480
            )
            guard let mesh = projection.exportMesh(),
                  mesh.positions.count == 20_301,
                  mesh.texcoords.count == 20_301,
                  mesh.indices.count == 120_000,
                  mesh.indices.first == 0,
                  mesh.indices.last == 20_099 else {
                invalidExports.withValue { $0 += 1 }
                return
            }
        }

        XCTAssertEqual(invalidExports.value, 0)
    }

    func testExportedSnapshotRemainsStableAcrossInstances() throws {
        let firstProjection = IRGLProjectionVR(
            textureWidth: 1,
            height: 1
        )
        let first = try XCTUnwrap(firstProjection.exportMesh())
        let retainedPrefix = Array(first.indices.prefix(12))

        for _ in 0..<20 {
            _ = IRGLProjectionVR(
                textureWidth: 3840,
                height: 2160
            ).exportMesh()
        }

        XCTAssertEqual(Array(first.indices.prefix(12)), retainedPrefix)
        XCTAssertEqual(first.positions.count, 20_301)
    }

    func testProjectionNoOpUpdateDrawMethodsRemainCallable() {
        let mediaParameter = IRMediaParameter(width: 640, height: 480)
        let vrProjection = IRGLProjectionVR(
            textureWidth: 640,
            height: 480
        )
        let orthographicProjection = IRGLProjectionOrthographic(
            textureWidth: 640,
            height: 480
        )

        vrProjection.update(with: mediaParameter)
        vrProjection.updateVertex()
        vrProjection.draw()
        orthographicProjection.update(with: mediaParameter)
        orthographicProjection.updateVertex()
        orthographicProjection.draw()

        XCTAssertEqual(vrProjection.vertex_count, 20_301)
        XCTAssertEqual(vrProjection.index_count, 120_000)
    }
}

private final class LockedVRProjectionTestValue<Value>:
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
