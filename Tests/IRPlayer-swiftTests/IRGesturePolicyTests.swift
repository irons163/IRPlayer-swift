//
//  IRGesturePolicyTests.swift
//  IRPlayer-swiftTests
//
//  Created by Codex on 2026/6/2.
//

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
