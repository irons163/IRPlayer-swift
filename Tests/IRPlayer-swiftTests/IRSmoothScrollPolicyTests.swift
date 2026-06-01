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
}
