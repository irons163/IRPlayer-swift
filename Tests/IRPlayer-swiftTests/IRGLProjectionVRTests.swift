//
//  IRGLProjectionVRTests.swift
//  IRPlayer-swiftTests
//
//  Created by Codex on 2026/6/2.
//

import XCTest
@testable import IRPlayer_swift

final class IRGLProjectionVRTests: XCTestCase {

    func testStaticPolicyWrappersRemainSourceCompatible() {
        XCTAssertEqual(IRGLProjectionVR.glIndex(0), IRGLProjectionVRPolicy.glIndex(0))
        XCTAssertEqual(IRGLProjectionVR.glIndex(Int(UInt16.max)), IRGLProjectionVRPolicy.glIndex(Int(UInt16.max)))
        XCTAssertEqual(IRGLProjectionVR.glIndex(-1), IRGLProjectionVRPolicy.glIndex(-1))
    }

    func testGLIndexRejectsValuesOutsideUInt16Range() {
        XCTAssertNil(IRGLProjectionVR.glIndex(-1))
        XCTAssertNil(IRGLProjectionVR.glIndex(Int(UInt16.max) + 1))
    }

    func testGLIndexConvertsUInt16RepresentableValues() {
        XCTAssertEqual(IRGLProjectionVR.glIndex(0), 0)
        XCTAssertEqual(IRGLProjectionVR.glIndex(Int(UInt16.max)), UInt16.max)
    }

    func testProjectionExportsGeneratedMesh() throws {
        let projection = IRGLProjectionVR(textureWidth: 1440, height: 1080)

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
        XCTAssertEqual(mesh.indices.prefix(6).map(Int.init), [0, 201, 1, 201, 202, 1])
    }

    func testProjectionNoOpUpdateDrawMethodsRemainCallable() {
        let mediaParameter = IRMediaParameter(width: 640, height: 480)
        let vrProjection = IRGLProjectionVR(textureWidth: 640, height: 480)
        let orthographicProjection = IRGLProjectionOrthographic(textureWidth: 640, height: 480)

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
