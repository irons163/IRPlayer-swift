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

    func testRuntimeDebugOutputWrapperMatchesPolicy() {
        XCTAssertEqual(IRMetalRuntimeDebugOutput.isEnabled, IRMetalRuntimeDebugOutputPolicy.isEnabled)
        XCTAssertFalse(IRMetalRuntimeDebugOutputPolicy.isEnabled)

        let output = captureStandardOutput {
            IRMetalRuntimeDebugOutputPolicy.write("metal trace")
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

    func testComputeScaleWrapperMatchesPolicy() {
        let frameSize = CGSize(width: 400, height: 200)
        let drawableSize = CGSize(width: 100, height: 100)

        XCTAssertEqual(
            IRMetalRenderer.computeScale(contentMode: .scaleAspectFit, frameSize: frameSize, drawableSize: drawableSize),
            IRMetalRendererScalePolicy.computeScale(contentMode: .scaleAspectFit, frameSize: frameSize, drawableSize: drawableSize)
        )
        XCTAssertEqual(
            IRMetalRenderer.computeScale(contentMode: .scaleAspectFill, frameSize: frameSize, drawableSize: drawableSize),
            IRMetalRendererScalePolicy.computeScale(contentMode: .scaleAspectFill, frameSize: frameSize, drawableSize: drawableSize)
        )
        XCTAssertEqual(
            IRMetalRendererScalePolicy.computeScale(contentMode: .scaleToFill,
                                                    frameSize: CGSize(width: CGFloat.nan, height: 200),
                                                    drawableSize: drawableSize),
            CGSize(width: 1, height: 1)
        )
    }

    func testQuadVerticesCoverFullTextureRange() {
        let vertices = IRMetalRenderer.quadVertices(textureRange: .full)

        XCTAssertEqual(vertices.map(\.position), [
            SIMD2<Float>(-1.0, -1.0),
            SIMD2<Float>( 1.0, -1.0),
            SIMD2<Float>(-1.0,  1.0),
            SIMD2<Float>( 1.0,  1.0)
        ])
        XCTAssertEqual(vertices.map(\.texCoord), [
            SIMD2<Float>(0.0, 1.0),
            SIMD2<Float>(1.0, 1.0),
            SIMD2<Float>(0.0, 0.0),
            SIMD2<Float>(1.0, 0.0)
        ])
    }

    func testQuadVerticesSplitLeftAndRightTextureRanges() {
        XCTAssertEqual(IRMetalRenderer.quadVertices(textureRange: .left).map(\.texCoord), [
            SIMD2<Float>(0.0, 1.0),
            SIMD2<Float>(0.5, 1.0),
            SIMD2<Float>(0.0, 0.0),
            SIMD2<Float>(0.5, 0.0)
        ])
        XCTAssertEqual(IRMetalRenderer.quadVertices(textureRange: .right).map(\.texCoord), [
            SIMD2<Float>(0.5, 1.0),
            SIMD2<Float>(1.0, 1.0),
            SIMD2<Float>(0.5, 0.0),
            SIMD2<Float>(1.0, 0.0)
        ])
    }

    func testQuadVerticesWrapperMatchesGeometryPolicy() {
        XCTAssertEqual(IRMetalRenderer.quadVertices(textureRange: .full),
                       IRMetalRendererGeometryPolicy.quadVertices(textureRange: .full))
        XCTAssertEqual(IRMetalRenderer.quadVertices(textureRange: .left),
                       IRMetalRendererGeometryPolicy.quadVertices(textureRange: .left))
        XCTAssertEqual(IRMetalRenderer.quadVertices(textureRange: .right),
                       IRMetalRendererGeometryPolicy.quadVertices(textureRange: .right))
    }

    func testMetalViewportBuildsTopLeftFlippedViewport() {
        let viewport = IRMetalRenderer.metalViewport(drawableSize: CGSize(width: 320, height: 240),
                                                     viewport: CGRect(x: 10, y: 20, width: 100, height: 50),
                                                     orientation: .topLeftFlipped)

        XCTAssertEqual(viewport.originX, 10)
        XCTAssertEqual(viewport.originY, 220)
        XCTAssertEqual(viewport.width, 100)
        XCTAssertEqual(viewport.height, -50)
        XCTAssertEqual(viewport.znear, 0)
        XCTAssertEqual(viewport.zfar, 1)
    }

    func testMetalViewportBuildsBottomLeftViewport() {
        let viewport = IRMetalRenderer.metalViewport(drawableSize: CGSize(width: 320, height: 240),
                                                     viewport: CGRect(x: 10, y: 20, width: 100, height: 50),
                                                     orientation: .bottomLeft)

        XCTAssertEqual(viewport.originX, 10)
        XCTAssertEqual(viewport.originY, 170)
        XCTAssertEqual(viewport.width, 100)
        XCTAssertEqual(viewport.height, 50)
        XCTAssertEqual(viewport.znear, 0)
        XCTAssertEqual(viewport.zfar, 1)
    }

    func testMetalViewportWrapperMatchesGeometryPolicy() {
        let drawableSize = CGSize(width: 320, height: 240)
        let viewport = CGRect(x: 10, y: 20, width: 100, height: 50)

        let wrapper = IRMetalRenderer.metalViewport(drawableSize: drawableSize,
                                                    viewport: viewport,
                                                    orientation: .topLeftFlipped)
        let policy = IRMetalRendererGeometryPolicy.metalViewport(drawableSize: drawableSize,
                                                                 viewport: viewport,
                                                                 orientation: .topLeftFlipped)

        XCTAssertEqual(wrapper.originX, policy.originX)
        XCTAssertEqual(wrapper.originY, policy.originY)
        XCTAssertEqual(wrapper.width, policy.width)
        XCTAssertEqual(wrapper.height, policy.height)
        XCTAssertEqual(wrapper.znear, policy.znear)
        XCTAssertEqual(wrapper.zfar, policy.zfar)
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

    func testRGBTextureLayoutWrapperMatchesPixelFormatPolicy() {
        let wrapper = IRMetalRenderer.rgbTextureLayout(width: 2, height: 2, linesize: 8, byteCount: 16)
        let policy = IRMetalRendererPixelFormatPolicy.rgbTextureLayout(width: 2, height: 2, linesize: 8, byteCount: 16)

        XCTAssertEqual(wrapper?.bytesPerRow, policy?.bytesPerRow)
        XCTAssertEqual(wrapper?.totalByteCount, policy?.totalByteCount)
        XCTAssertNil(IRMetalRendererPixelFormatPolicy.rgbTextureLayout(width: 2, height: 2, linesize: 7, byteCount: 16))
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
