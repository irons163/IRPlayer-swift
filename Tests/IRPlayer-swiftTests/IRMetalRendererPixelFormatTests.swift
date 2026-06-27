//
//  IRMetalRendererPixelFormatTests.swift
//  IRPlayer-swiftTests
//
//  Created by Codex on 2026/6/2.
//

import Metal
import CoreVideo
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

    private func makeOffscreenDrawable(renderer: IRMetalRenderer,
                                       width: Int = 4,
                                       height: Int = 2) throws -> IRPixelFormatTestMetalDrawable {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm,
                                                                  width: width,
                                                                  height: height,
                                                                  mipmapped: false)
        descriptor.usage = [.renderTarget, .shaderRead]
        guard let texture = renderer.device.makeTexture(descriptor: descriptor) else {
            throw XCTSkip("Offscreen Metal drawable texture unavailable")
        }
        return IRPixelFormatTestMetalDrawable(texture: texture)
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

    private func makeIndexBuffer(renderer: IRMetalRenderer) throws -> MTLBuffer {
        var indices: [UInt16] = [0, 1, 2]
        guard let buffer = renderer.device.makeBuffer(bytes: &indices,
                                                      length: MemoryLayout<UInt16>.stride * indices.count,
                                                      options: .storageModeShared) else {
            throw XCTSkip("Metal index buffer unavailable")
        }
        return buffer
    }

    private func makeFish2PanoParams() -> IRMetalRenderer.Fish2PanoParams {
        return IRMetalRenderer.Fish2PanoParams(
            fishwidth: 2,
            fishheight: 2,
            panowidth: 2,
            panoheight: 2,
            antialias: 0,
            offsetX: 0
        )
    }

    private func makePixelBuffer(width: Int = 2,
                                 height: Int = 2,
                                 format: OSType) throws -> CVPixelBuffer {
        var pixelBuffer: CVPixelBuffer?
        let attributes: [String: Any] = [
            kCVPixelBufferMetalCompatibilityKey as String: true,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:]
        ]
        let status = CVPixelBufferCreate(kCFAllocatorDefault,
                                         width,
                                         height,
                                         format,
                                         attributes as CFDictionary,
                                         &pixelBuffer)
        guard status == kCVReturnSuccess, let pixelBuffer else {
            throw XCTSkip("CVPixelBuffer unavailable")
        }
        return pixelBuffer
    }

    private func withI420Frame(
        width: Int = 2,
        height: Int = 2,
        _ body: (IRFFAVYUVVideoFrame) throws -> Void
    ) rethrows {
        var y = [UInt8](repeating: 0x10, count: max(1, width * height))
        var u = [UInt8](repeating: 0x80, count: max(1, (width / 2) * (height / 2)))
        var v = [UInt8](repeating: 0x80, count: max(1, (width / 2) * (height / 2)))
        let frame = IRFFAVYUVVideoFrame()
        frame.width = width
        frame.height = height

        try y.withUnsafeMutableBufferPointer { yBuffer in
            try u.withUnsafeMutableBufferPointer { uBuffer in
                try v.withUnsafeMutableBufferPointer { vBuffer in
                    frame.channelPixels[IRYUVChannel.luma.rawValue] = yBuffer.baseAddress
                    frame.channelPixels[IRYUVChannel.chromaB.rawValue] = uBuffer.baseAddress
                    frame.channelPixels[IRYUVChannel.chromaR.rawValue] = vBuffer.baseAddress
                    try body(frame)
                }
            }
        }
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

    func testMakeNV12TexturesCreatesPlaneTexturesForBiPlanarBuffer() throws {
        let renderer = try makeRenderer()
        let pixelBuffer = try makePixelBuffer(format: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange)
        let frame = IRFFCVYUVVideoFrame(pixelBuffer: pixelBuffer)

        let textures = renderer.makeNV12Textures(from: frame)

        XCTAssertEqual(textures?.y.width, 2)
        XCTAssertEqual(textures?.y.height, 2)
        XCTAssertEqual(textures?.y.pixelFormat, .r8Unorm)
        XCTAssertEqual(textures?.uv.width, 1)
        XCTAssertEqual(textures?.uv.height, 1)
        XCTAssertEqual(textures?.uv.pixelFormat, .rg8Unorm)
    }

    func testMakeNV12TexturesRejectsNonBiPlanarPixelBuffer() throws {
        let renderer = try makeRenderer()
        let pixelBuffer = try makePixelBuffer(format: kCVPixelFormatType_32BGRA)
        let frame = IRFFCVYUVVideoFrame(pixelBuffer: pixelBuffer)

        XCTAssertNil(renderer.makeNV12Textures(from: frame))
    }

    func testMakeBGRATextureCreatesTextureForBGRAAndRejectsNV12() throws {
        let renderer = try makeRenderer()
        let bgraFrame = IRFFCVYUVVideoFrame(pixelBuffer: try makePixelBuffer(format: kCVPixelFormatType_32BGRA))
        let nv12Frame = IRFFCVYUVVideoFrame(pixelBuffer: try makePixelBuffer(format: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange))

        let texture = renderer.makeBGRATexture(from: bgraFrame)

        XCTAssertEqual(texture?.width, 2)
        XCTAssertEqual(texture?.height, 2)
        XCTAssertEqual(texture?.pixelFormat, .bgra8Unorm)
        XCTAssertNil(renderer.makeBGRATexture(from: nv12Frame))
    }

    func testMakeI420TexturesRejectsMissingPlanesAndInvalidSize() throws {
        let renderer = try makeRenderer()
        let missingPlanes = IRFFAVYUVVideoFrame()
        missingPlanes.width = 2
        missingPlanes.height = 2
        XCTAssertNil(renderer.makeI420Textures(from: missingPlanes))

        withI420Frame(width: 0, height: 2) { frame in
            XCTAssertNil(renderer.makeI420Textures(from: frame))
        }
    }

    func testMakeI420TexturesCreatesPlaneTexturesForValidFrame() throws {
        let renderer = try makeRenderer()

        withI420Frame { frame in
            let textures = renderer.makeI420Textures(from: frame)

            XCTAssertEqual(textures?.y.width, 2)
            XCTAssertEqual(textures?.y.height, 2)
            XCTAssertEqual(textures?.y.pixelFormat, .r8Unorm)
            XCTAssertEqual(textures?.u.width, 1)
            XCTAssertEqual(textures?.u.height, 1)
            XCTAssertEqual(textures?.u.pixelFormat, .r8Unorm)
            XCTAssertEqual(textures?.v.width, 1)
            XCTAssertEqual(textures?.v.height, 1)
            XCTAssertEqual(textures?.v.pixelFormat, .r8Unorm)
        }
    }

    func testPixelRendererSelectionMatchesFrameTypes() throws {
        let renderer = try makeRenderer()
        let cvFrame = IRFFCVYUVVideoFrame(pixelBuffer: try makePixelBuffer(format: kCVPixelFormatType_32BGRA))

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

    func testRenderBGRADrawsValidFrameToOffscreenEncoder() throws {
        let renderer = try makeRenderer()
        guard renderer.pipelineRGB != nil else {
            throw XCTSkip("RGB Metal pipeline unavailable")
        }
        let frame = IRFFCVYUVVideoFrame(pixelBuffer: try makePixelBuffer(format: kCVPixelFormatType_32BGRA))

        try withOffscreenEncoder(renderer: renderer) { encoder in
            XCTAssertTrue(renderer.renderBGRA(cvFrame: frame, encoder: encoder))
        }
    }

    func testRenderI420DrawsValidFrameToOffscreenEncoder() throws {
        let renderer = try makeRenderer()
        guard renderer.pipelineI420 != nil else {
            throw XCTSkip("I420 Metal pipeline unavailable")
        }

        try withI420Frame { frame in
            try withOffscreenEncoder(renderer: renderer) { encoder in
                XCTAssertTrue(renderer.renderI420(yuvFrame: frame, encoder: encoder))
            }
        }
    }

    func testRenderMultiRejectsUnsupportedFrameAfterWalkingViewportList() throws {
        let renderer = try makeRenderer()
        let drawable = try makeOffscreenDrawable(renderer: renderer)
        let frame = IRFFVideoFrame()
        frame.width = 2
        frame.height = 2

        XCTAssertFalse(renderer.renderMulti(frame: frame,
                                            to: drawable,
                                            drawableSize: CGSize(width: 4, height: 2),
                                            viewports: [
                                                CGRect(x: 0, y: 0, width: 2, height: 2),
                                                CGRect(x: 2, y: 0, width: 0, height: 2),
                                                CGRect(x: 2, y: 0, width: 2, height: 2)
                                            ],
                                            contentModes: [
                                                .scaleAspectFit,
                                                .scaleAspectFill,
                                                .scaleToFill
                                            ],
                                            zoomScales: [1.25],
                                            translations: [SIMD2<Float>(0.1, -0.1)]))
    }

    func testRenderMeshHelpersRejectRenderingWhenPipelinesAreMissing() throws {
        let renderer = try makeRenderer()
        renderer.pipelineNV12Mesh = nil
        renderer.pipelineRGBMesh = nil
        renderer.pipelineI420Mesh = nil
        let indexBuffer = try makeIndexBuffer(renderer: renderer)
        let bgraFrame = IRFFCVYUVVideoFrame(pixelBuffer: try makePixelBuffer(format: kCVPixelFormatType_32BGRA))
        let nv12Frame = IRFFCVYUVVideoFrame(pixelBuffer: try makePixelBuffer(format: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange))

        try withI420Frame { yuvFrame in
            try withOffscreenEncoder(renderer: renderer) { encoder in
                XCTAssertFalse(renderer.renderNV12Mesh(cvFrame: nv12Frame,
                                                       encoder: encoder,
                                                       indexCount: 3,
                                                       indexBuffer: indexBuffer))
                XCTAssertFalse(renderer.renderBGRAMesh(cvFrame: bgraFrame,
                                                       encoder: encoder,
                                                       indexCount: 3,
                                                       indexBuffer: indexBuffer))
                XCTAssertFalse(renderer.renderI420Mesh(yuvFrame: yuvFrame,
                                                       encoder: encoder,
                                                       indexCount: 3,
                                                       indexBuffer: indexBuffer))
            }
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

    func testPixelRenderersRejectRenderingWhenTypedPipelinesAreMissing() throws {
        let renderer = try makeRenderer()
        renderer.pipelineNV12 = nil
        renderer.pipelineRGB = nil
        renderer.pipelineI420 = nil
        renderer.pipelineNV12Mesh = nil
        renderer.pipelineRGBMesh = nil
        renderer.pipelineI420Mesh = nil
        renderer.pipelineNV12Fish2Pano = nil
        renderer.pipelineRGBFish2Pano = nil
        renderer.pipelineI420Fish2Pano = nil
        let nv12Renderer = IRMetalPixelRendererNV12()
        let i420Renderer = IRMetalPixelRendererI420()
        let rgbRenderer = IRMetalPixelRendererRGB()
        let indexBuffer = try makeIndexBuffer(renderer: renderer)
        let nv12Frame = IRFFCVYUVVideoFrame(pixelBuffer: try makePixelBuffer(format: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange))
        let bgraFrame = IRFFCVYUVVideoFrame(pixelBuffer: try makePixelBuffer(format: kCVPixelFormatType_32BGRA))
        let rgbFrame = makeRGBFrame()
        let params = makeFish2PanoParams()

        try withI420Frame { frame in
            try withOffscreenEncoder(renderer: renderer) { encoder in
                XCTAssertFalse(nv12Renderer.render2D(renderer: renderer, frame: nv12Frame, encoder: encoder))
                XCTAssertFalse(nv12Renderer.render2D(renderer: renderer, frame: bgraFrame, encoder: encoder))
                XCTAssertFalse(nv12Renderer.renderMesh(renderer: renderer,
                                                       frame: nv12Frame,
                                                       encoder: encoder,
                                                       indexCount: 3,
                                                       indexBuffer: indexBuffer))
                XCTAssertFalse(nv12Renderer.renderMesh(renderer: renderer,
                                                       frame: bgraFrame,
                                                       encoder: encoder,
                                                       indexCount: 3,
                                                       indexBuffer: indexBuffer))
                XCTAssertFalse(nv12Renderer.renderFish2Pano(renderer: renderer,
                                                            frame: nv12Frame,
                                                            encoder: encoder,
                                                            params: params,
                                                            texUVTextures: []))
                XCTAssertFalse(nv12Renderer.renderFish2Pano(renderer: renderer,
                                                            frame: bgraFrame,
                                                            encoder: encoder,
                                                            params: params,
                                                            texUVTextures: []))

                XCTAssertFalse(i420Renderer.render2D(renderer: renderer, frame: frame, encoder: encoder))
                XCTAssertFalse(i420Renderer.renderMesh(renderer: renderer,
                                                       frame: frame,
                                                       encoder: encoder,
                                                       indexCount: 3,
                                                       indexBuffer: indexBuffer))
                XCTAssertFalse(i420Renderer.renderFish2Pano(renderer: renderer,
                                                            frame: frame,
                                                            encoder: encoder,
                                                            params: params,
                                                            texUVTextures: []))

                XCTAssertFalse(rgbRenderer.render2D(renderer: renderer, frame: rgbFrame, encoder: encoder))
                XCTAssertFalse(rgbRenderer.renderFish2Pano(renderer: renderer,
                                                           frame: rgbFrame,
                                                           encoder: encoder,
                                                           params: params,
                                                           texUVTextures: []))
            }
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
        let params = makeFish2PanoParams()

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

private final class IRPixelFormatTestMetalDrawable: NSObject, CAMetalDrawable {
    let texture: MTLTexture
    let layer = CAMetalLayer()

    init(texture: MTLTexture) {
        self.texture = texture
        super.init()
    }

    func present() {}

    func present(at presentationTime: CFTimeInterval) {
        present()
    }

    @objc func presentAfterMinimumDuration(_ duration: CFTimeInterval) {
        present()
    }

    @objc func addPresentScheduledHandler(_ block: @escaping (MTLDrawable) -> Void) {
        block(self)
    }

    @objc func addPresentedHandler(_ block: @escaping (MTLDrawable) -> Void) {
        block(self)
    }
}
