//
//  IRMatrix4Tests.swift
//  IRPlayer-swiftTests
//
//  Created by Codex on 2026/5/24.
//

import simd
import CoreGraphics
import XCTest
@testable import IRPlayer_swift

final class IRMatrix4Tests: XCTestCase {

    func testIdentityReturnsSimdIdentity() {
        XCTAssertEqual(IRMatrix4.identity(), matrix_identity_float4x4)
    }

    func testTranslationMatrixStoresTranslationInLastColumn() {
        let matrix = IRMatrix4.makeTranslation(1, 2, 3)

        XCTAssertEqual(matrix.columns.3.x, 1, accuracy: 0.0001)
        XCTAssertEqual(matrix.columns.3.y, 2, accuracy: 0.0001)
        XCTAssertEqual(matrix.columns.3.z, 3, accuracy: 0.0001)
        XCTAssertEqual(matrix.columns.3.w, 1, accuracy: 0.0001)
    }

    func testScaleMatrixStoresScaleOnDiagonal() {
        let matrix = IRMatrix4.makeScale(2, 3, 4)

        XCTAssertEqual(matrix.columns.0.x, 2, accuracy: 0.0001)
        XCTAssertEqual(matrix.columns.1.y, 3, accuracy: 0.0001)
        XCTAssertEqual(matrix.columns.2.z, 4, accuracy: 0.0001)
        XCTAssertEqual(matrix.columns.3.w, 1, accuracy: 0.0001)
    }

    func testMultiplyReturnsSimdProduct() {
        let translation = IRMatrix4.makeTranslation(1, 2, 3)
        let scale = IRMatrix4.makeScale(2, 2, 2)

        XCTAssertEqual(IRMatrix4.multiply(translation, scale), simd_mul(translation, scale))
    }

    func testRotationMatrixRotatesAroundNormalizedAxis() {
        let matrix = IRMatrix4.makeRotation(.pi / 2, 0, 0, 2)
        let rotated = simd_mul(matrix, SIMD4<Float>(1, 0, 0, 1))

        XCTAssertEqual(rotated.x, 0, accuracy: 0.0001)
        XCTAssertEqual(rotated.y, 1, accuracy: 0.0001)
        XCTAssertEqual(rotated.z, 0, accuracy: 0.0001)
        XCTAssertEqual(rotated.w, 1, accuracy: 0.0001)
    }

    func testPerspectiveMatrixStoresProjectionTerms() {
        let matrix = IRMatrix4.makePerspective(.pi / 2, 2, 1, 11)

        XCTAssertEqual(matrix.columns.0.x, 0.5, accuracy: 0.0001)
        XCTAssertEqual(matrix.columns.1.y, 1, accuracy: 0.0001)
        XCTAssertEqual(matrix.columns.2.z, -1.1, accuracy: 0.0001)
        XCTAssertEqual(matrix.columns.2.w, -1, accuracy: 0.0001)
        XCTAssertEqual(matrix.columns.3.z, -1.1, accuracy: 0.0001)
        XCTAssertEqual(matrix.columns.3.w, 0, accuracy: 0.0001)
    }

    func testLookAtMatrixMovesEyeToOrigin() {
        let eye = SIMD3<Float>(0, 0, 1)
        let matrix = IRMatrix4.makeLookAt(
            eye,
            SIMD3<Float>(0, 0, 0),
            SIMD3<Float>(0, 1, 0)
        )
        let transformedEye = simd_mul(matrix, SIMD4<Float>(eye, 1))

        XCTAssertEqual(transformedEye.x, 0, accuracy: 0.0001)
        XCTAssertEqual(transformedEye.y, 0, accuracy: 0.0001)
        XCTAssertEqual(transformedEye.z, 0, accuracy: 0.0001)
        XCTAssertEqual(transformedEye.w, 1, accuracy: 0.0001)
    }

    func testOrthoMatrixStoresScaleAndTranslationTerms() {
        let matrix = IRMatrix4.makeOrtho(-2, 2, -1, 3, 1, 5)

        XCTAssertEqual(matrix.columns.0.x, 0.5, accuracy: 0.0001)
        XCTAssertEqual(matrix.columns.1.y, 0.5, accuracy: 0.0001)
        XCTAssertEqual(matrix.columns.2.z, -0.5, accuracy: 0.0001)
        XCTAssertEqual(matrix.columns.3.x, 0, accuracy: 0.0001)
        XCTAssertEqual(matrix.columns.3.y, -0.5, accuracy: 0.0001)
        XCTAssertEqual(matrix.columns.3.z, -1.5, accuracy: 0.0001)
        XCTAssertEqual(matrix.columns.3.w, 1, accuracy: 0.0001)
    }

    func testMetalClipSpaceConvertsIdentityZRange() {
        let matrix = IRMatrix4.identity().toMetalClipSpace()

        XCTAssertEqual(matrix.columns.0.x, 1, accuracy: 0.0001)
        XCTAssertEqual(matrix.columns.1.y, 1, accuracy: 0.0001)
        XCTAssertEqual(matrix.columns.2.z, 0.5, accuracy: 0.0001)
        XCTAssertEqual(matrix.columns.3.z, 0.5, accuracy: 0.0001)
        XCTAssertEqual(matrix.columns.3.w, 1, accuracy: 0.0001)
    }
}

final class IRSensorTests: XCTestCase {

    func testMotionDeltaWrapsAcrossPositiveAndNegativeHalfTurns() {
        XCTAssertEqual(IRSensor.normalizedMotionDelta(current: CGFloat(-170), previous: CGFloat(170)), 20, accuracy: 0.0001)
        XCTAssertEqual(IRSensor.normalizedMotionDelta(current: CGFloat(170), previous: CGFloat(-170)), -20, accuracy: 0.0001)
    }

    func testMotionDeltaKeepsSmallOffsetsUnchanged() {
        XCTAssertEqual(IRSensor.normalizedMotionDelta(current: CGFloat(45), previous: CGFloat(15)), 30, accuracy: 0.0001)
        XCTAssertEqual(IRSensor.normalizedMotionDelta(current: CGFloat(-20), previous: CGFloat(15)), -35, accuracy: 0.0001)
    }

    func testMotionDeltaDefaultsNonFiniteInputsToZero() {
        XCTAssertEqual(IRSensor.normalizedMotionDelta(current: CGFloat.nan, previous: CGFloat(15)), 0)
        XCTAssertEqual(IRSensor.normalizedMotionDelta(current: CGFloat(15), previous: CGFloat.infinity), 0)
    }

    func testMotionDeltaDefaultsOverflowingDeltaToZero() {
        XCTAssertEqual(
            IRSensor.normalizedMotionDelta(current: CGFloat.greatestFiniteMagnitude,
                                           previous: -CGFloat.greatestFiniteMagnitude),
            0
        )
    }
}
