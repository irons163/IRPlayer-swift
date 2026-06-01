//
//  IRMetalRendererPixelFormatTests.swift
//  IRPlayer-swiftTests
//
//  Created by Codex on 2026/6/2.
//

import Metal
import XCTest
@testable import IRPlayer_swift

final class IRMetalRendererPixelFormatTests: XCTestCase {

    func testRuntimeDebugOutputIsSilentByDefault() {
        XCTAssertFalse(IRMetalRuntimeDebugOutput.isEnabled)

        let output = captureStandardOutput {
            IRMetalRuntimeDebugOutput.write("metal trace")
        }

        XCTAssertEqual(output, "")
    }

    func testComputeScaleRejectsInvalidSizes() {
        XCTAssertEqual(
            IRMetalRenderer.computeScale(contentMode: .scaleAspectFit, frameSize: CGSize(width: CGFloat.nan, height: 100), drawableSize: CGSize(width: 100, height: 100)),
            CGSize(width: 1, height: 1)
        )
        XCTAssertEqual(
            IRMetalRenderer.computeScale(contentMode: .scaleAspectFill, frameSize: CGSize(width: 100, height: 100), drawableSize: CGSize(width: CGFloat.infinity, height: 100)),
            CGSize(width: 1, height: 1)
        )
    }

    func testComputeScaleCalculatesAspectFitAndFill() {
        XCTAssertEqual(
            IRMetalRenderer.computeScale(contentMode: .scaleAspectFit, frameSize: CGSize(width: 400, height: 200), drawableSize: CGSize(width: 100, height: 100)),
            CGSize(width: 1, height: 0.5)
        )
        XCTAssertEqual(
            IRMetalRenderer.computeScale(contentMode: .scaleAspectFill, frameSize: CGSize(width: 400, height: 200), drawableSize: CGSize(width: 100, height: 100)),
            CGSize(width: 2, height: 1)
        )
    }

    func testRGBTextureLayoutRejectsInvalidOrOverflowingInputs() {
        XCTAssertNil(IRMetalRenderer.rgbTextureLayout(width: 0, height: 1, linesize: 4, byteCount: 4))
        XCTAssertNil(IRMetalRenderer.rgbTextureLayout(width: 1, height: 0, linesize: 4, byteCount: 4))
        XCTAssertNil(IRMetalRenderer.rgbTextureLayout(width: Int.max, height: 2, linesize: Int.max, byteCount: Int.max))
    }

    func testRGBTextureLayoutRequiresExpectedBGRABytesPerRowAndBufferSize() {
        XCTAssertNil(IRMetalRenderer.rgbTextureLayout(width: 2, height: 2, linesize: 7, byteCount: 16))
        XCTAssertNil(IRMetalRenderer.rgbTextureLayout(width: 2, height: 2, linesize: 8, byteCount: 15))
        XCTAssertEqual(
            IRMetalRenderer.rgbTextureLayout(width: 2, height: 2, linesize: 8, byteCount: 16)?.bytesPerRow,
            8
        )
    }

    func testMakeRGBTextureRejectsLinesizeThatCannotFitBytesPerRow() throws {
        guard let device = MTLCreateSystemDefaultDevice(),
              let renderer = IRMetalRenderer(device: device) else {
            throw XCTSkip("Metal device unavailable")
        }
        let frame = IRVideoFrameRGB(linesize: UInt(Int.max) + 1, rgb: Data([0, 0, 0, 0]))
        frame.width = 1
        frame.height = 1

        XCTAssertNil(renderer.makeRGBTexture(from: frame))
    }
}
