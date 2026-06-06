//
//  IRPLFImageTests.swift
//  IRPlayer-swiftTests
//
//  Created by Codex on 2026/6/2.
//

import XCTest
@testable import IRPlayer_swift

final class IRPLFImageTests: XCTestCase {

    func testCGImageWithRGBDataBuildsImageWithExpectedGeometry() {
        let pixels: [UInt8] = [
            255, 0, 0, 0, 255, 0,
            0, 0, 255, 255, 255, 255
        ]

        let image = pixels.withUnsafeBufferPointer { buffer in
            IRPLFImageCGImageWithRGBData(buffer.baseAddress!, linesize: 6, width: 2, height: 2)
        }

        XCTAssertEqual(image?.width, 2)
        XCTAssertEqual(image?.height, 2)
        XCTAssertEqual(image?.bitsPerComponent, 8)
        XCTAssertEqual(image?.bitsPerPixel, 24)
        XCTAssertEqual(image?.bytesPerRow, 6)
    }

    func testImageWithRGBDataWrapsCGImage() {
        let pixels: [UInt8] = [
            10, 20, 30,
            40, 50, 60
        ]

        let image = pixels.withUnsafeBufferPointer { buffer in
            IRPLFImageWithRGBData(buffer.baseAddress!, linesize: 3, width: 1, height: 2)
        }

        XCTAssertEqual(image?.size.width, 1)
        XCTAssertEqual(image?.size.height, 2)
        XCTAssertNotNil(image?.cgImage)
    }

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
