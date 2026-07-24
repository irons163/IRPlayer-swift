//
//  IRMetalRendererPixelFormatTests.swift
//  IRPlayer-swiftTests
//
//  Created by Codex on 2026/6/2.
//

import Metal
import CoreVideo
import IRFFMpeg
import simd
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

    private func makeFish2PanoLookupTexture(renderer: IRMetalRenderer,
                                            width: Int = 2,
                                            height: Int = 2) throws -> MTLTexture {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rg32Float,
                                                                  width: width,
                                                                  height: height,
                                                                  mipmapped: false)
        descriptor.usage = .shaderRead
        guard let texture = renderer.device.makeTexture(descriptor: descriptor) else {
            throw XCTSkip("Fish2pano lookup texture unavailable")
        }

        let bytesPerRow = width * MemoryLayout<Float>.stride * 2
        let values = [Float](repeating: 1, count: width * height * 2)
        values.withUnsafeBytes { buffer in
            texture.replace(region: MTLRegionMake2D(0, 0, width, height),
                            mipmapLevel: 0,
                            withBytes: buffer.baseAddress!,
                            bytesPerRow: bytesPerRow)
        }
        return texture
    }

    private func withOffscreenEncoder(
        renderer: IRMetalRenderer,
        _ body: (
            MTLRenderCommandEncoder,
            IRMetalCommandResources
        ) throws -> Void
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

        encoder.setVertexBuffer(
            renderer.vertexBuffer,
            offset: 0,
            index: 0
        )
        var scaleVector = SIMD2<Float>(repeating: 1)
        encoder.setVertexBytes(&scaleVector, length: MemoryLayout<SIMD2<Float>>.size, index: 1)
        var translationVector = SIMD2<Float>(repeating: 0)
        encoder.setVertexBytes(&translationVector, length: MemoryLayout<SIMD2<Float>>.size, index: 2)

        let resources = IRMetalCommandResources()
        try body(encoder, resources)
        encoder.endEncoding()
        XCTAssertTrue(resources.submit(to: commandBuffer))
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
    }

    private func makeRGBFrame(width: Int = 2, height: Int = 2) -> IRVideoFrameRGB {
        let bytesPerRow = width * 4
        return IRVideoFrameRGB(
            width: width,
            height: height,
            pixelFormat: .bgra32,
            bytesPerRow: bytesPerRow,
            data: Data(
                repeating: 0xff,
                count: bytesPerRow * height
            )
        )!
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

    private func makeFisheyeMesh(renderer: IRMetalRenderer) throws -> IRMetalFisheyeMesh {
        let mesh = IRMetalFisheyeMesh(
            device: renderer.device,
            positions: [
                SIMD3<Float>(-1, -1, 0),
                SIMD3<Float>(1, -1, 0),
                SIMD3<Float>(0, 1, 0)
            ],
            texcoords: [
                SIMD2<Float>(0, 0),
                SIMD2<Float>(1, 0),
                SIMD2<Float>(0.5, 1)
            ],
            indices: [0, 1, 2]
        )
        return try XCTUnwrap(mesh)
    }

    private func makeFish2PanoParams() -> IRMetalRenderer.Fish2PanoParams {
        return IRMetalRenderer.Fish2PanoParams(
            fishwidth: 2,
            fishheight: 2,
            panowidth: 2,
            panoheight: 2,
            antialias: 1,
            offsetX: 0
        )
    }

    private func makeIdentityMatrix() -> simd_float4x4 {
        return simd_float4x4(diagonal: SIMD4<Float>(repeating: 1))
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
        let chromaWidth = max(1, (width + 1) / 2)
        let chromaHeight = max(1, (height + 1) / 2)
        var y = [UInt8](
            repeating: 0x10,
            count: max(1, width * height)
        )
        var u = [UInt8](
            repeating: 0x80,
            count: chromaWidth * chromaHeight
        )
        var v = [UInt8](
            repeating: 0x80,
            count: chromaWidth * chromaHeight
        )
        var avFrame = AVFrame()
        avFrame.format = AV_PIX_FMT_YUV420P.rawValue
        avFrame.linesize.0 = Int32(max(1, width))
        avFrame.linesize.1 = Int32(chromaWidth)
        avFrame.linesize.2 = Int32(chromaWidth)
        let frame = IRFFAVYUVVideoFrame()

        y.withUnsafeMutableBufferPointer { yBuffer in
            u.withUnsafeMutableBufferPointer { uBuffer in
                v.withUnsafeMutableBufferPointer { vBuffer in
                    avFrame.data.0 = yBuffer.baseAddress
                    avFrame.data.1 = uBuffer.baseAddress
                    avFrame.data.2 = vBuffer.baseAddress
                    withUnsafePointer(to: &avFrame) { pointer in
                        frame.setFrameData(
                            pointer,
                            width: width,
                            height: height
                        )
                    }
                }
            }
        }
        try body(frame)
    }

    func testRendererExposesCompleteImmutableResources() throws {
        let renderer = try makeRenderer()

        let pipelines: [MTLRenderPipelineState] = [
            renderer.pipelineNV12,
            renderer.pipelineI420,
            renderer.pipelineRGB,
            renderer.pipelineNV12Mesh,
            renderer.pipelineI420Mesh,
            renderer.pipelineRGBMesh,
            renderer.pipelineNV12Fish2Pano,
            renderer.pipelineI420Fish2Pano,
            renderer.pipelineRGBFish2Pano,
            renderer.pipelineDistortion
        ]
        let quadBuffers: [MTLBuffer] = [
            renderer.vertexBuffer,
            renderer.vertexBufferLeft,
            renderer.vertexBufferRight
        ]

        XCTAssertEqual(pipelines.count, 10)
        XCTAssertEqual(quadBuffers.count, 3)
        XCTAssertTrue(quadBuffers.allSatisfy { $0.length > 0 })
        XCTAssertEqual(
            renderer.resources.diagnostics.pipelineCount,
            pipelines.count
        )
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

    func testFish2PanoInputValidationRejectsInvalidParameters() {
        let validParams = IRMetalRenderer.Fish2PanoParams(fishwidth: 2,
                                                          fishheight: 2,
                                                          panowidth: 4,
                                                          panoheight: 2,
                                                          antialias: 1,
                                                          offsetX: 0)
        XCTAssertTrue(IRMetalRenderer.fish2PanoInputsAreValid(params: validParams, texUVTextureCount: 1))

        var invalidParams = validParams
        invalidParams.antialias = 0
        XCTAssertFalse(IRMetalRenderer.fish2PanoInputsAreValid(params: invalidParams, texUVTextureCount: 0))

        invalidParams = validParams
        invalidParams.fishwidth = 0
        XCTAssertFalse(IRMetalRenderer.fish2PanoInputsAreValid(params: invalidParams, texUVTextureCount: 1))

        invalidParams = validParams
        invalidParams.offsetX = .nan
        XCTAssertFalse(IRMetalRenderer.fish2PanoInputsAreValid(params: invalidParams, texUVTextureCount: 1))

        invalidParams = validParams
        invalidParams.antialias = 4
        XCTAssertFalse(IRMetalRenderer.fish2PanoInputsAreValid(params: invalidParams, texUVTextureCount: 16))

        XCTAssertFalse(IRMetalRenderer.fish2PanoInputsAreValid(params: validParams, texUVTextureCount: 0))
        invalidParams = validParams
        invalidParams.antialias = 3
        XCTAssertTrue(
            IRMetalRenderer.fish2PanoInputsAreValid(
                params: invalidParams,
                texUVTextureCount: 9
            )
        )
        XCTAssertFalse(
            IRMetalRenderer.fish2PanoInputsAreValid(
                params: invalidParams,
                texUVTextureCount: 8
            )
        )
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

    func testMakeRGBTextureCreatesBGRATextureForValidFrame() throws {
        let renderer = try makeRenderer()
        let texture = renderer.makeRGBTexture(from: makeRGBFrame())

        XCTAssertEqual(texture?.width, 2)
        XCTAssertEqual(texture?.height, 2)
        XCTAssertEqual(texture?.pixelFormat, .bgra8Unorm)
    }

    func testMakeRGBTextureConvertsRGB24ToExactRGBA8Bytes()
        throws {
        let renderer = try makeRenderer()
        let frame = try XCTUnwrap(
            IRVideoFrameRGB(
                width: 2,
                height: 1,
                pixelFormat: .rgb24,
                bytesPerRow: 6,
                data: Data([
                    255, 0, 0,
                    0, 255, 0
                ])
            )
        )
        let texture = try XCTUnwrap(
            renderer.makeRGBTexture(from: frame)
        )
        var bytes = [UInt8](repeating: 0, count: 8)

        texture.getBytes(
            &bytes,
            bytesPerRow: 8,
            from: MTLRegionMake2D(0, 0, 2, 1),
            mipmapLevel: 0
        )

        XCTAssertEqual(texture.pixelFormat, .rgba8Unorm)
        XCTAssertEqual(
            bytes,
            [
                255, 0, 0, 255,
                0, 255, 0, 255
            ]
        )
    }

    func testMakeRGBTexturePreservesExactBGRA32Bytes() throws {
        let renderer = try makeRenderer()
        let source: [UInt8] = [1, 2, 3, 255]
        let frame = try XCTUnwrap(
            IRVideoFrameRGB(
                width: 1,
                height: 1,
                pixelFormat: .bgra32,
                bytesPerRow: 4,
                data: Data(source)
            )
        )
        let texture = try XCTUnwrap(
            renderer.makeRGBTexture(from: frame)
        )
        var bytes = [UInt8](repeating: 0, count: 4)

        texture.getBytes(
            &bytes,
            bytesPerRow: 4,
            from: MTLRegionMake2D(0, 0, 1, 1),
            mipmapLevel: 0
        )

        XCTAssertEqual(texture.pixelFormat, .bgra8Unorm)
        XCTAssertEqual(bytes, source)
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

        let generation = try XCTUnwrap(
            renderer.makeNV12TextureGeneration(from: frame)
        )
        guard case let .nv12(y, uv) =
                generation.textures else {
            return XCTFail("expected NV12 textures")
        }

        XCTAssertEqual(y.width, 2)
        XCTAssertEqual(y.height, 2)
        XCTAssertEqual(y.pixelFormat, .r8Unorm)
        XCTAssertEqual(uv.width, 1)
        XCTAssertEqual(uv.height, 1)
        XCTAssertEqual(uv.pixelFormat, .rg8Unorm)
    }

    func testMakeNV12TexturesRejectsNonBiPlanarPixelBuffer() throws {
        let renderer = try makeRenderer()
        let pixelBuffer = try makePixelBuffer(format: kCVPixelFormatType_32BGRA)
        let frame = IRFFCVYUVVideoFrame(pixelBuffer: pixelBuffer)

        XCTAssertNil(
            renderer.makeNV12TextureGeneration(from: frame)
        )
    }

    func testMakeBGRATextureCreatesTextureForBGRAAndRejectsNV12() throws {
        let renderer = try makeRenderer()
        let bgraFrame = IRFFCVYUVVideoFrame(pixelBuffer: try makePixelBuffer(format: kCVPixelFormatType_32BGRA))
        let nv12Frame = IRFFCVYUVVideoFrame(pixelBuffer: try makePixelBuffer(format: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange))

        let generation = try XCTUnwrap(
            renderer.makeBGRATextureGeneration(
                from: bgraFrame
            )
        )
        guard case let .bgra(texture) =
                generation.textures else {
            return XCTFail("expected BGRA texture")
        }

        XCTAssertEqual(texture.width, 2)
        XCTAssertEqual(texture.height, 2)
        XCTAssertEqual(texture.pixelFormat, .bgra8Unorm)
        XCTAssertNil(
            renderer.makeBGRATextureGeneration(
                from: nv12Frame
            )
        )
    }

    func testMakeI420TexturesRejectsMissingPlanesAndInvalidSize() throws {
        let renderer = try makeRenderer()
        let missingPlanes = IRFFAVYUVVideoFrame()
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

        try withOffscreenEncoder(renderer: renderer) {
            encoder,
            resources in
            XCTAssertTrue(
                renderer.renderRGB(
                    rgbFrame: makeRGBFrame(),
                    encoder: encoder,
                    resources: resources
                )
            )
        }
    }

    func testRenderBGRADrawsValidFrameToOffscreenEncoder() throws {
        let renderer = try makeRenderer()
        let frame = IRFFCVYUVVideoFrame(pixelBuffer: try makePixelBuffer(format: kCVPixelFormatType_32BGRA))

        try withOffscreenEncoder(renderer: renderer) {
            encoder,
            resources in
            XCTAssertTrue(
                renderer.renderBGRA(
                    cvFrame: frame,
                    encoder: encoder,
                    resources: resources
                )
            )
        }
    }

    func testRenderI420DrawsValidFrameToOffscreenEncoder() throws {
        let renderer = try makeRenderer()

        try withI420Frame { frame in
            try withOffscreenEncoder(renderer: renderer) {
                encoder,
                resources in
                XCTAssertTrue(
                    renderer.renderI420(
                        yuvFrame: frame,
                        encoder: encoder,
                        resources: resources
                    )
                )
            }
        }
    }

    func testRenderMultiRejectsUnsupportedFrameAfterWalkingViewportList() throws {
        let renderer = try makeRenderer()
        let drawable = try makeOffscreenDrawable(renderer: renderer)
        let frame = IRFFVideoFrame()
        XCTAssertTrue(frame.setDimensions(width: 2, height: 2))

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

    func testRenderMultiDrawsNV12AcrossViewports() throws {
        let renderer = try makeRenderer()
        let drawable = try makeOffscreenDrawable(
            renderer: renderer
        )
        let frame = IRFFCVYUVVideoFrame(
            pixelBuffer: try makePixelBuffer(
                format:
                    kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
            )
        )

        XCTAssertTrue(
            renderer.renderMulti(
                frame: frame,
                to: drawable,
                drawableSize: CGSize(width: 4, height: 2),
                viewports: [
                    CGRect(x: 0, y: 0, width: 2, height: 2),
                    CGRect(x: 2, y: 0, width: 2, height: 2)
                ],
                contentModes: [
                    .scaleAspectFit,
                    .scaleAspectFill
                ],
                zoomScales: [1, 1],
                translations: [.zero, .zero]
            )
        )
    }

    func testRenderFish2PanoEncodesValidInputsAndRejectsUnsupportedFrame() throws {
        let renderer = try makeRenderer()
        let drawable = try makeOffscreenDrawable(renderer: renderer)
        let lookupTexture = try makeFish2PanoLookupTexture(renderer: renderer)
        let frame = IRFFVideoFrame()
        XCTAssertTrue(frame.setDimensions(width: 2, height: 2))

        XCTAssertFalse(renderer.renderFish2Pano(frame: frame,
                                                params: makeFish2PanoParams(),
                                                texUVTextures: [lookupTexture],
                                                to: drawable,
                                                drawableSize: CGSize(width: 4, height: 2),
                                                viewport: CGRect(x: 0, y: 0, width: 4, height: 2),
                                                contentMode: .scaleToFill,
                                                outputSize: CGSize(width: 2, height: 2),
                                                zoomScale: 1,
                                                translation: .zero))
    }

    func testRenderFisheyeDrawsValidI420Frame() throws {
        let renderer = try makeRenderer()
        let mesh = try makeFisheyeMesh(renderer: renderer)
        let drawable = try makeOffscreenDrawable(renderer: renderer, width: 4, height: 4)

        withI420Frame { frame in
            XCTAssertTrue(renderer.renderFisheye(frame: frame,
                                                mesh: mesh,
                                                mvp: makeIdentityMatrix(),
                                                textureMatrix: makeIdentityMatrix(),
                                                to: drawable,
                                                drawableSize: CGSize(width: 4, height: 4),
                                                viewport: CGRect(x: 0, y: 0, width: 4, height: 4)))
        }
    }

    func testRenderFisheyeDrawsValidNV12Frame() throws {
        let renderer = try makeRenderer()
        let mesh = try makeFisheyeMesh(renderer: renderer)
        let drawable = try makeOffscreenDrawable(renderer: renderer, width: 4, height: 4)
        let frame = IRFFCVYUVVideoFrame(pixelBuffer: try makePixelBuffer(format: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange))

        XCTAssertTrue(renderer.renderFisheye(frame: frame,
                                            mesh: mesh,
                                            mvp: makeIdentityMatrix(),
                                            textureMatrix: makeIdentityMatrix(),
                                            to: drawable,
                                            drawableSize: CGSize(width: 4, height: 4),
                                            viewport: CGRect(x: 0, y: 0, width: 4, height: 4)))
    }

    func testRenderFisheyeFallsBackToBGRAMeshForBGRAFrame() throws {
        let renderer = try makeRenderer()
        let mesh = try makeFisheyeMesh(renderer: renderer)
        let drawable = try makeOffscreenDrawable(renderer: renderer, width: 4, height: 4)
        let frame = IRFFCVYUVVideoFrame(pixelBuffer: try makePixelBuffer(format: kCVPixelFormatType_32BGRA))

        XCTAssertTrue(renderer.renderFisheye(frame: frame,
                                            mesh: mesh,
                                            mvp: makeIdentityMatrix(),
                                            textureMatrix: makeIdentityMatrix(),
                                            to: drawable,
                                            drawableSize: CGSize(width: 4, height: 4),
                                            viewport: CGRect(x: 0, y: 0, width: 4, height: 4)))
    }

    func testRenderFisheyeMultiDrawsValidI420FrameAcrossViewports() throws {
        let renderer = try makeRenderer()
        let mesh = try makeFisheyeMesh(renderer: renderer)
        let drawable = try makeOffscreenDrawable(renderer: renderer, width: 4, height: 4)

        withI420Frame { frame in
            XCTAssertTrue(renderer.renderFisheyeMulti(frame: frame,
                                                     mesh: mesh,
                                                     mvpList: [
                                                        makeIdentityMatrix(),
                                                        makeIdentityMatrix()
                                                     ],
                                                     textureMatrix: makeIdentityMatrix(),
                                                     to: drawable,
                                                     drawableSize: CGSize(width: 4, height: 4),
                                                     viewports: [
                                                        CGRect(x: 0, y: 0, width: 2, height: 4),
                                                        CGRect(x: 2, y: 0, width: 2, height: 4)
                                                     ]))
        }
    }

    func testRGBPixelRendererRendersFish2PanoWithValidInputs() throws {
        let renderer = try makeRenderer()
        let pixelRenderer = IRMetalPixelRendererRGB()
        let frame = makeRGBFrame()
        let lookupTexture = try makeFish2PanoLookupTexture(renderer: renderer)

        try withOffscreenEncoder(renderer: renderer) {
            encoder,
            resources in
            XCTAssertTrue(pixelRenderer.renderFish2Pano(renderer: renderer,
                                                        frame: frame,
                                                        encoder: encoder,
                                                        params: makeFish2PanoParams(),
                                                        texUVTextures: [lookupTexture],
                                                        resources: resources))
        }
    }

    func testI420PixelRendererRendersFish2PanoWithValidInputs() throws {
        let renderer = try makeRenderer()
        let pixelRenderer = IRMetalPixelRendererI420()
        let lookupTexture = try makeFish2PanoLookupTexture(renderer: renderer)

        try withI420Frame { frame in
            try withOffscreenEncoder(renderer: renderer) {
                encoder,
                resources in
                XCTAssertTrue(pixelRenderer.renderFish2Pano(renderer: renderer,
                                                            frame: frame,
                                                            encoder: encoder,
                                                            params: makeFish2PanoParams(),
                                                            texUVTextures: [lookupTexture],
                                                            resources: resources))
            }
        }
    }

    func testNV12PixelRendererRendersFish2PanoAndFallsBackToBGRA() throws {
        let renderer = try makeRenderer()
        let pixelRenderer = IRMetalPixelRendererNV12()
        let lookupTexture = try makeFish2PanoLookupTexture(renderer: renderer)
        let nv12Frame = IRFFCVYUVVideoFrame(pixelBuffer: try makePixelBuffer(format: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange))
        let bgraFrame = IRFFCVYUVVideoFrame(pixelBuffer: try makePixelBuffer(format: kCVPixelFormatType_32BGRA))

        try withOffscreenEncoder(renderer: renderer) {
            encoder,
            resources in
            XCTAssertTrue(pixelRenderer.renderFish2Pano(renderer: renderer,
                                                        frame: nv12Frame,
                                                        encoder: encoder,
                                                        params: makeFish2PanoParams(),
                                                        texUVTextures: [lookupTexture],
                                                        resources: resources))
            XCTAssertTrue(pixelRenderer.renderFish2Pano(renderer: renderer,
                                                        frame: bgraFrame,
                                                        encoder: encoder,
                                                        params: makeFish2PanoParams(),
                                                        texUVTextures: [lookupTexture],
                                                        resources: resources))
        }
    }

    func testRGBPixelRendererRenders2DAndRejectsMesh() throws {
        let renderer = try makeRenderer()
        let pixelRenderer = IRMetalPixelRendererRGB()
        let frame = makeRGBFrame()

        try withOffscreenEncoder(renderer: renderer) {
            encoder,
            resources in
            XCTAssertTrue(pixelRenderer.render2D(renderer: renderer,
                                                 frame: frame,
                                                 encoder: encoder,
                                                 resources: resources))
            XCTAssertFalse(pixelRenderer.renderMesh(renderer: renderer,
                                                    frame: frame,
                                                    encoder: encoder,
                                                    indexCount: 0,
                                                    indexBuffer: renderer.vertexBuffer,
                                                    resources: resources))
        }
    }

    func testPixelRenderersRejectMismatchedFrameTypes() throws {
        let renderer = try makeRenderer()
        let nv12Renderer = IRMetalPixelRendererNV12()
        let i420Renderer = IRMetalPixelRendererI420()
        let rgbFrame = makeRGBFrame()
        let params = makeFish2PanoParams()
        let lookupTexture = try makeFish2PanoLookupTexture(renderer: renderer)

        try withOffscreenEncoder(renderer: renderer) {
            encoder,
            resources in
            XCTAssertFalse(nv12Renderer.render2D(renderer: renderer,
                                                 frame: rgbFrame,
                                                 encoder: encoder,
                                                 resources: resources))
            XCTAssertFalse(nv12Renderer.renderMesh(renderer: renderer,
                                                   frame: rgbFrame,
                                                   encoder: encoder,
                                                   indexCount: 0,
                                                   indexBuffer: renderer.vertexBuffer,
                                                   resources: resources))
            XCTAssertFalse(nv12Renderer.renderFish2Pano(renderer: renderer,
                                                        frame: rgbFrame,
                                                        encoder: encoder,
                                                        params: params,
                                                        texUVTextures: [lookupTexture],
                                                        resources: resources))

            XCTAssertFalse(i420Renderer.render2D(renderer: renderer,
                                                 frame: rgbFrame,
                                                 encoder: encoder,
                                                 resources: resources))
            XCTAssertFalse(i420Renderer.renderMesh(renderer: renderer,
                                                   frame: rgbFrame,
                                                   encoder: encoder,
                                                   indexCount: 0,
                                                   indexBuffer: renderer.vertexBuffer,
                                                   resources: resources))
            XCTAssertFalse(i420Renderer.renderFish2Pano(renderer: renderer,
                                                        frame: rgbFrame,
                                                        encoder: encoder,
                                                        params: params,
                                                        texUVTextures: [lookupTexture],
                                                        resources: resources))
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
