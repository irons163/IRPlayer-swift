//
//  IRMetalFisheyeMeshTests.swift
//  IRPlayer-swiftTests
//
//  Created by Codex on 2026/6/2.
//

import XCTest
#if SWIFT_PACKAGE
@testable import IRPlayerSwift
#else
@testable import IRPlayer_swift
#endif

final class IRMetalFisheyeMeshTests: XCTestCase {

    private func makeMetalDevice() throws -> MTLDevice {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("Metal device unavailable")
        }
        return device
    }

    func testResolveParamsRejectsInvalidTextureDimensions() {
        let params = IRMetalFisheyeMesh.resolveParameters(
            textureWidth: 0,
            textureHeight: 100,
            centerX: 20,
            centerY: 20,
            radius: 10
        )

        XCTAssertEqual(params.textureWidth, 0)
        XCTAssertEqual(params.textureHeight, 0)
        XCTAssertEqual(params.centerX, 0)
        XCTAssertEqual(params.centerY, 0)
        XCTAssertEqual(params.radius, 0)
    }

    func testResolveParamsRejectsNonFiniteGeometry() {
        let params = IRMetalFisheyeMesh.resolveParameters(
            textureWidth: .infinity,
            textureHeight: 100,
            centerX: 20,
            centerY: 20,
            radius: .nan
        )

        XCTAssertEqual(params.textureWidth, 0)
        XCTAssertEqual(params.textureHeight, 0)
        XCTAssertEqual(params.centerX, 0)
        XCTAssertEqual(params.centerY, 0)
        XCTAssertEqual(params.radius, 0)
    }

    func testResolveParamsPreservesValidGeometry() {
        let params = IRMetalFisheyeMesh.resolveParameters(
            textureWidth: 200,
            textureHeight: 100,
            centerX: 60,
            centerY: 50,
            radius: 40
        )

        XCTAssertEqual(params.textureWidth, 200)
        XCTAssertEqual(params.textureHeight, 100)
        XCTAssertEqual(params.centerX, 60)
        XCTAssertEqual(params.centerY, 50)
        XCTAssertEqual(params.radius, 40)
    }

    func testResolveParamsFallsBackWhenGeometryCannotFitTexture() {
        let params = IRMetalFisheyeMesh.resolveParameters(
            textureWidth: 200,
            textureHeight: 100,
            centerX: 180,
            centerY: 50,
            radius: 40
        )

        XCTAssertEqual(params.textureWidth, 200)
        XCTAssertEqual(params.textureHeight, 100)
        XCTAssertEqual(params.centerX, 100)
        XCTAssertEqual(params.centerY, 50)
        XCTAssertEqual(params.radius, 50)
    }

    func testResolveParamsFallsBackForOffTextureCircle() {
        let cases: [(Float, Float, Float)] = [
            (-1, 50, 20),
            (100, -1, 20),
            (20, 50, -1),
            (20, 50, 40),
            (100, 20, 40),
            (201, 50, 20),
            (100, 101, 20)
        ]

        for (centerX, centerY, radius) in cases {
            XCTAssertEqual(
                IRMetalFisheyeMesh.resolveParameters(
                    textureWidth: 200,
                    textureHeight: 100,
                    centerX: centerX,
                    centerY: centerY,
                    radius: radius
                ),
                .init(
                    textureWidth: 200,
                    textureHeight: 100,
                    centerX: 100,
                    centerY: 50,
                    radius: 50
                )
            )
        }
    }

    func testResolveParamsAvoidsCircleAdditionOverflow() {
        let params = IRMetalFisheyeMesh.resolveParameters(
            textureWidth: .greatestFiniteMagnitude,
            textureHeight: 100,
            centerX: .greatestFiniteMagnitude,
            centerY: 50,
            radius: .greatestFiniteMagnitude
        )

        XCTAssertEqual(
            params.centerX,
            Float.greatestFiniteMagnitude / 2
        )
        XCTAssertEqual(params.centerY, 50)
        XCTAssertEqual(params.radius, 50)
    }

    func testExplicitInitRejectsMismatchedOrEmptyGeometry() throws {
        let device = try makeMetalDevice()

        XCTAssertNil(IRMetalFisheyeMesh(device: device,
                                        positions: [SIMD3<Float>(0, 0, 0)],
                                        texcoords: [],
                                        indices: [0]))
        XCTAssertNil(IRMetalFisheyeMesh(device: device,
                                        positions: [],
                                        texcoords: [],
                                        indices: [0]))
        XCTAssertNil(IRMetalFisheyeMesh(device: device,
                                        positions: [SIMD3<Float>(0, 0, 0)],
                                        texcoords: [SIMD2<Float>(0, 0)],
                                        indices: []))
    }

    func testExplicitInitBuildsBuffersForValidGeometry() throws {
        let device = try makeMetalDevice()

        let mesh = try XCTUnwrap(
            IRMetalFisheyeMesh(device: device,
                               positions: [
                                SIMD3<Float>(-1, -1, 0),
                                SIMD3<Float>(1, -1, 0),
                                SIMD3<Float>(0, 1, 0)
                               ],
                               texcoords: [
                                SIMD2<Float>(0, 0),
                                SIMD2<Float>(1, 0),
                                SIMD2<Float>(0.5, 1)
                               ],
                               indices: [0, 1, 2])
        )

        XCTAssertEqual(mesh.indexCount, 3)
        XCTAssertGreaterThan(mesh.vertexBuffer.length, 0)
        XCTAssertGreaterThan(mesh.indexBuffer.length, 0)
    }

    func testTextureGeometryInitRejectsInvalidResolvedParams() throws {
        let device = try makeMetalDevice()

        XCTAssertNil(IRMetalFisheyeMesh(device: device,
                                        textureWidth: 0,
                                        textureHeight: 100,
                                        centerX: 50,
                                        centerY: 50,
                                        radius: 20))
    }

    func testTextureGeometryInitBuildsSphereMesh() throws {
        let device = try makeMetalDevice()

        let mesh = try XCTUnwrap(
            IRMetalFisheyeMesh(device: device,
                               textureWidth: 200,
                               textureHeight: 100,
                               centerX: 100,
                               centerY: 50,
                               radius: 40)
        )

        XCTAssertEqual(mesh.indexCount, 194400)
        XCTAssertGreaterThan(mesh.vertexBuffer.length, 0)
        XCTAssertGreaterThan(mesh.indexBuffer.length, 0)
    }
}
