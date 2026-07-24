//
//  IRMetalDistortionMeshTests.swift
//  IRPlayer-swiftTests
//
//  Created by Codex on 2026/6/2.
//

import XCTest
@testable import IRPlayer_swift

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
}
