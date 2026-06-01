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

    func testBounceAnimationPlanMapsDirectionsToKeysAndAxes() {
        XCTAssertEqual(IRBounceController.animationPlan(for: .left), IRBounceAnimationPlan(key: "bounce_right", axis: .horizontal))
        XCTAssertEqual(IRBounceController.animationPlan(for: .right), IRBounceAnimationPlan(key: "bounce_left", axis: .horizontal))
        XCTAssertEqual(IRBounceController.animationPlan(for: .up), IRBounceAnimationPlan(key: "bounce_bottom", axis: .vertical))
        XCTAssertEqual(IRBounceController.animationPlan(for: .down), IRBounceAnimationPlan(key: "bounce_top", axis: .vertical))
        XCTAssertNil(IRBounceController.animationPlan(for: .none))
    }
}
