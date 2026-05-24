//
//  IRGLRenderModeBuildTests.swift
//  IRPlayer-swiftTests
//
//  Created by Codex on 2026/5/24.
//

import CoreGraphics
import XCTest
@testable import IRPlayer_swift

final class IRGLRenderModeBuildTests: XCTestCase {

    func testBuildProgramWiresProgramShiftControllerAndDelegate() throws {
        let mode = IRGLRenderMode2D()
        let delegate = RecordingRenderModeDelegate()
        let viewport = CGRect(x: 10, y: 20, width: 320, height: 180)
        mode.delegate = delegate

        mode.buildIRGLProgram(pixelFormat: .YUV_IRPixelFormat,
                              viewprotRange: viewport,
                              parameter: nil)

        let program = try XCTUnwrap(mode.program)
        XCTAssertEqual(program.pixelFormat, .YUV_IRPixelFormat)
        XCTAssertEqual(program.viewprotRange, viewport)
        XCTAssertTrue(mode.shiftController.program === program)
        XCTAssertTrue(delegate.createdPrograms.last === program)
    }

    func testBuildProgramAppliesQueuedConfigurationInOrder() throws {
        let mode = IRGLRenderMode2D()
        let scaleRange = IRGLScaleRange(minScaleX: 0.5,
                                        minScaleY: 0.75,
                                        maxScaleX: 8,
                                        maxScaleY: 9,
                                        defaultScaleX: 1,
                                        defaultScaleY: 1)
        let scopeRange = IRGLScopeRange(minLat: -10,
                                        maxLat: 10,
                                        minLng: -20,
                                        maxLng: 20,
                                        defaultLat: 3,
                                        defaultLng: 4)

        mode.scaleRange = scaleRange
        mode.defaultScale = 2.5
        mode.scopeRange = scopeRange
        mode.contentMode = .scaleAspectFill

        mode.buildIRGLProgram(pixelFormat: .RGB_IRPixelFormat,
                              viewprotRange: CGRect(x: 0, y: 0, width: 100, height: 50),
                              parameter: nil)

        let program = try XCTUnwrap(mode.program)
        let controller = try XCTUnwrap(program.tramsformController)
        let appliedScaleRange = try XCTUnwrap(controller.scaleRange)
        let appliedScopeRange = try XCTUnwrap(controller.scopeRange)

        XCTAssertEqual(program.contentMode, .scaleAspectFill)
        XCTAssertEqual(appliedScaleRange.minScaleX, 0.5)
        XCTAssertEqual(appliedScaleRange.minScaleY, 0.75)
        XCTAssertEqual(appliedScaleRange.maxScaleX, 8)
        XCTAssertEqual(appliedScaleRange.maxScaleY, 9)
        XCTAssertEqual(appliedScaleRange.defaultScaleX, 2.5)
        XCTAssertEqual(appliedScaleRange.defaultScaleY, 2.5)
        XCTAssertTrue(appliedScopeRange === scopeRange)
    }

    func testBuildProgramClearsProgramAndShiftControllerWhenFactoryRejectsParameter() {
        let mode = IRGLRenderMode3DFisheye()
        let invalidParameter = IRMediaParameter(width: 320, height: 180)

        mode.buildIRGLProgram(pixelFormat: .YUV_IRPixelFormat,
                              viewprotRange: .zero,
                              parameter: invalidParameter)

        XCTAssertNil(mode.program)
        XCTAssertNil(mode.shiftController.program)
    }

    func test2DModeLiveConfigurationUpdatesBuiltProgram() throws {
        let mode = IRGLRenderMode2D()
        mode.scaleRange = IRGLScaleRange(minScaleX: 0.5,
                                         minScaleY: 0.75,
                                         maxScaleX: 8,
                                         maxScaleY: 9,
                                         defaultScaleX: 1,
                                         defaultScaleY: 1)
        mode.buildIRGLProgram(pixelFormat: .RGB_IRPixelFormat,
                              viewprotRange: CGRect(x: 0, y: 0, width: 200, height: 100),
                              parameter: nil)

        mode.contentMode = .scaleToFill
        mode.defaultScale = 3.25

        let program = try XCTUnwrap(mode.program)
        let scaleRange = try XCTUnwrap(program.tramsformController?.scaleRange)
        XCTAssertEqual(program.contentMode, .scaleToFill)
        XCTAssertEqual(scaleRange.defaultScaleX, 3.25)
        XCTAssertEqual(scaleRange.defaultScaleY, 3.25)
        XCTAssertEqual(scaleRange.minScaleX, 0.5)
        XCTAssertEqual(scaleRange.minScaleY, 0.75)
        XCTAssertEqual(scaleRange.maxScaleX, 8)
        XCTAssertEqual(scaleRange.maxScaleY, 9)
    }
}

private final class RecordingRenderModeDelegate: IRGLRenderModeDelegate {
    private(set) var createdPrograms: [IRGLProgram2D] = []

    func programDidCreate(_ program: IRGLProgram2D) {
        createdPrograms.append(program)
    }
}
