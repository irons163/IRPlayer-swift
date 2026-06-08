//
//  IRVideoFrameRGBTests.swift
//  IRPlayer-swiftTests
//
//  Created by Codex on 2026/6/2.
//

import Foundation
import XCTest
@testable import IRPlayer_swift

final class IRVideoFrameRGBTests: XCTestCase {

    func testBytesPerRowWrapperMatchesPolicy() {
        XCTAssertEqual(IRVideoFrameRGB.bytesPerRow(from: 12), IRVideoFrameRGBPolicy.bytesPerRow(from: 12))
        XCTAssertNil(IRVideoFrameRGBPolicy.bytesPerRow(from: UInt(Int.max) + 1))
    }

    func testAsImageReturnsNilWhenLinesizeCannotFitBytesPerRow() {
        let frame = IRVideoFrameRGB(linesize: UInt(Int.max) + 1, rgb: Data([0, 0, 0]))
        frame.width = 1
        frame.height = 1

        XCTAssertNil(frame.asImage())
    }
}
