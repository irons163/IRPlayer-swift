//
//  IRMatrix4Tests.swift
//  IRPlayer-swiftTests
//
//  Created by Codex on 2026/5/24.
//

import simd
import XCTest
@testable import IRPlayer_swift

final class IRMatrix4Tests: XCTestCase {

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
}
