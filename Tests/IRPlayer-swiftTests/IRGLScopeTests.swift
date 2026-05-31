//
//  IRGLScopeTests.swift
//  IRPlayer-swiftTests
//
//  Created by Codex on 2026/5/24.
//

import XCTest
@testable import IRPlayer_swift

final class IRGLScopeTests: XCTestCase {

    func testScope2DDefaultValuesAreNeutral() {
        let scope = IRGLScope2D()

        XCTAssertEqual(scope.scaleX, 1)
        XCTAssertEqual(scope.scaleY, 1)
        XCTAssertEqual(scope.w, 0)
        XCTAssertEqual(scope.h, 0)
        XCTAssertEqual(scope.offsetX, 0)
        XCTAssertEqual(scope.offsetY, 0)
        XCTAssertEqual(scope.panDegree, 0)
    }

    func testScope2DCopyPreservesValuesWithoutSharingInstance() {
        let original = IRGLScope2D(scaleX: 2,
                                   scaleY: 3,
                                   offsetX: 4,
                                   offsetY: 5,
                                   panDegree: 6,
                                   w: 7,
                                   h: 8)

        let copy = IRGLScope2D(old: original)
        original.scaleX = 9
        original.offsetX = 10

        XCTAssertEqual(copy.scaleX, 2)
        XCTAssertEqual(copy.scaleY, 3)
        XCTAssertEqual(copy.offsetX, 4)
        XCTAssertEqual(copy.offsetY, 5)
        XCTAssertEqual(copy.panDegree, 6)
        XCTAssertEqual(copy.w, 7)
        XCTAssertEqual(copy.h, 8)
    }

    func testScope3DDefaultValuesUseUpTiltAndZeroAngles() {
        let scope = IRGLScope3D()

        XCTAssertEqual(scope.tiltType, .up)
        XCTAssertEqual(scope.lat, 0)
        XCTAssertEqual(scope.lng, 0)
        XCTAssertEqual(scope.scaleX, 1)
        XCTAssertEqual(scope.scaleY, 1)
    }

    func testScope3DInitializersPreserve3DAndInheritedValues() {
        let original = IRGLScope3D(lat: 11,
                                   lng: 22,
                                   scale: 1.5,
                                   tiltType: .backward,
                                   panDegree: 33,
                                   width: 44,
                                   height: 55)

        let copy = IRGLScope3D(old: original)
        original.lat = 99
        original.scaleX = 3

        XCTAssertEqual(copy.lat, 11)
        XCTAssertEqual(copy.lng, 22)
        XCTAssertEqual(copy.scaleX, 1.5)
        XCTAssertEqual(copy.scaleY, 1.5)
        XCTAssertEqual(copy.tiltType, .backward)
        XCTAssertEqual(copy.panDegree, 33)
        XCTAssertEqual(copy.w, 44)
        XCTAssertEqual(copy.h, 55)
    }
}
