//
//  IRMetalDistortionMeshTests.swift
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

final class IRMetalDistortionMeshTests: XCTestCase {

    private func makeMetalDevice() throws -> MTLDevice {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("Metal device unavailable")
        }
        return device
    }

    func testInitBuildsLeftAndRightDistortionMeshes() throws {
        let device = try makeMetalDevice()

        let left = try XCTUnwrap(IRMetalDistortionMesh(device: device, modelType: .left))
        let right = try XCTUnwrap(IRMetalDistortionMesh(device: device, modelType: .right))

        XCTAssertEqual(left.indexCount, 3158)
        XCTAssertEqual(right.indexCount, 3158)
        XCTAssertGreaterThan(left.vertexBuffer.length, 0)
        XCTAssertGreaterThan(left.indexBuffer.length, 0)
        XCTAssertGreaterThan(right.vertexBuffer.length, 0)
        XCTAssertGreaterThan(right.indexBuffer.length, 0)
    }

    func testMeshVignettePreservesInteriorAndFadesEdges() throws {
        let device = try makeMetalDevice()
        let mesh = try XCTUnwrap(
            IRMetalDistortionMesh(device: device, modelType: .left)
        )
        let vertexCount = mesh.vertexBuffer.length
            / MemoryLayout<IRMetalDistortionVertex>.stride
        XCTAssertEqual(vertexCount, 1_600)

        let vertices = mesh.vertexBuffer.contents().bindMemory(
            to: IRMetalDistortionVertex.self,
            capacity: vertexCount
        )
        let center = vertices[20 * 40 + 20]
        XCTAssertEqual(center.vignette, 1, accuracy: 0.0001)
        XCTAssertEqual(vertices[0].vignette, 0, accuracy: 0.0001)
        XCTAssertEqual(vertices[39].vignette, 0, accuracy: 0.0001)
        XCTAssertEqual(vertices[39 * 40].vignette, 0, accuracy: 0.0001)
        XCTAssertEqual(
            vertices[39 * 40 + 39].vignette,
            0,
            accuracy: 0.0001
        )
    }

    func testBlueDistortionInverseConvergesToExpectedRadii() throws {
        let cases: [(radius: Float, expected: Float)] = [
            (0, 0),
            (0.1, 0.09956324),
            (0.25, 0.24349949),
            (0.5, 0.4553191),
            (1, 0.76337785),
            (1.5, 0.9677977)
        ]

        for testCase in cases {
            let result = try XCTUnwrap(
                IRMetalDistortionMesh.invertedBlueRadius(
                    testCase.radius
                )
            )
            XCTAssertEqual(
                result,
                testCase.expected,
                accuracy: 0.0001
            )
        }
    }

    func testBlueDistortionInverseRejectsInvalidAndOverflowingRadii() {
        XCTAssertNil(
            IRMetalDistortionMesh.invertedBlueRadius(-1)
        )
        XCTAssertNil(
            IRMetalDistortionMesh.invertedBlueRadius(.nan)
        )
        XCTAssertNil(
            IRMetalDistortionMesh.invertedBlueRadius(.infinity)
        )
        XCTAssertNil(
            IRMetalDistortionMesh.invertedBlueRadius(
                .greatestFiniteMagnitude
            )
        )
    }
}
