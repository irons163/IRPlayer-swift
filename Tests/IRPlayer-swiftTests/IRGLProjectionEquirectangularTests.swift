//
//  IRGLProjectionEquirectangularTests.swift
//  IRPlayer-swiftTests
//
//  Created by Codex on 2026/6/2.
//

import XCTest
@testable import IRPlayer_swift

final class IRGLProjectionEquirectangularTests: XCTestCase {

    func testStaticPolicyWrappersRemainSourceCompatible() {
        let wrapperPlan = IRGLProjectionEquirectangular.bufferPlan(slices: 4, indicesPerVertex: 1)
        let policyPlan = IRGLProjectionEquirectangularPolicy.bufferPlan(slices: 4, indicesPerVertex: 1)
        XCTAssertEqual(wrapperPlan?.iMax, policyPlan?.iMax)
        XCTAssertEqual(wrapperPlan?.vertexCount, policyPlan?.vertexCount)
        XCTAssertEqual(wrapperPlan?.vertexCapacity, policyPlan?.vertexCapacity)
        XCTAssertEqual(wrapperPlan?.vectorCapacity, policyPlan?.vectorCapacity)
        XCTAssertEqual(wrapperPlan?.totalIndices, policyPlan?.totalIndices)

        var values = [3, 7, 2]
        let count = values.count
        values.withUnsafeMutableBufferPointer { buffer in
            XCTAssertEqual(
                IRGLProjectionEquirectangular.maxItem(in: buffer.baseAddress, size: count),
                IRGLProjectionEquirectangularPolicy.maxItem(in: buffer.baseAddress, size: count)
            )
        }
        XCTAssertEqual(
            IRGLProjectionEquirectangular.elementCount(baseCount: 4, components: 3),
            IRGLProjectionEquirectangularPolicy.elementCount(baseCount: 4, components: 3)
        )
        XCTAssertEqual(
            IRGLProjectionEquirectangular.byteCount(elementCount: 4, stride: MemoryLayout<Float>.stride),
            IRGLProjectionEquirectangularPolicy.byteCount(elementCount: 4, stride: MemoryLayout<Float>.stride)
        )
        XCTAssertEqual(
            IRGLProjectionEquirectangular.indexValue(Int(Int16.max)),
            IRGLProjectionEquirectangularPolicy.indexValue(Int(Int16.max))
        )
    }

    func testElementCountRejectsInvalidOrOverflowingInputs() {
        XCTAssertNil(IRGLProjectionEquirectangular.elementCount(baseCount: 0, components: 3))
        XCTAssertNil(IRGLProjectionEquirectangular.elementCount(baseCount: 1, components: 0))
        XCTAssertNil(IRGLProjectionEquirectangular.elementCount(baseCount: Int.max, components: 2))
    }

    func testElementCountCalculatesComponentStorage() {
        XCTAssertEqual(IRGLProjectionEquirectangular.elementCount(baseCount: 4, components: 3), 12)
    }

    func testByteCountRejectsInvalidOrOverflowingInputs() {
        XCTAssertNil(IRGLProjectionEquirectangular.byteCount(elementCount: 0, stride: MemoryLayout<Float>.stride))
        XCTAssertNil(IRGLProjectionEquirectangular.byteCount(elementCount: 1, stride: 0))
        XCTAssertNil(IRGLProjectionEquirectangular.byteCount(elementCount: Int.max, stride: 2))
    }

    func testByteCountCalculatesStrideStorage() {
        XCTAssertEqual(
            IRGLProjectionEquirectangular.byteCount(elementCount: 4, stride: MemoryLayout<Float>.stride),
            16
        )
    }

    func testMaxItemRejectsMissingOrEmptyInputs() {
        XCTAssertNil(IRGLProjectionEquirectangular.maxItem(in: nil, size: 1))

        var values = [1, 2, 3]
        values.withUnsafeMutableBufferPointer { buffer in
            XCTAssertNil(IRGLProjectionEquirectangular.maxItem(in: buffer.baseAddress, size: 0))
        }
    }

