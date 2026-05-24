//
//  IRPlayer_swiftTests.swift
//  IRPlayer-swiftTests
//
//  Created by Phil Chang on 2022/4/11.
//  Copyright © 2022 Phil. All rights reserved.
//

import AVFoundation
import CoreGraphics
import IRFFMpeg
import simd
import XCTest
@testable import IRPlayer_swift

final class IRFFToolsTests: XCTestCase {

    func testFFLogIgnoresInvalidUTF8FormatString() throws {
        let invalidFormat: [CChar] = [-1, 0]

        try invalidFormat.withUnsafeBufferPointer { formatBuffer in
            let format = try XCTUnwrap(formatBuffer.baseAddress)
            withVaList([]) { args in
                IRFFLog(context: nil, level: 0, format: format, args: args)
            }
        }
    }

    func testStreamTimebaseFallsBackToFiniteValueForInvalidStreamAndDefault() {
        var stream = AVStream()
        stream.time_base = AVRational(num: 0, den: 0)

        let timebase = withUnsafePointer(to: &stream) { streamPointer in
            IRFFStreamGetTimebase(streamPointer, defaultTimebase: 0)
        }

        XCTAssertEqual(timebase, 1)
        XCTAssertTrue(timebase.isFinite)
    }

    func testStreamFPSFallsBackToFiniteValueForInvalidRatesAndTimebase() {
        var stream = AVStream()
        stream.avg_frame_rate = AVRational(num: 0, den: 0)
        stream.r_frame_rate = AVRational(num: 0, den: 0)

        let fps = withUnsafePointer(to: &stream) { streamPointer in
            IRFFStreamGetFPS(streamPointer, timebase: 0)
        }

        XCTAssertEqual(fps, 1)
        XCTAssertTrue(fps.isFinite)
    }
}

final class IRGLProgram2DFisheye2PanoTests: XCTestCase {

    func testTextureSizeRejectsMissingParamsAndReturnsExistingDimensions() {
        XCTAssertNil(IRGLProgram2DFisheye2Pano.textureSize(from: nil))

        let params = IRGLFish2PanoShaderParams()
        params.textureWidth = 1920
        params.textureHeight = 960

        let size = IRGLProgram2DFisheye2Pano.textureSize(from: params)
        XCTAssertEqual(size?.width, 1920)
        XCTAssertEqual(size?.height, 960)
    }
}

final class IRGLGestureControllerTests: XCTestCase {

    func testClearingCurrentModeClearsSmoothScrollMode() {
        let view = IRGLView(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        let smoothScroll = IRSmoothScrollController(targetView: view)
        let gestureController = IRGLGestureController()

        gestureController.smoothScroll = smoothScroll
        gestureController.currentMode = IRGLRenderMode2D()

        gestureController.currentMode = nil

        XCTAssertNil(smoothScroll.currentMode)
        withExtendedLifetime(smoothScroll) {}
    }

    func testAddGestureReplacesExistingRotationGestureRecognizer() {
        let view = IRGLView(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        let gestureController = IRGLGestureController()

        gestureController.addGesture(to: view)
        gestureController.addGesture(to: view)

        let rotationRecognizers = view.gestureRecognizers?.filter { $0 is UIRotationGestureRecognizer } ?? []
        XCTAssertEqual(rotationRecognizers.count, 1)
    }

    func testRemoveGestureRemovesRotationGestureRecognizer() {
        let view = IRGLView(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        let gestureController = IRGLGestureController()

        gestureController.addGesture(to: view)
        gestureController.removeGesture(to: view)

        let rotationRecognizers = view.gestureRecognizers?.filter { $0 is UIRotationGestureRecognizer } ?? []
        XCTAssertTrue(rotationRecognizers.isEmpty)
    }
}

final class IRGLViewSnapshotTests: XCTestCase {

    func testCreateImageFromFramebufferReturnsImageForZeroSizedView() {
        let view = IRGLView(frame: .zero)

        let image = view.createImageFromFramebuffer()

        XCTAssertEqual(image.size, .zero)
    }
}
