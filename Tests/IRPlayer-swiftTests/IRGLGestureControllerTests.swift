import UIKit
import XCTest
@testable import IRPlayer_swift

final class IRGesturePolicyTests: XCTestCase {

    func testPanDirectionUsesDominantVelocityAxis() {
        XCTAssertEqual(IRGesturePolicy.panDirection(forVelocity: CGPoint(x: 20, y: 5)), .horizontal)
        XCTAssertEqual(IRGesturePolicy.panDirection(forVelocity: CGPoint(x: -4, y: 9)), .vertical)
        XCTAssertEqual(IRGesturePolicy.panDirection(forVelocity: CGPoint(x: 7, y: -7)), .unknown)
    }

    func testPanDirectionDefaultsNonFiniteVelocityToUnknown() {
        XCTAssertEqual(IRGesturePolicy.panDirection(forVelocity: CGPoint(x: CGFloat.nan, y: 5)), .unknown)
        XCTAssertEqual(IRGesturePolicy.panDirection(forVelocity: CGPoint(x: 5, y: CGFloat.infinity)), .unknown)
    }

    func testPanMovingDirectionUsesTranslationAndPanAxis() {
        XCTAssertEqual(IRGesturePolicy.panMovingDirection(forTranslation: CGPoint(x: 4, y: 0),
                                                         panDirection: .horizontal), .right)
        XCTAssertEqual(IRGesturePolicy.panMovingDirection(forTranslation: CGPoint(x: -4, y: 0),
                                                         panDirection: .horizontal), .left)
        XCTAssertEqual(IRGesturePolicy.panMovingDirection(forTranslation: CGPoint(x: 0, y: 4),
                                                         panDirection: .vertical), .bottom)
        XCTAssertEqual(IRGesturePolicy.panMovingDirection(forTranslation: CGPoint(x: 0, y: -4),
                                                         panDirection: .vertical), .top)
        XCTAssertEqual(IRGesturePolicy.panMovingDirection(forTranslation: CGPoint(x: 0, y: 0),
                                                         panDirection: .unknown), .unknown)
    }

    func testPanLocationUsesTargetMidpoint() {
        XCTAssertEqual(IRGesturePolicy.panLocation(forTouchX: 51, targetWidth: 100), .right)
        XCTAssertEqual(IRGesturePolicy.panLocation(forTouchX: 50, targetWidth: 100), .left)
        XCTAssertEqual(IRGesturePolicy.panLocation(forTouchX: 10, targetWidth: 0), .unknown)
        XCTAssertEqual(IRGesturePolicy.panLocation(forTouchX: CGFloat.nan, targetWidth: 100), .unknown)
    }

    func testPanMovingAxisUsesDominantTranslationAxis() {
        XCTAssertEqual(IRGesturePolicy.panMovingAxis(forTranslation: CGPoint(x: 10, y: 2)), .horizontal)
        XCTAssertEqual(IRGesturePolicy.panMovingAxis(forTranslation: CGPoint(x: 2, y: -10)), .vertical)
        XCTAssertEqual(IRGesturePolicy.panMovingAxis(forTranslation: CGPoint(x: 5, y: 5)), .unknown)
        XCTAssertEqual(IRGesturePolicy.panMovingAxis(forTranslation: CGPoint(x: CGFloat.nan, y: 5)), .unknown)
    }

    func testPanMovingAxisDisableDecisionMatchesConfiguredDisabledAxes() {
        XCTAssertTrue(IRGesturePolicy.isPanMovingAxisDisabled(.vertical, disabledAxes: .vertical))
        XCTAssertTrue(IRGesturePolicy.isPanMovingAxisDisabled(.horizontal, disabledAxes: .horizontal))
        XCTAssertFalse(IRGesturePolicy.isPanMovingAxisDisabled(.vertical, disabledAxes: .horizontal))
        XCTAssertFalse(IRGesturePolicy.isPanMovingAxisDisabled(.horizontal, disabledAxes: .vertical))
        XCTAssertFalse(IRGesturePolicy.isPanMovingAxisDisabled(.unknown, disabledAxes: .all))
    }