    func testMaxItemReturnsLargestValue() {
        var values = [3, 7, 2]
        let count = values.count
        values.withUnsafeMutableBufferPointer { buffer in
            XCTAssertEqual(IRGLProjectionEquirectangular.maxItem(in: buffer.baseAddress, size: count), 7)
        }
    }

    func testIndexValueRejectsValuesOutsideInt16Range() {
        XCTAssertNil(IRGLProjectionEquirectangular.indexValue(Int(Int16.min) - 1))
        XCTAssertNil(IRGLProjectionEquirectangular.indexValue(Int(Int16.max) + 1))
    }

    func testIndexValueConvertsInt16RepresentableValues() {
        XCTAssertEqual(IRGLProjectionEquirectangular.indexValue(0), 0)
        XCTAssertEqual(IRGLProjectionEquirectangular.indexValue(Int(Int16.max)), Int16.max)
    }

    func testInvalidProjectionParametersFallBackWithoutDebugOutput() {
        let output = captureStandardOutput {
            _ = IRGLProjectionEquirectangular(textureWidth: 1440,
                                              height: 1080,
                                              centerX: 720,
                                              centerY: 540,
                                              radius: 0)
        }

        XCTAssertEqual(output, "")
    }

    func testProjectionRejectsInvalidBufferParametersWithoutDebugOutput() {
        let output = captureStandardOutput {
            let projection = IRGLProjectionEquirectangular(textureWidth: 0,
                                                          height: 0,
                                                          centerX: 1,
                                                          centerY: 1,
                                                          radius: 1)

            XCTAssertNil(projection.exportMesh())
        }

        XCTAssertEqual(output, "")
    }

    func testBufferPlanRejectsOverflowWithoutDebugOutput() {
        let output = captureStandardOutput {
            XCTAssertNil(IRGLProjectionEquirectangular.bufferPlan(slices: Int.max, indicesPerVertex: 1))
            XCTAssertNil(IRGLProjectionEquirectangular.bufferPlan(slices: 3_037_000_499, indicesPerVertex: 1))
        }

        XCTAssertEqual(output, "")
    }

    func testProjectionExportMeshSurvivesParameterUpdate() throws {
        let projection = IRGLProjectionEquirectangular(textureWidth: 1440, height: 1080, centerX: 720, centerY: 540, radius: 520)
        let firstMesh = try XCTUnwrap(projection.exportMesh())

        projection.update(with: IRFisheyeParameter(width: 1440,
                                                   height: 1080,
                                                   up: false,
                                                   rx: 500,
                                                   ry: 500,
                                                   cx: 720,
                                                   cy: 540,
                                                   latmax: 80))
        let updatedMesh = try XCTUnwrap(projection.exportMesh())

        XCTAssertEqual(firstMesh.positions.count, updatedMesh.positions.count)
        XCTAssertEqual(firstMesh.texcoords.count, updatedMesh.texcoords.count)
        XCTAssertEqual(firstMesh.indices.count, updatedMesh.indices.count)
        XCTAssertFalse(updatedMesh.positions.isEmpty)
        XCTAssertFalse(updatedMesh.texcoords.isEmpty)
        XCTAssertFalse(updatedMesh.indices.isEmpty)
    }

    func testProjectionNoOpUpdateAndDrawKeepMeshAvailable() throws {
        let projection = IRGLProjectionEquirectangular(textureWidth: 1440,
                                                      height: 1080,
                                                      centerX: 720,
                                                      centerY: 540,
                                                      radius: 520)

        projection.updateVertex()
        projection.draw()

        let mesh = try XCTUnwrap(projection.exportMesh())
        XCTAssertFalse(mesh.positions.isEmpty)
        XCTAssertFalse(mesh.texcoords.isEmpty)
        XCTAssertFalse(mesh.indices.isEmpty)
    }
}
