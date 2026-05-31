//
//  IRGLProgramFactoryTests.swift
//  IRPlayer-swiftTests
//
//  Created by Codex on 2026/5/24.
//

import CoreGraphics
import XCTest
@testable import IRPlayer_swift

final class IRGLProgramFactoryTests: XCTestCase {

    func testFactoryPolicyExpandsMaximumScaleWithoutChangingDefaults() {
        let range = IRGLScaleRange(minScaleX: 0.5,
                                   minScaleY: 0.75,
                                   maxScaleX: 4,
                                   maxScaleY: 5,
                                   defaultScaleX: 1.25,
                                   defaultScaleY: 1.5)

        let expanded = IRGLProgramFactoryPolicy.expandedScaleRange(from: range, multiplier: 1.5)

        XCTAssertEqual(expanded.minScaleX, 0.5)
        XCTAssertEqual(expanded.minScaleY, 0.75)
        XCTAssertEqual(expanded.maxScaleX, 6)
        XCTAssertEqual(expanded.maxScaleY, 7.5)
        XCTAssertEqual(expanded.defaultScaleX, 1.25)
        XCTAssertEqual(expanded.defaultScaleY, 1.5)
    }

    func testFactoryPolicyClampsFisheyeScopeToParameterLatitude() {
        let range = IRGLScopeRange(minLat: -90,
                                   maxLat: 90,
                                   minLng: -180,
                                   maxLng: 180,
                                   defaultLat: 120,
                                   defaultLng: 20)

        let adjusted = IRGLProgramFactoryPolicy.fisheyeScopeRange(from: range, latmax: 80)

        XCTAssertEqual(adjusted.minLat, -90)
        XCTAssertEqual(adjusted.maxLat, 80)
        XCTAssertEqual(adjusted.minLng, -180)
        XCTAssertEqual(adjusted.maxLng, 180)
        XCTAssertEqual(adjusted.defaultLat, -5)
        XCTAssertEqual(adjusted.defaultLng, 20)
    }

    func testFactoryPolicyAppliesSingleAndFourPanelDefaults() {
        let range = IRGLScopeRange(minLat: -90,
                                   maxLat: 80,
                                   minLng: -180,
                                   maxLng: 180,
                                   defaultLat: -5,
                                   defaultLng: 20)

        XCTAssertEqual(IRGLProgramFactoryPolicy.defaultFisheyeScope(from: range, panelIndex: nil).defaultLng, 90)
        XCTAssertEqual((0..<4).map { IRGLProgramFactoryPolicy.defaultFisheyeScope(from: range, panelIndex: $0).defaultLng },
                       [90, 180, 270, 0])
        XCTAssertEqual(IRGLProgramFactoryPolicy.defaultFisheyeScope(from: range, panelIndex: nil).defaultLat, -40)
    }

    func test2DProgramFactoryAttaches2DControllerAndOrthographicProjection() {
        let parameter = IRMediaParameter(width: 320, height: 180)
        let viewport = CGRect(x: 4, y: 8, width: 160, height: 90)

        let program = IRGLProgramFactory.createIRGLProgram2D(pixelFormat: .YUV_IRPixelFormat,
                                                            viewportRange: viewport,
                                                            parameter: parameter)

        XCTAssertEqual(program.pixelFormat, .YUV_IRPixelFormat)
        XCTAssertTrue(program.parameter === parameter)
        XCTAssertEqual(program.viewprotRange, viewport)
        XCTAssertTrue(program.tramsformController is IRGLTransformController2D)
        XCTAssertTrue(program.mapProjection is IRGLProjectionOrthographic)
    }

    func testPanoramaFactoryExpandsScaleRangeAndUsesOrthographicProjection() {
        let viewport = CGRect(x: 0, y: 0, width: 200, height: 100)

        let program = IRGLProgramFactory.createIRGLProgram2DFisheye2Pano(pixelFormat: .RGB_IRPixelFormat,
                                                                        viewportRange: viewport,
                                                                        parameter: nil)

        XCTAssertTrue(program.tramsformController is IRGLTransformController2D)
        XCTAssertEqual(program.tramsformController?.scaleRange?.maxScaleX, 6)
        XCTAssertEqual(program.tramsformController?.scaleRange?.maxScaleY, 6)
        XCTAssertTrue(program.mapProjection is IRGLProjectionOrthographic)
    }

    func testFisheyeFactoryRejectsIncompatibleParameter() {
        let invalidParameter = IRMediaParameter(width: 320, height: 180)

        let program = IRGLProgramFactory.createIRGLProgram3DFisheye(pixelFormat: .YUV_IRPixelFormat,
                                                                   viewportRange: .zero,
                                                                   parameter: invalidParameter)

        XCTAssertNil(program)
    }

    func testFisheyeFactoryRejectsIncompatibleParameterWithoutDebugOutput() {
        let invalidParameter = IRMediaParameter(width: 320, height: 180)

        let output = captureStandardOutput {
            _ = IRGLProgramFactory.createIRGLProgram3DFisheye(pixelFormat: .YUV_IRPixelFormat,
                                                             viewportRange: .zero,
                                                             parameter: invalidParameter)
        }

        XCTAssertEqual(output, "")
    }

