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

    func testBufferByteLengthRejectsInvalidOrOverflowingInputs() {
        XCTAssertNil(IRMetalDistortionMesh.bufferByteLength(elementCount: 0, stride: MemoryLayout<UInt16>.stride))
        XCTAssertNil(IRMetalDistortionMesh.bufferByteLength(elementCount: 1, stride: 0))
        XCTAssertNil(IRMetalDistortionMesh.bufferByteLength(elementCount: Int.max, stride: 2))
    }

    func testBufferByteLengthCalculatesStrideStorage() {
        XCTAssertEqual(
            IRMetalDistortionMesh.bufferByteLength(elementCount: 4, stride: MemoryLayout<UInt16>.stride),
            8
        )
    }

    func testBufferByteLengthWrapperMatchesPolicy() {
        XCTAssertEqual(
            IRMetalDistortionMesh.bufferByteLength(elementCount: 4, stride: MemoryLayout<UInt16>.stride),
            IRMetalDistortionMeshPolicy.bufferByteLength(elementCount: 4, stride: MemoryLayout<UInt16>.stride)
        )
        XCTAssertNil(IRMetalDistortionMeshPolicy.bufferByteLength(elementCount: 0, stride: MemoryLayout<UInt16>.stride))
    }

    func testIndexValueRejectsValuesOutsideUInt16Range() {
        XCTAssertNil(IRMetalDistortionMesh.indexValue(-1))
        XCTAssertNil(IRMetalDistortionMesh.indexValue(Int(UInt16.max) + 1))
    }

    func testIndexValueConvertsUInt16RepresentableValues() {
        XCTAssertEqual(IRMetalDistortionMesh.indexValue(0), 0)
        XCTAssertEqual(IRMetalDistortionMesh.indexValue(Int(UInt16.max)), UInt16.max)
    }

    func testIndexValueWrapperMatchesPolicy() {
        XCTAssertEqual(IRMetalDistortionMesh.indexValue(0), IRMetalDistortionMeshPolicy.indexValue(0))
        XCTAssertEqual(IRMetalDistortionMesh.indexValue(Int(UInt16.max)), IRMetalDistortionMeshPolicy.indexValue(Int(UInt16.max)))
        XCTAssertNil(IRMetalDistortionMeshPolicy.indexValue(-1))
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
