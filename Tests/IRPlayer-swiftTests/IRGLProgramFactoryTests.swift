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
