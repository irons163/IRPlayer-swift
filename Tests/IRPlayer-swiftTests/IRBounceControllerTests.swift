//
//  IRBounceControllerTests.swift
//  IRPlayer-swiftTests
//
//  Created by Codex on 2026/6/2.
//

import UIKit
import XCTest
@testable import IRPlayer_swift

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

    func testBounceGeometryBuildsRightAndUpEdges() {
        let targetSize = CGSize(width: 100, height: 80)

        let rightGeometry = IRBouncePolicy.bouncePathGeometry(amount: 3,
                                                             direction: .right,
                                                             targetSize: targetSize)
        XCTAssertEqual(rightGeometry.start, .zero)
        XCTAssertEqual(rightGeometry.control, CGPoint(x: 3, y: 40))
        XCTAssertEqual(rightGeometry.end, CGPoint(x: 0, y: 80))

        let upGeometry = IRBouncePolicy.bouncePathGeometry(amount: -4,
                                                          direction: .up,
                                                          targetSize: targetSize)
        XCTAssertEqual(upGeometry.start, CGPoint(x: 0, y: 80))
        XCTAssertEqual(upGeometry.control, CGPoint(x: 50, y: 76))
        XCTAssertEqual(upGeometry.end, CGPoint(x: 100, y: 80))
    }

    func testBounceGeometryRejectsMalformedInputs() {
        let geometry = IRBouncePolicy.bouncePathGeometry(amount: .nan,
                                                         direction: .left,
                                                         targetSize: CGSize(width: CGFloat.infinity, height: -80))

        XCTAssertEqual(geometry.start, .zero)
        XCTAssertEqual(geometry.control, .zero)
        XCTAssertEqual(geometry.end, .zero)
    }

    func testBounceGeometryReturnsZeroForUnsupportedDirection() {
        let geometry = IRBouncePolicy.bouncePathGeometry(amount: 4,
                                                         direction: .none,
                                                         targetSize: CGSize(width: 100, height: 80))

        XCTAssertEqual(geometry.start, .zero)
        XCTAssertEqual(geometry.control, .zero)
        XCTAssertEqual(geometry.end, .zero)
    }

    func testBounceAnimationPlanMapsDirectionsToKeysAndAxes() {
        XCTAssertEqual(IRBounceController.animationPlan(for: .left), IRBounceAnimationPlan(key: "bounce_right", axis: .horizontal))
        XCTAssertEqual(IRBounceController.animationPlan(for: .right), IRBounceAnimationPlan(key: "bounce_left", axis: .horizontal))
        XCTAssertEqual(IRBounceController.animationPlan(for: .up), IRBounceAnimationPlan(key: "bounce_bottom", axis: .vertical))
        XCTAssertEqual(IRBounceController.animationPlan(for: .down), IRBounceAnimationPlan(key: "bounce_top", axis: .vertical))
        XCTAssertNil(IRBounceController.animationPlan(for: .none))
    }

    func testBounceControllerWrappersMatchPolicy() {
        let targetSize = CGSize(width: 120, height: 90)
        let wrapperGeometry = IRBounceController.bouncePathGeometry(amount: -240,
                                                                    direction: .left,
                                                                    targetSize: targetSize)
        let policyGeometry = IRBouncePolicy.bouncePathGeometry(amount: -240,
                                                               direction: .left,
                                                               targetSize: targetSize)

        XCTAssertEqual(wrapperGeometry.start, policyGeometry.start)
        XCTAssertEqual(wrapperGeometry.control, policyGeometry.control)
        XCTAssertEqual(wrapperGeometry.end, policyGeometry.end)
        XCTAssertEqual(IRBounceController.animationPlan(for: .up), IRBouncePolicy.animationPlan(for: .up))
        XCTAssertNil(IRBouncePolicy.animationPlan(for: .none))
    }
}
