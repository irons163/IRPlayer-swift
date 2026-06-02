//
//  IRMetalFisheyeMeshTests.swift
//  IRPlayer-swiftTests
//
//  Created by Codex on 2026/6/2.
//

import XCTest
@testable import IRPlayer_swift

final class IRMetalFisheyeMeshTests: XCTestCase {

    func testBufferByteLengthRejectsInvalidOrOverflowingInputs() {
        XCTAssertNil(IRMetalFisheyeMesh.bufferByteLength(elementCount: 0, stride: MemoryLayout<UInt16>.stride))
        XCTAssertNil(IRMetalFisheyeMesh.bufferByteLength(elementCount: 1, stride: 0))
        XCTAssertNil(IRMetalFisheyeMesh.bufferByteLength(elementCount: Int.max, stride: 2))
    }

    func testBufferByteLengthCalculatesStrideStorage() {
        XCTAssertEqual(
            IRMetalFisheyeMesh.bufferByteLength(elementCount: 4, stride: MemoryLayout<UInt16>.stride),
            8
        )
    }

    func testBufferByteLengthWrapperMatchesPolicy() {
        XCTAssertEqual(
            IRMetalFisheyeMesh.bufferByteLength(elementCount: 4, stride: MemoryLayout<UInt16>.stride),
            IRMetalFisheyeMeshPolicy.bufferByteLength(elementCount: 4, stride: MemoryLayout<UInt16>.stride)
        )
        XCTAssertNil(IRMetalFisheyeMeshPolicy.bufferByteLength(elementCount: 0, stride: MemoryLayout<UInt16>.stride))
    }

    func testIndexValueRejectsValuesOutsideUInt16Range() {
        XCTAssertNil(IRMetalFisheyeMesh.indexValue(-1))
        XCTAssertNil(IRMetalFisheyeMesh.indexValue(Int(UInt16.max) + 1))
    }

    func testIndexValueConvertsUInt16RepresentableValues() {
        XCTAssertEqual(IRMetalFisheyeMesh.indexValue(0), 0)
        XCTAssertEqual(IRMetalFisheyeMesh.indexValue(Int(UInt16.max)), UInt16.max)
    }

    func testIndexValueWrapperMatchesPolicy() {
        XCTAssertEqual(IRMetalFisheyeMesh.indexValue(0), IRMetalFisheyeMeshPolicy.indexValue(0))
        XCTAssertEqual(IRMetalFisheyeMesh.indexValue(Int(UInt16.max)), IRMetalFisheyeMeshPolicy.indexValue(Int(UInt16.max)))
        XCTAssertNil(IRMetalFisheyeMeshPolicy.indexValue(-1))
    }

    func testResolveParamsRejectsInvalidTextureDimensions() {
        let params = IRMetalFisheyeMesh.resolveParams(textureWidth: 0, textureHeight: 100, centerX: 20, centerY: 20, radius: 10)

        XCTAssertEqual(params.textureWidth, 0)
        XCTAssertEqual(params.textureHeight, 0)
        XCTAssertEqual(params.centerX, 0)
        XCTAssertEqual(params.centerY, 0)
        XCTAssertEqual(params.radius, 0)
    }

    func testResolveParamsRejectsNonFiniteGeometry() {
        let params = IRMetalFisheyeMeshPolicy.resolveParams(textureWidth: .infinity,
                                                            textureHeight: 100,
                                                            centerX: 20,
                                                            centerY: 20,
                                                            radius: .nan)

        XCTAssertEqual(params.textureWidth, 0)
        XCTAssertEqual(params.textureHeight, 0)
        XCTAssertEqual(params.centerX, 0)
        XCTAssertEqual(params.centerY, 0)
        XCTAssertEqual(params.radius, 0)
    }

    func testResolveParamsPreservesValidGeometry() {
        let params = IRMetalFisheyeMesh.resolveParams(textureWidth: 200, textureHeight: 100, centerX: 60, centerY: 50, radius: 40)

        XCTAssertEqual(params.textureWidth, 200)
        XCTAssertEqual(params.textureHeight, 100)
        XCTAssertEqual(params.centerX, 60)
        XCTAssertEqual(params.centerY, 50)
        XCTAssertEqual(params.radius, 40)
    }

    func testResolveParamsFallsBackWhenGeometryCannotFitTexture() {
        let params = IRMetalFisheyeMesh.resolveParams(textureWidth: 200, textureHeight: 100, centerX: 180, centerY: 50, radius: 40)

        XCTAssertEqual(params.textureWidth, 200)
        XCTAssertEqual(params.textureHeight, 100)
        XCTAssertEqual(params.centerX, 100)
        XCTAssertEqual(params.centerY, 50)
        XCTAssertEqual(params.radius, 50)
    }

    func testResolveParamsWrapperMatchesPolicy() {
        let wrapper = IRMetalFisheyeMesh.resolveParams(textureWidth: 200, textureHeight: 100, centerX: 180, centerY: 50, radius: 40)
        let policy = IRMetalFisheyeMeshPolicy.resolveParams(textureWidth: 200, textureHeight: 100, centerX: 180, centerY: 50, radius: 40)

        XCTAssertEqual(wrapper.textureWidth, policy.textureWidth)
        XCTAssertEqual(wrapper.textureHeight, policy.textureHeight)
        XCTAssertEqual(wrapper.centerX, policy.centerX)
        XCTAssertEqual(wrapper.centerY, policy.centerY)
        XCTAssertEqual(wrapper.radius, policy.radius)
    }
}
