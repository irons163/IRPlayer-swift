//
//  IRMetalDistortionMeshTests.swift
//  IRPlayer-swiftTests
//
//  Created by Codex on 2026/6/2.
//

import XCTest
@testable import IRPlayer_swift

final class IRMetalDistortionMeshTests: XCTestCase {

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
}