    func testPanRecognizerStateActionMapsBeganChangedAndFinishedStates() {
        XCTAssertEqual(IRGesturePolicy.panAction(for: .began), .begin)
        XCTAssertEqual(IRGesturePolicy.panAction(for: .changed), .change)
        XCTAssertEqual(IRGesturePolicy.panAction(for: .ended), .end)
        XCTAssertEqual(IRGesturePolicy.panAction(for: .cancelled), .end)
        XCTAssertEqual(IRGesturePolicy.panAction(for: .failed), .end)
        XCTAssertNil(IRGesturePolicy.panAction(for: .possible))
    }

    func testPinchRecognizerStateActionOnlyEndsOnEndedState() {
        XCTAssertEqual(IRGesturePolicy.pinchAction(for: .ended), .end)
        XCTAssertNil(IRGesturePolicy.pinchAction(for: .began))
        XCTAssertNil(IRGesturePolicy.pinchAction(for: .changed))
        XCTAssertNil(IRGesturePolicy.pinchAction(for: .cancelled))
        XCTAssertNil(IRGesturePolicy.pinchAction(for: .failed))
        XCTAssertNil(IRGesturePolicy.pinchAction(for: .possible))
    }
}

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

    func testSmoothScrollTargetScalesVelocityMagnitudeIntoDistanceAndDuration() {
        let target = IRSmoothScrollController.smoothScrollTarget(for: CGPoint(x: 300, y: 400))

        XCTAssertEqual(target.point.x, 37.5, accuracy: 0.0001)
        XCTAssertEqual(target.point.y, 50, accuracy: 0.0001)
        XCTAssertEqual(target.duration, 0.25, accuracy: 0.0001)
    }

    func testSmoothScrollTargetUsesZeroForZeroVelocity() {
        let target = IRSmoothScrollController.smoothScrollTarget(for: .zero)

        XCTAssertEqual(target.point, .zero)
        XCTAssertEqual(target.duration, 0)
    }

    func testSmoothScrollTargetDefaultsNonFiniteVelocityToZero() {
        let target = IRSmoothScrollController.smoothScrollTarget(for: CGPoint(x: CGFloat.nan, y: CGFloat.infinity))

        XCTAssertEqual(target.point, .zero)
        XCTAssertEqual(target.duration, 0)
    }

    func testSmoothScrollPolicyCalculatesEaseOutMovementStep() throws {
        let step = try XCTUnwrap(
            IRSmoothScrollPolicy.step(finalPoint: CGPoint(x: 100, y: 50),
                                      alreadyPoint: CGPoint(x: 20, y: 5),
                                      elapsed: 0.25,
                                      duration: 1.0)
        )

        XCTAssertEqual(step.move.x, 23.75, accuracy: 0.0001)
        XCTAssertEqual(step.move.y, 16.875, accuracy: 0.0001)
        XCTAssertEqual(step.alreadyPoint.x, 43.75, accuracy: 0.0001)
        XCTAssertEqual(step.alreadyPoint.y, 21.875, accuracy: 0.0001)
        XCTAssertFalse(step.isFinished)
    }

    func testSmoothScrollPolicyClampsElapsedTimeAndMarksFinished() throws {
        let step = try XCTUnwrap(
            IRSmoothScrollPolicy.step(finalPoint: CGPoint(x: 100, y: 50),
                                      alreadyPoint: CGPoint(x: 43.75, y: 21.875),
                                      elapsed: 2.0,
                                      duration: 1.0)
        )

        XCTAssertEqual(step.move.x, 56.25, accuracy: 0.0001)
        XCTAssertEqual(step.move.y, 28.125, accuracy: 0.0001)
        XCTAssertEqual(step.alreadyPoint, CGPoint(x: 100, y: 50))
        XCTAssertTrue(step.isFinished)
    }

    func testSmoothScrollPolicyRejectsInvalidTiming() {
        XCTAssertNil(IRSmoothScrollPolicy.step(finalPoint: CGPoint(x: 10, y: 10),
                                              alreadyPoint: .zero,
                                              elapsed: 0.1,
                                              duration: 0))
        XCTAssertNil(IRSmoothScrollPolicy.step(finalPoint: CGPoint(x: 10, y: 10),
                                              alreadyPoint: .zero,
                                              elapsed: CGFloat.nan,
                                              duration: 1))
    }

    func testSmoothScrollBoundsPolicyBuildsHorizontalAndVerticalBounceRequests() {
        let result = IRSmoothScrollPolicy.boundsBounce(
            bounds: .both,
            finalPoint: CGPoint(x: 30, y: -40),
            alreadyPoint: CGPoint(x: 10, y: -5),
            didHorizontalBounce: false,
            didVerticalBounce: false
        )

        XCTAssertEqual(result.horizontal?.amount, 20)
        XCTAssertEqual(result.horizontal?.direction, .right)
        XCTAssertEqual(result.vertical?.amount, -35)
        XCTAssertEqual(result.vertical?.direction, .up)
    }

    func testSmoothScrollBoundsPolicyMasksUnsupportedAxes() {
        let horizontal = IRSmoothScrollPolicy.boundsBounce(
            bounds: .horizontal,
            finalPoint: CGPoint(x: -30, y: 40),
            alreadyPoint: .zero,
            didHorizontalBounce: false,
            didVerticalBounce: false
        )
        let vertical = IRSmoothScrollPolicy.boundsBounce(
            bounds: .vertical,
            finalPoint: CGPoint(x: -30, y: 40),
            alreadyPoint: .zero,
            didHorizontalBounce: false,
            didVerticalBounce: false
        )

        XCTAssertEqual(horizontal.horizontal?.amount, -30)
        XCTAssertEqual(horizontal.horizontal?.direction, .left)
        XCTAssertNil(horizontal.vertical)
        XCTAssertNil(vertical.horizontal)
        XCTAssertEqual(vertical.vertical?.amount, 40)
        XCTAssertEqual(vertical.vertical?.direction, .down)
    }

    func testSmoothScrollBoundsPolicySkipsAlreadyBouncedAxesAndInvalidInputs() {
        let alreadyBounced = IRSmoothScrollPolicy.boundsBounce(
            bounds: .both,
            finalPoint: CGPoint(x: 30, y: 40),
            alreadyPoint: .zero,
            didHorizontalBounce: true,
            didVerticalBounce: true
        )
        let invalid = IRSmoothScrollPolicy.boundsBounce(
            bounds: .both,
            finalPoint: CGPoint(x: CGFloat.nan, y: 40),
            alreadyPoint: .zero,
            didHorizontalBounce: false,
            didVerticalBounce: false
        )

        XCTAssertNil(alreadyBounced.horizontal)
        XCTAssertNil(alreadyBounced.vertical)
        XCTAssertNil(invalid.horizontal)
        XCTAssertNil(invalid.vertical)
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

final class IRBounceControllerTests: XCTestCase {

    func testBounceGeometryClampsHorizontalControlPointToBounceWidth() {
        let geometry = IRBounceController.bouncePathGeometry(amount: -200,
                                                             direction: .left,
                                                             targetSize: CGSize(width: 100, height: 80))

        XCTAssertEqual(geometry.start, CGPoint(x: 100, y: 0))
        XCTAssertEqual(geometry.control, CGPoint(x: 92, y: 40))
        XCTAssertEqual(geometry.end, CGPoint(x: 100, y: 80))
    }

    func testBounceGeometryClampsVerticalControlPointToBounceWidth() {
        let geometry = IRBounceController.bouncePathGeometry(amount: 200,
                                                             direction: .down,
                                                             targetSize: CGSize(width: 100, height: 80))

        XCTAssertEqual(geometry.start, .zero)
        XCTAssertEqual(geometry.control, CGPoint(x: 50, y: 8))
        XCTAssertEqual(geometry.end, CGPoint(x: 100, y: 0))
    }

    func testBounceAnimationPlanMapsDirectionsToKeysAndAxes() {
        XCTAssertEqual(IRBounceController.animationPlan(for: .left), IRBounceAnimationPlan(key: "bounce_right", axis: .horizontal))
        XCTAssertEqual(IRBounceController.animationPlan(for: .right), IRBounceAnimationPlan(key: "bounce_left", axis: .horizontal))
        XCTAssertEqual(IRBounceController.animationPlan(for: .up), IRBounceAnimationPlan(key: "bounce_bottom", axis: .vertical))
        XCTAssertEqual(IRBounceController.animationPlan(for: .down), IRBounceAnimationPlan(key: "bounce_top", axis: .vertical))
        XCTAssertNil(IRBounceController.animationPlan(for: .none))
    }
}
