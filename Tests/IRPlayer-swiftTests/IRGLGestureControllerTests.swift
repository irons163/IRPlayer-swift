import UIKit
import XCTest
@testable import IRPlayer_swift

final class IRGLGestureControllerTests: XCTestCase {

    func testGesturePolicyConvertsTouchPointToRenderSpace() {
        let point = IRGLGesturePolicy.renderPoint(from: CGPoint(x: 12, y: 20),
                                                 viewHeight: 100,
                                                 screenScale: 3)

        XCTAssertEqual(point.x, 36)
        XCTAssertEqual(point.y, 240)
    }

    func testGesturePolicyDefaultsInvalidInputsToZero() {
        XCTAssertEqual(
            IRGLGesturePolicy.renderPoint(from: CGPoint(x: CGFloat.nan, y: 20),
                                          viewHeight: 100,
                                          screenScale: 3),
            .zero
        )
        XCTAssertEqual(
            IRGLGesturePolicy.renderPoint(from: CGPoint(x: 12, y: 20),
                                          viewHeight: CGFloat.infinity,
                                          screenScale: 3),
            .zero
        )
        XCTAssertEqual(
            IRGLGesturePolicy.renderPoint(from: CGPoint(x: 12, y: 20),
                                          viewHeight: 100,
                                          screenScale: 0),
            .zero
        )
    }

    func testGesturePolicyMapsPanRecognizerStatesToActions() {
        XCTAssertEqual(IRGLGesturePolicy.panAction(for: .began), .begin)
        XCTAssertEqual(IRGLGesturePolicy.panAction(for: .changed), .update)
        XCTAssertEqual(IRGLGesturePolicy.panAction(for: .possible), .update)
        XCTAssertEqual(IRGLGesturePolicy.panAction(for: .ended), .endWithDeceleration)
        XCTAssertEqual(IRGLGesturePolicy.panAction(for: .cancelled), .cancel)
        XCTAssertEqual(IRGLGesturePolicy.panAction(for: .failed), .cancel)
    }

    func testGesturePolicyMapsContinuousRecognizerStatesToActions() {
        XCTAssertEqual(IRGLGesturePolicy.continuousAction(for: .began), .begin)
        XCTAssertEqual(IRGLGesturePolicy.continuousAction(for: .changed), .update)
        XCTAssertEqual(IRGLGesturePolicy.continuousAction(for: .possible), .update)
        XCTAssertEqual(IRGLGesturePolicy.continuousAction(for: .ended), .end)
        XCTAssertEqual(IRGLGesturePolicy.continuousAction(for: .cancelled), .end)
        XCTAssertEqual(IRGLGesturePolicy.continuousAction(for: .failed), .end)
    }

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

    func testGestureCallbacksDoNotWriteDebugOutput() {
        let gestureController = IRGLGestureController()

        let output = captureStandardOutput {
            gestureController.handlePan(UIPanGestureRecognizer())
            gestureController.handlePinch(UIPinchGestureRecognizer())
            gestureController.handleRotate(UIRotationGestureRecognizer())
            gestureController.handleDoubleTap(UITapGestureRecognizer())
        }

        XCTAssertEqual(output, "")
    }
}
