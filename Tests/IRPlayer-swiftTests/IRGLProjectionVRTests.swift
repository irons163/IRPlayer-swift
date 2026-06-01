//
//  IRGLProjectionVRTests.swift
//  IRPlayer-swiftTests
//
//  Created by Codex on 2026/6/2.
//

import XCTest
@testable import IRPlayer_swift

final class IRGLProjectionVRTests: XCTestCase {

    func testStaticPolicyWrappersRemainSourceCompatible() {
        XCTAssertEqual(IRGLProjectionVR.glIndex(0), IRGLProjectionVRPolicy.glIndex(0))
        XCTAssertEqual(IRGLProjectionVR.glIndex(Int(UInt16.max)), IRGLProjectionVRPolicy.glIndex(Int(UInt16.max)))
        XCTAssertEqual(IRGLProjectionVR.glIndex(-1), IRGLProjectionVRPolicy.glIndex(-1))
    }

    func testGLIndexRejectsValuesOutsideUInt16Range() {
        XCTAssertNil(IRGLProjectionVR.glIndex(-1))
        XCTAssertNil(IRGLProjectionVR.glIndex(Int(UInt16.max) + 1))
    }

    func testGLIndexConvertsUInt16RepresentableValues() {
        XCTAssertEqual(IRGLProjectionVR.glIndex(0), 0)
        XCTAssertEqual(IRGLProjectionVR.glIndex(Int(UInt16.max)), UInt16.max)
    }
}
