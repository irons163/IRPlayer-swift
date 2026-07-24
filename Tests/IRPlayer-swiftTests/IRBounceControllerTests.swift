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

        let rightGeometry =
            IRBounceController.bouncePathGeometry(
                amount: 3,
                direction: .right,
                targetSize: targetSize
            )
        XCTAssertEqual(rightGeometry.start, .zero)
        XCTAssertEqual(rightGeometry.control, CGPoint(x: 3, y: 40))
        XCTAssertEqual(rightGeometry.end, CGPoint(x: 0, y: 80))

        let upGeometry =
            IRBounceController.bouncePathGeometry(
                amount: -4,
                direction: .up,
                targetSize: targetSize
            )
        XCTAssertEqual(upGeometry.start, CGPoint(x: 0, y: 80))
        XCTAssertEqual(upGeometry.control, CGPoint(x: 50, y: 76))
        XCTAssertEqual(upGeometry.end, CGPoint(x: 100, y: 80))
    }

    func testBounceGeometryRejectsMalformedInputs() {
        let cases: [(CGFloat, CGSize)] = [
            (CGFloat.nan, CGSize(width: 100, height: 80)),
            (
                1,
                CGSize(width: CGFloat.infinity, height: 80)
            ),
            (
                1,
                CGSize(width: 100, height: -CGFloat.infinity)
            ),
            (1, CGSize(width: 0, height: 80)),
            (1, CGSize(width: 100, height: -80))
        ]

        for (amount, size) in cases {
            XCTAssertEqual(
                IRBounceController.bouncePathGeometry(
                    amount: amount,
                    direction: .left,
                    targetSize: size
                ),
                .zero
            )
        }
    }

    func testBounceGeometryReturnsZeroForUnsupportedDirection() {
        XCTAssertEqual(
            IRBounceController.bouncePathGeometry(
                amount: 4,
                direction: .none,
                targetSize: CGSize(width: 100, height: 80)
            ),
            .zero
        )
    }

    func testBounceAnimationPlanMapsDirectionsToKeysAndAxes() {
        let cases: [
            (
                IRScrollDirectionType,
                IRBounceController.AnimationPlan?
            )
        ] = [
            (
                .left,
                .init(key: "bounce_right", axis: .horizontal)
            ),
            (
                .right,
                .init(key: "bounce_left", axis: .horizontal)
            ),
            (
                .up,
                .init(key: "bounce_bottom", axis: .vertical)
            ),
            (
                .down,
                .init(key: "bounce_top", axis: .vertical)
            ),
            (.none, nil)
        ]

        for (direction, expected) in cases {
            XCTAssertEqual(
                IRBounceController.animationPlan(
                    for: direction
                ),
                expected
            )
        }
    }

    func testBounceGeometryRejectsDerivedCoordinateOverflow() {
        for direction in [
            IRScrollDirectionType.left,
            .up
        ] {
            XCTAssertEqual(
                IRBounceController.bouncePathGeometry(
                    amount: CGFloat.greatestFiniteMagnitude,
                    direction: direction,
                    targetSize: CGSize(
                        width: CGFloat.greatestFiniteMagnitude,
                        height: CGFloat.greatestFiniteMagnitude
                    )
                ),
                .zero
            )
        }
    }
}