    func testFisheyeFactoryBuildsControllerProjectionAndAdjustedScope() throws {
        let parameter = makeFisheyeParameter()
        let viewport = CGRect(x: 0, y: 0, width: 320, height: 180)

        let program = try XCTUnwrap(IRGLProgramFactory.createIRGLProgram3DFisheye(pixelFormat: .YUV_IRPixelFormat,
                                                                                 viewportRange: viewport,
                                                                                 parameter: parameter))

        XCTAssertTrue(program.parameter === parameter)
        XCTAssertTrue(program.tramsformController is IRGLTransformController3DFisheye)
        XCTAssertTrue(program.mapProjection is IRGLProjectionEquirectangular)
        XCTAssertEqual(program.tramsformController?.scopeRange?.defaultLat, -40)
        XCTAssertEqual(program.tramsformController?.scopeRange?.defaultLng, 90)
    }

    func testFourPanelPerspectiveFactorySplitsViewportIntoQuadrants() {
        let viewport = CGRect(x: 0, y: 0, width: 400, height: 200)

        let program = IRGLProgramFactory.createIRGLProgram2DFisheye2Persp4P(pixelFormat: .RGB_IRPixelFormat,
                                                                           viewportRange: viewport,
                                                                           parameter: nil)

        XCTAssertTrue(program.tramsformController is IRGLTransformController2D)
        XCTAssertEqual(program.programs.count, 4)
        XCTAssertEqual(program.programs.map(\.viewprotRange), [
            CGRect(x: 0, y: 0, width: 200, height: 100),
            CGRect(x: 200, y: 0, width: 200, height: 100),
            CGRect(x: 0, y: 100, width: 200, height: 100),
            CGRect(x: 200, y: 100, width: 200, height: 100)
        ])
    }

    func testFourPanelFisheyeFactoryRejectsIncompatibleParameter() {
        let invalidParameter = IRMediaParameter(width: 320, height: 180)

        let program = IRGLProgramFactory.createIRGLProgram3DFisheye4P(pixelFormat: .YUV_IRPixelFormat,
                                                                     viewportRange: .zero,
                                                                     parameter: invalidParameter)

        XCTAssertNil(program)
    }

    func testFourPanelFisheyeFactoryBuildsChildProgramsWithExpectedScopes() throws {
        let parameter = makeFisheyeParameter()
        let viewport = CGRect(x: 0, y: 0, width: 400, height: 200)

        let program = try XCTUnwrap(IRGLProgramFactory.createIRGLProgram3DFisheye4P(pixelFormat: .YUV_IRPixelFormat,
                                                                                   viewportRange: viewport,
                                                                                   parameter: parameter))

        XCTAssertTrue(program.tramsformController is IRGLTransformController2D)
        XCTAssertEqual(program.programs.count, 4)
        XCTAssertTrue(program.programs.allSatisfy { $0 is IRGLProgram3DFisheye })
        XCTAssertTrue(program.programs.allSatisfy { $0.mapProjection is IRGLProjectionEquirectangular })
        XCTAssertEqual(program.programs.compactMap { $0.tramsformController?.scopeRange?.defaultLat }, [-40, -40, -40, -40])
        XCTAssertEqual(program.programs.compactMap { $0.tramsformController?.scopeRange?.defaultLng }, [90, 180, 270, 0])
    }

    func testVRAndDistortionFactoriesAttachExpectedControllersAndProjection() {
        let viewport = CGRect(x: 0, y: 0, width: 320, height: 180)

        let vrProgram = IRGLProgramFactory.createIRGLProgramVR(pixelFormat: .RGB_IRPixelFormat,
                                                              viewportRange: viewport,
                                                              parameter: nil)
        let distortionProgram = IRGLProgramFactory.createIRGLProgramDistortion(pixelFormat: .RGB_IRPixelFormat,
                                                                               viewportRange: viewport,
                                                                               parameter: nil)

        XCTAssertTrue(vrProgram.tramsformController is IRGLTransformControllerVR)
        XCTAssertEqual(vrProgram.tramsformController?.scaleRange?.maxScaleX, 6)
        XCTAssertTrue(vrProgram.mapProjection is IRGLProjectionVR)
        XCTAssertTrue(distortionProgram.tramsformController is IRGLTransformControllerDistortion)
        XCTAssertEqual(distortionProgram.tramsformController?.scaleRange?.maxScaleY, 6)
        XCTAssertTrue(distortionProgram.mapProjection is IRGLProjectionVR)
    }

    private func makeFisheyeParameter() -> IRFisheyeParameter {
        IRFisheyeParameter(width: 1440,
                           height: 1080,
                           up: false,
                           rx: 520,
                           ry: 520,
                           cx: 720,
                           cy: 540,
                           latmax: 80)
    }
}

final class IRGLProjectionEquirectangularTests: XCTestCase {

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
}

final class IRGLProjectionVRTests: XCTestCase {

    func testGLIndexRejectsValuesOutsideUInt16Range() {
        XCTAssertNil(IRGLProjectionVR.glIndex(-1))
        XCTAssertNil(IRGLProjectionVR.glIndex(Int(UInt16.max) + 1))
    }

    func testGLIndexConvertsUInt16RepresentableValues() {
        XCTAssertEqual(IRGLProjectionVR.glIndex(0), 0)
        XCTAssertEqual(IRGLProjectionVR.glIndex(Int(UInt16.max)), UInt16.max)
    }
}
