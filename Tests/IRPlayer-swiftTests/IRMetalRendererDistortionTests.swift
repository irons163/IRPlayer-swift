//
//  IRMetalRendererDistortionTests.swift
//  IRPlayer-swiftTests
//
//  Created by Codex on 2026/6/2.
//

import XCTest
@testable import IRPlayer_swift

final class IRMetalRendererDistortionTests: XCTestCase {

    func testDistortionTextureSizeRejectsInvalidOrOverflowingSizes() {
        XCTAssertNil(IRMetalRenderer.distortionTextureSize(from: CGSize(width: 0, height: 10)))
        XCTAssertNil(IRMetalRenderer.distortionTextureSize(from: CGSize(width: 10, height: 0)))
        XCTAssertNil(IRMetalRenderer.distortionTextureSize(from: CGSize(width: CGFloat.infinity, height: 10)))
        XCTAssertNil(IRMetalRenderer.distortionTextureSize(from: CGSize(width: 10, height: CGFloat.nan)))
        XCTAssertNil(IRMetalRenderer.distortionTextureSize(from: CGSize(width: CGFloat(Int.max) * 2, height: 10)))
    }

    func testDistortionTextureSizeConvertsFinitePositiveSize() {
        let size = IRMetalRenderer.distortionTextureSize(from: CGSize(width: 101.9, height: 50.2))

        XCTAssertEqual(size?.width, 101)
        XCTAssertEqual(size?.height, 50)
    }

    func testDistortionScissorRectsSplitDrawableWidth() throws {
        let rects = try XCTUnwrap(IRMetalRenderer.distortionScissorRects(drawableSize: CGSize(width: 101, height: 50)))

        XCTAssertEqual(rects.left.x, 0)
        XCTAssertEqual(rects.left.width, 50)
        XCTAssertEqual(rects.left.height, 50)
        XCTAssertEqual(rects.right.x, 50)
        XCTAssertEqual(rects.right.width, 51)
        XCTAssertEqual(rects.right.height, 50)
    }
}
