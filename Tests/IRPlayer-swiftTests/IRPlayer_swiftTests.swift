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
