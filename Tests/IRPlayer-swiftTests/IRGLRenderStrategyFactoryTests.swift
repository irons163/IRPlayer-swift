//
//  IRGLRenderStrategyFactoryTests.swift
//  IRPlayer-swiftTests
//
//  Created by Codex on 2026/5/24.
//

import XCTest
@testable import IRPlayer_swift

final class IRGLRenderStrategyFactoryTests: XCTestCase {

    func testStrategyKindMatchesRenderModeTypePrecedence() {
        XCTAssertEqual(IRGLRenderStrategyFactory.strategyKind(for: IRGLRenderModeDistortion()), .distortion)
        XCTAssertEqual(IRGLRenderStrategyFactory.strategyKind(for: IRGLRenderMode2DFisheye2Pano()), .fish2Pano)
        XCTAssertEqual(IRGLRenderStrategyFactory.strategyKind(for: IRGLRenderModeVR()), .vr)
        XCTAssertEqual(IRGLRenderStrategyFactory.strategyKind(for: IRGLRenderModeMulti4P()), .multi4P)
        XCTAssertEqual(IRGLRenderStrategyFactory.strategyKind(for: IRGLRenderMode3DFisheye()), .fisheye)
        XCTAssertEqual(IRGLRenderStrategyFactory.strategyKind(for: IRGLRenderMode2D()), .twoD)
        XCTAssertEqual(IRGLRenderStrategyFactory.strategyKind(for: IRGLRenderMode()), .twoD)
    }
}
