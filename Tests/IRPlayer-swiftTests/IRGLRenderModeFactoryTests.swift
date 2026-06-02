//
//  IRGLRenderModeFactoryTests.swift
//  IRPlayer-swiftTests
//
//  Created by Codex on 2026/5/24.
//

import CoreGraphics
import XCTest
@testable import IRPlayer_swift

final class IRGLRenderModeFactoryTests: XCTestCase {

    func testFactoryPolicyDescribesNormalAndFisheyeModePlans() {
        XCTAssertEqual(IRGLRenderModeFactoryPolicy.normalModePlan(), [.normal2D])
        XCTAssertEqual(
            IRGLRenderModeFactoryPolicy.fisheyeModePlan(),
            [
                .panorama(name: "Panorama", wideDegreeX: 360, wideDegreeY: 20),
                .fisheye3D(name: "Onelen"),
                .multi4P(name: "Fourlens"),
                .normal2DNamed(name: "Rawdata", shiftEnabled: false)
            ]
        )
    }

    func testNormalModesContainOnly2DModeWithParameter() {
        let parameter = IRMediaParameter(width: 100, height: 50)
        let modes = IRGLRenderModeFactory.createNormalModes(with: parameter)

        XCTAssertEqual(modes.count, 1)
        XCTAssertTrue(modes[0] is IRGLRenderMode2D)
        XCTAssertTrue(modes[0].parameter === parameter)
    }

    func testFisheyeModesHaveExpectedOrderNamesAndDefaults() {
        let parameter = IRMediaParameter(width: 100, height: 50)
        let modes = IRGLRenderModeFactory.createFisheyeModes(with: parameter)

        XCTAssertEqual(modes.map(\.name), ["Panorama", "Onelen", "Fourlens", "Rawdata"])
        XCTAssertTrue(modes[0] is IRGLRenderMode2DFisheye2Pano)
        XCTAssertTrue(modes[1] is IRGLRenderMode3DFisheye)
        XCTAssertTrue(modes[2] is IRGLRenderModeMulti4P)
        XCTAssertTrue(modes[3] is IRGLRenderMode2D)
        XCTAssertTrue(modes.allSatisfy { $0.parameter === parameter })
        XCTAssertEqual(modes[0].contentMode, .scaleAspectFill)
        XCTAssertEqual(modes[0].wideDegreeX, 360)
        XCTAssertEqual(modes[0].wideDegreeY, 20)
        XCTAssertEqual(modes[0].shiftController.panAngle, 180)
        XCTAssertEqual(modes[0].shiftController.tiltAngle, 360)
        XCTAssertEqual(modes[1].shiftController.panAngle, 180)
        XCTAssertEqual(modes[1].shiftController.tiltAngle, 360)
        XCTAssertEqual(modes[2].shiftController.panAngle, 360)
        XCTAssertEqual(modes[2].shiftController.tiltAngle, 360)
        XCTAssertFalse(modes[3].shiftController.enabled)
    }

    func testSpecializedFactoriesAttachParametersAndExpectedShiftAngles() {
        let parameter = IRMediaParameter(width: 320, height: 240)

        let vrMode = IRGLRenderModeFactory.createVRMode(with: parameter)
        XCTAssertTrue(vrMode is IRGLRenderModeVR)
        XCTAssertTrue(vrMode.parameter === parameter)
        XCTAssertEqual(vrMode.shiftController.panAngle, 360)
        XCTAssertEqual(vrMode.shiftController.tiltAngle, 180)

        let distortionMode = IRGLRenderModeFactory.createDistortionMode(with: parameter)
        XCTAssertTrue(distortionMode is IRGLRenderModeDistortion)
        XCTAssertTrue(distortionMode.parameter === parameter)
        XCTAssertEqual(distortionMode.shiftController.panAngle, 360)
        XCTAssertEqual(distortionMode.shiftController.tiltAngle, 180)

        let fisheyeMode = IRGLRenderModeFactory.createFisheyeMode(with: parameter)
        XCTAssertTrue(fisheyeMode is IRGLRenderMode3DFisheye)
        XCTAssertTrue(fisheyeMode.parameter === parameter)
        XCTAssertEqual(fisheyeMode.shiftController.panAngle, 180)
        XCTAssertEqual(fisheyeMode.shiftController.tiltAngle, 360)
    }

    func testPanoramaModeUsesScaleAspectFillAndWideDegrees() {
        let mode = IRGLRenderModeFactory.createPanoramaMode(with: nil)

        XCTAssertTrue(mode is IRGLRenderMode2DFisheye2Pano)
        XCTAssertEqual(mode.contentMode, .scaleAspectFill)
        XCTAssertEqual(mode.wideDegreeX, 360)
        XCTAssertEqual(mode.wideDegreeY, 20)
    }

    func testFisheyeRenderModesIgnoreIncompatibleProgramParameters() {
        let invalidParameter = IRMediaParameter(width: 100, height: 50)

        let fisheyeMode = IRGLRenderMode3DFisheye()
        fisheyeMode.buildIRGLProgram(pixelFormat: .YUV_IRPixelFormat,
                                     viewprotRange: CGRect(x: 0, y: 0, width: 320, height: 240),
                                     parameter: invalidParameter)

        let fourPanelMode = IRGLRenderModeMulti4P()
        fourPanelMode.buildIRGLProgram(pixelFormat: .YUV_IRPixelFormat,
                                       viewprotRange: CGRect(x: 0, y: 0, width: 320, height: 240),
                                       parameter: invalidParameter)

        XCTAssertNil(fisheyeMode.program)
        XCTAssertNil(fourPanelMode.program)
    }
}
