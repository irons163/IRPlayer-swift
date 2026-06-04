//
//  IRPLFImageTests.swift
//  IRPlayer-swiftTests
//
//  Created by Codex on 2026/6/2.
//

import XCTest
@testable import IRPlayer_swift

final class IRPLFImageTests: XCTestCase {

    func testRGBDataByteCountRejectsInvalidOrOverflowingInputs() {
        XCTAssertNil(IRPLFImageRGBDataByteCount(linesize: 0, width: 4, height: 4))
        XCTAssertNil(IRPLFImageRGBDataByteCount(linesize: 12, width: 0, height: 4))
        XCTAssertNil(IRPLFImageRGBDataByteCount(linesize: 12, width: 4, height: 0))
        XCTAssertNil(IRPLFImageRGBDataByteCount(linesize: Int.max, width: 4, height: 2))
    }

    func testRGBDataByteCountRequiresRowsWideEnoughForRGBPixels() {
        XCTAssertNil(IRPLFImageRGBDataByteCount(linesize: 11, width: 4, height: 2))
        XCTAssertEqual(IRPLFImageRGBDataByteCount(linesize: 12, width: 4, height: 2), 24)
    }

    func testRGBDataByteCountWrapperMatchesPolicy() {
        XCTAssertEqual(
            IRPLFImageRGBDataByteCount(linesize: 12, width: 4, height: 2),
            IRPLFImagePolicy.rgbDataByteCount(linesize: 12, width: 4, height: 2)
        )
        XCTAssertNil(IRPLFImagePolicy.rgbDataByteCount(linesize: 11, width: 4, height: 2))
    }
}
