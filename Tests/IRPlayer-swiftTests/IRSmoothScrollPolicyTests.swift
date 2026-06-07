//
//  IRSmoothScrollPolicyTests.swift
//  IRPlayer-swiftTests
//
//  Created by Codex on 2026/6/2.
//

import UIKit
import XCTest
@testable import IRPlayer_swift

final class IRSmoothScrollPolicyTests: XCTestCase {

    func testSmoothScrollTargetScalesVelocityMagnitudeIntoDistanceAndDuration() {
        let target = IRSmoothScrollController.smoothScrollTarget(for: CGPoint(x: 300, y: 400))

        XCTAssertEqual(target.point.x, 37.5, accuracy: 0.0001)
        XCTAssertEqual(target.point.y, 50, accuracy: 0.0001)
        XCTAssertEqual(target.duration, 0.25, accuracy: 0.0001)
    }

    func testSmoothScrollTargetWrapperMatchesPolicy() {
        let velocity = CGPoint(x: 300, y: 400)
        let wrapper = IRSmoothScrollController.smoothScrollTarget(for: velocity)
        let policy = IRSmoothScrollPolicy.smoothScrollTarget(for: velocity)

        XCTAssertEqual(wrapper.point.x, policy.point.x, accuracy: 0.0001)
        XCTAssertEqual(wrapper.point.y, policy.point.y, accuracy: 0.0001)
        XCTAssertEqual(wrapper.duration, policy.duration, accuracy: 0.0001)
        XCTAssertEqual(IRSmoothScrollPolicy.smoothScrollTarget(for: CGPoint(x: CGFloat.nan, y: 0)).point, .zero)
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

    func testSmoothScrollControllerInitializesTargetAndCalculatesPendingScroll() {
        let view = IRGLView(frame: CGRect(x: 0, y: 0, width: 120, height: 80))
        let controller = IRSmoothScrollController(targetView: view)
        defer { invalidateDisplayLink(in: controller) }

        controller.calculateSmoothScroll(velocity: CGPoint(x: 300, y: 400))

        XCTAssertTrue(controller.targetView === view)
        XCTAssertEqual(pointState(controller, "finalPoint"), CGPoint(x: 37.5, y: 50))
        XCTAssertEqual(cgFloatState(controller, "slideDuration"), 0.25, accuracy: 0.0001)
    }

    func testSmoothScrollControllerResetClearsPendingScrollAndBounceFlags() {
        let controller = IRSmoothScrollController(targetView: IRGLView(frame: .zero))
        defer { invalidateDisplayLink(in: controller) }

        controller.calculateSmoothScroll(velocity: CGPoint(x: 300, y: 400))
        controller.didScrollToBounds(.horizontal, withProgram: IRGLProgram2D())

        XCTAssertTrue(boolState(controller, "didHorizontalBoundsBounce"))

        controller.resetSmoothScroll()

        XCTAssertEqual(pointState(controller, "finalPoint"), .zero)
        XCTAssertEqual(pointState(controller, "alreadyPoint"), .zero)
        XCTAssertEqual(timeState(controller, "startTimestamp"), 0, accuracy: 0.0001)
        XCTAssertFalse(boolState(controller, "didHorizontalBoundsBounce"))
        XCTAssertFalse(boolState(controller, "didVerticalBoundsBounce"))
    }

    func testSmoothScrollControllerShiftDegreeUsesPendingRemainderAndDisablesPanMode() {
        let controller = IRSmoothScrollController(targetView: IRGLView(frame: .zero))
        defer { invalidateDisplayLink(in: controller) }
        controller.isPaned = true
        controller.calculateSmoothScroll(velocity: CGPoint(x: 300, y: 400))

        controller.shiftDegreeX(10, degreeY: 5)

        XCTAssertFalse(controller.isPaned)
        XCTAssertEqual(pointState(controller, "finalPoint"), CGPoint(x: 47.5, y: 45))
        XCTAssertEqual(cgFloatState(controller, "slideDuration"), 0.5, accuracy: 0.0001)
    }

    func testSmoothScrollControllerScrollByDelegatesToTargetView() {
        let view = IRGLView(frame: .zero)
        let controller = IRSmoothScrollController(targetView: view)
        defer { invalidateDisplayLink(in: controller) }

        controller.scrollBy(dx: 3, dy: -4)

        XCTAssertTrue(controller.targetView === view)
    }

    func testSmoothScrollControllerBoundsDelegateBouncesOncePerAxisAndNotifiesDelegate() {
        let view = IRGLView(frame: CGRect(x: 0, y: 0, width: 120, height: 80))
        let controller = IRSmoothScrollController(targetView: view)
        let delegate = SmoothScrollDelegateSpy()
        controller.delegate = delegate
        defer { invalidateDisplayLink(in: controller) }
        controller.calculateSmoothScroll(velocity: CGPoint(x: 300, y: -400))

        controller.didScrollToBounds(.both, withProgram: IRGLProgram2D())

        XCTAssertEqual(delegate.boundsScrollViews.count, 1)
        XCTAssertTrue(delegate.boundsScrollViews[0] === view)
        XCTAssertTrue(boolState(controller, "didHorizontalBoundsBounce"))
        XCTAssertTrue(boolState(controller, "didVerticalBoundsBounce"))

        controller.didScrollToBounds(.both, withProgram: IRGLProgram2D())

        XCTAssertEqual(delegate.boundsScrollViews.count, 2)
        XCTAssertTrue(boolState(controller, "didHorizontalBoundsBounce"))
        XCTAssertTrue(boolState(controller, "didVerticalBoundsBounce"))
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

    private func pointState(_ controller: IRSmoothScrollController, _ label: String) -> CGPoint {
        return state(controller, label) as? CGPoint ?? .zero
    }

    private func cgFloatState(_ controller: IRSmoothScrollController, _ label: String) -> CGFloat {
        return state(controller, label) as? CGFloat ?? .nan
    }

    private func timeState(_ controller: IRSmoothScrollController, _ label: String) -> TimeInterval {
        return state(controller, label) as? TimeInterval ?? .nan
    }

    private func boolState(_ controller: IRSmoothScrollController, _ label: String) -> Bool {
        return state(controller, label) as? Bool ?? false
    }

    private func state(_ controller: IRSmoothScrollController, _ label: String) -> Any? {
        return Mirror(reflecting: controller)
            .children
            .first { $0.label == label }?
            .value
    }

    private func invalidateDisplayLink(in controller: IRSmoothScrollController) {
        guard let timerValue = state(controller, "timer") else { return }
        let optionalMirror = Mirror(reflecting: timerValue)
        let displayLink = optionalMirror.children.first?.value as? CADisplayLink
        displayLink?.invalidate()
    }
}

private final class SmoothScrollDelegateSpy: IRGLViewDelegate {
    private(set) var boundsScrollViews: [IRGLView?] = []

    func glViewDidEndDragging(_ view: IRGLView?, willDecelerate: Bool) {}
    func glViewWillBeginDragging(_ view: IRGLView?) {}
    func glViewWillBeginZooming(_ view: IRGLView?) {}
    func glViewDidEndDecelerating(_ view: IRGLView?) {}
    func glViewDidEndZooming(_ view: IRGLView?, atScale scale: CGFloat) {}

    func glViewDidScroll(toBounds view: IRGLView?) {
        boundsScrollViews.append(view)
    }
}
