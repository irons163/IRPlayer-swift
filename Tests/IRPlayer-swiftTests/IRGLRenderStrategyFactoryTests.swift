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

    func testStrategyKindWrapperMatchesPolicy() {
        let renderModes: [IRGLRenderMode] = [
            IRGLRenderModeDistortion(),
            IRGLRenderMode2DFisheye2Pano(),
            IRGLRenderModeVR(),
            IRGLRenderModeMulti4P(),
            IRGLRenderMode3DFisheye(),
            IRGLRenderMode2D(),
            IRGLRenderMode()
        ]

        for renderMode in renderModes {
            XCTAssertEqual(IRGLRenderStrategyFactory.strategyKind(for: renderMode),
                           IRGLRenderStrategyPolicy.strategyKind(for: renderMode))
        }
    }
}
