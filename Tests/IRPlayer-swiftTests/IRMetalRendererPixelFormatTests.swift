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

    private func makeRenderer() throws -> IRMetalRenderer {
        guard let device = MTLCreateSystemDefaultDevice(),
              let renderer = IRMetalRenderer(device: device) else {
            throw XCTSkip("Metal device unavailable")
        }
        return renderer
    }

    private func withOffscreenEncoder(
        renderer: IRMetalRenderer,
        _ body: (MTLRenderCommandEncoder) throws -> Void
    ) throws {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: 2,
            height: 2,
            mipmapped: false
        )
        descriptor.usage = [.renderTarget, .shaderRead]
        guard let texture = renderer.device.makeTexture(descriptor: descriptor),
              let commandBuffer = renderer.commandQueue.makeCommandBuffer() else {
            throw XCTSkip("Offscreen Metal rendering unavailable")
        }

        let renderPass = MTLRenderPassDescriptor()
        renderPass.colorAttachments[0].texture = texture
        renderPass.colorAttachments[0].loadAction = .clear
        renderPass.colorAttachments[0].storeAction = .store
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPass) else {
            throw XCTSkip("Offscreen Metal encoder unavailable")
        }

        guard let vertexBuffer = renderer.vertexBuffer else {
            throw XCTSkip("Metal vertex buffer unavailable")
        }
        encoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
        var scaleVector = SIMD2<Float>(repeating: 1)
        encoder.setVertexBytes(&scaleVector, length: MemoryLayout<SIMD2<Float>>.size, index: 1)
        var translationVector = SIMD2<Float>(repeating: 0)
        encoder.setVertexBytes(&translationVector, length: MemoryLayout<SIMD2<Float>>.size, index: 2)

        try body(encoder)
        encoder.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
    }

    private func makeRGBFrame(width: Int = 2, height: Int = 2) -> IRVideoFrameRGB {
        let bytesPerRow = width * 4
        let frame = IRVideoFrameRGB(
            linesize: UInt(bytesPerRow),
            rgb: Data(repeating: 0xff, count: bytesPerRow * height)
        )
        frame.width = width
        frame.height = height
        return frame
    }

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

    func testMetalViewportRejectsMalformedGeometry() {
        let viewport = IRMetalRendererGeometryPolicy.metalViewport(
            drawableSize: CGSize(width: CGFloat.infinity, height: 240),
            viewport: CGRect(x: CGFloat.nan, y: 20, width: 100, height: -50),
            orientation: .bottomLeft
        )

        XCTAssertEqual(viewport.originX, 0)
        XCTAssertEqual(viewport.originY, 0)
        XCTAssertEqual(viewport.width, 0)
        XCTAssertEqual(viewport.height, 0)
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
        let renderer = try makeRenderer()
        let frame = IRVideoFrameRGB(linesize: UInt(Int.max) + 1, rgb: Data([0, 0, 0, 0]))
        frame.width = 1
        frame.height = 1

        XCTAssertNil(renderer.makeRGBTexture(from: frame))
    }

    func testMakeRGBTextureCreatesBGRATextureForValidFrame() throws {
        let renderer = try makeRenderer()
        let texture = renderer.makeRGBTexture(from: makeRGBFrame())

        XCTAssertEqual(texture?.width, 2)
        XCTAssertEqual(texture?.height, 2)
        XCTAssertEqual(texture?.pixelFormat, .bgra8Unorm)
    }

    func testMakeTextureRejectsInvalidSizeAndCreatesValidTexture() throws {
        let renderer = try makeRenderer()
        var bytes = [UInt8](repeating: 0x7f, count: 4)

        bytes.withUnsafeMutableBytes { buffer in
            XCTAssertNil(renderer.makeTexture(width: 0,
                                              height: 1,
                                              pixelFormat: .r8Unorm,
                                              bytes: buffer.baseAddress!))

            let texture = renderer.makeTexture(width: 2,
                                               height: 2,
                                               pixelFormat: .r8Unorm,
                                               bytes: buffer.baseAddress!)
            XCTAssertEqual(texture?.width, 2)
            XCTAssertEqual(texture?.height, 2)
            XCTAssertEqual(texture?.pixelFormat, .r8Unorm)
        }
    }

    func testPixelRendererSelectionMatchesFrameTypes() throws {
        let renderer = try makeRenderer()
        var pixelBuffer: CVPixelBuffer?
        CVPixelBufferCreate(kCFAllocatorDefault,
                            2,
                            2,
                            kCVPixelFormatType_32BGRA,
                            nil,
                            &pixelBuffer)
        let cvFrame = IRFFCVYUVVideoFrame(pixelBuffer: try XCTUnwrap(pixelBuffer))

        XCTAssertTrue(renderer.pixelRenderer(for: cvFrame) is IRMetalPixelRendererNV12)
        XCTAssertTrue(renderer.pixelRenderer(for: IRFFAVYUVVideoFrame()) is IRMetalPixelRendererI420)
        XCTAssertTrue(renderer.pixelRenderer(for: makeRGBFrame()) is IRMetalPixelRendererRGB)
        XCTAssertNil(renderer.pixelRenderer(for: IRFFVideoFrame()))
    }

    func testRenderRGBDrawsValidFrameToOffscreenEncoder() throws {
        let renderer = try makeRenderer()
        guard renderer.pipelineRGB != nil else {
            throw XCTSkip("RGB Metal pipeline unavailable")
        }

        try withOffscreenEncoder(renderer: renderer) { encoder in
            XCTAssertTrue(renderer.renderRGB(rgbFrame: makeRGBFrame(), encoder: encoder))
        }
    }

    func testRGBPixelRendererRenders2DAndRejectsMesh() throws {
        let renderer = try makeRenderer()
        guard renderer.pipelineRGB != nil else {
            throw XCTSkip("RGB Metal pipeline unavailable")
        }
        let pixelRenderer = IRMetalPixelRendererRGB()
        let frame = makeRGBFrame()

        try withOffscreenEncoder(renderer: renderer) { encoder in
            XCTAssertTrue(pixelRenderer.render2D(renderer: renderer, frame: frame, encoder: encoder))
            XCTAssertFalse(pixelRenderer.renderMesh(renderer: renderer,
                                                    frame: frame,
                                                    encoder: encoder,
                                                    indexCount: 0,
                                                    indexBuffer: renderer.vertexBuffer!))
        }
    }

    func testRGBPixelRendererRejectsRenderingWhenPipelineIsMissing() throws {
        let renderer = try makeRenderer()
        renderer.pipelineRGB = nil
        let pixelRenderer = IRMetalPixelRendererRGB()
        let frame = makeRGBFrame()

        try withOffscreenEncoder(renderer: renderer) { encoder in
            XCTAssertFalse(renderer.renderRGB(rgbFrame: frame, encoder: encoder))
            XCTAssertFalse(pixelRenderer.render2D(renderer: renderer, frame: frame, encoder: encoder))
            XCTAssertFalse(pixelRenderer.renderMesh(renderer: renderer,
                                                    frame: frame,
                                                    encoder: encoder,
                                                    indexCount: 0,
                                                    indexBuffer: renderer.vertexBuffer!))
        }
    }

    func testPixelRenderersRejectMismatchedFrameTypes() throws {
        let renderer = try makeRenderer()
        let nv12Renderer = IRMetalPixelRendererNV12()
        let i420Renderer = IRMetalPixelRendererI420()
        let rgbFrame = makeRGBFrame()
        let params = IRMetalRenderer.Fish2PanoParams(
            fishwidth: 2,
            fishheight: 2,
            panowidth: 2,
            panoheight: 2,
            antialias: 0,
            offsetX: 0
        )

        try withOffscreenEncoder(renderer: renderer) { encoder in
            XCTAssertFalse(nv12Renderer.render2D(renderer: renderer, frame: rgbFrame, encoder: encoder))
            XCTAssertFalse(nv12Renderer.renderMesh(renderer: renderer,
                                                   frame: rgbFrame,
                                                   encoder: encoder,
                                                   indexCount: 0,
                                                   indexBuffer: renderer.vertexBuffer!))
            XCTAssertFalse(nv12Renderer.renderFish2Pano(renderer: renderer,
                                                        frame: rgbFrame,
                                                        encoder: encoder,
                                                        params: params,
                                                        texUVTextures: []))

            XCTAssertFalse(i420Renderer.render2D(renderer: renderer, frame: rgbFrame, encoder: encoder))
            XCTAssertFalse(i420Renderer.renderMesh(renderer: renderer,
                                                   frame: rgbFrame,
                                                   encoder: encoder,
                                                   indexCount: 0,
                                                   indexBuffer: renderer.vertexBuffer!))
            XCTAssertFalse(i420Renderer.renderFish2Pano(renderer: renderer,
                                                        frame: rgbFrame,
                                                        encoder: encoder,
                                                        params: params,
                                                        texUVTextures: []))
        }
    }
}
