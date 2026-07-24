//
//  IRMetalRendererDistortionTests.swift
//  IRPlayer-swiftTests
//
//  Created by Codex on 2026/6/2.
//

import CoreVideo
import Metal
import QuartzCore
import XCTest
#if SWIFT_PACKAGE
@testable import IRPlayerSwift
#else
@testable import IRPlayer_swift
#endif

final class IRMetalRendererDistortionTests: XCTestCase {

    private func makeMetalDevice() throws -> MTLDevice {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("Metal device unavailable")
        }
        return device
    }

    private func makeRenderer() throws -> IRMetalRenderer {
        guard let renderer = IRMetalRenderer(device: try makeMetalDevice()) else {
            throw XCTSkip("Metal renderer unavailable")
        }
        return renderer
    }

    private func makeOffscreenDrawable(renderer: IRMetalRenderer,
                                       width: Int = 4,
                                       height: Int = 4) throws -> IRDistortionTestMetalDrawable {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm,
                                                                  width: width,
                                                                  height: height,
                                                                  mipmapped: false)
        descriptor.usage = [.renderTarget, .shaderRead]
        guard let texture = renderer.device.makeTexture(descriptor: descriptor) else {
            throw XCTSkip("Offscreen Metal drawable texture unavailable")
        }
        return IRDistortionTestMetalDrawable(texture: texture)
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

    private func makePixelBuffer(
        format: OSType
    ) throws -> CVPixelBuffer {
        var pixelBuffer: CVPixelBuffer?
        let attributes: [String: Any] = [
            kCVPixelBufferMetalCompatibilityKey as String:
                true,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:]
        ]
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            2,
            2,
            format,
            attributes as CFDictionary,
            &pixelBuffer
        )
        guard status == kCVReturnSuccess,
              let pixelBuffer else {
            throw XCTSkip("CVPixelBuffer unavailable")
        }
        return pixelBuffer
    }

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

    func testRenderDistortionDrawsValidRGBFrame() throws {
        let renderer = try makeRenderer()
        let drawable = try makeOffscreenDrawable(renderer: renderer)
        let leftMesh = try XCTUnwrap(IRMetalDistortionMesh(device: renderer.device, modelType: .left))
        let rightMesh = try XCTUnwrap(IRMetalDistortionMesh(device: renderer.device, modelType: .right))

        XCTAssertTrue(renderer.renderDistortion(frame: makeRGBFrame(),
                                                leftMesh: leftMesh,
                                                rightMesh: rightMesh,
                                                to: drawable,
                                                drawableSize: CGSize(width: 4, height: 4),
                                                contentMode: .scaleAspectFit))
        XCTAssertEqual(renderer.distortionTargetSnapshot?.width, 4)
        XCTAssertEqual(renderer.distortionTargetSnapshot?.height, 4)
        XCTAssertEqual(
            renderer.distortionTargetDiagnostics.creationCount,
            1
        )
    }

    func testRenderDistortionDrawsCoreVideoFrames() throws {
        let renderer = try makeRenderer()
        let drawable = try makeOffscreenDrawable(
            renderer: renderer
        )
        let leftMesh = try XCTUnwrap(
            IRMetalDistortionMesh(
                device: renderer.device,
                modelType: .left
            )
        )
        let rightMesh = try XCTUnwrap(
            IRMetalDistortionMesh(
                device: renderer.device,
                modelType: .right
            )
        )
        let formats: [OSType] = [
            kCVPixelFormatType_420YpCbCr8BiPlanarFullRange,
            kCVPixelFormatType_32BGRA
        ]

        for format in formats {
            let frame = IRFFCVYUVVideoFrame(
                pixelBuffer: try makePixelBuffer(
                    format: format
                )
            )
            XCTAssertTrue(
                renderer.renderDistortion(
                    frame: frame,
                    leftMesh: leftMesh,
                    rightMesh: rightMesh,
                    to: drawable,
                    drawableSize: CGSize(width: 4, height: 4),
                    contentMode: .scaleAspectFit
                )
            )
        }
    }

    func testRenderDistortionRejectsUnsupportedFrameAfterOffscreenPass() throws {
        let renderer = try makeRenderer()
        let drawable = try makeOffscreenDrawable(renderer: renderer)
        let leftMesh = try XCTUnwrap(IRMetalDistortionMesh(device: renderer.device, modelType: .left))
        let rightMesh = try XCTUnwrap(IRMetalDistortionMesh(device: renderer.device, modelType: .right))

        XCTAssertFalse(renderer.renderDistortion(frame: IRFFVideoFrame(),
                                                 leftMesh: leftMesh,
                                                 rightMesh: rightMesh,
                                                 to: drawable,
                                                 drawableSize: CGSize(width: 4, height: 4),
                                                 contentMode: .scaleAspectFit))
        XCTAssertEqual(renderer.distortionTargetSnapshot?.width, 4)
        XCTAssertEqual(renderer.distortionTargetSnapshot?.height, 4)
    }

    func testRenderDistortionReusesOffscreenTextureForSameDrawableSize() throws {
        let renderer = try makeRenderer()
        let drawable = try makeOffscreenDrawable(renderer: renderer)
        let leftMesh = try XCTUnwrap(IRMetalDistortionMesh(device: renderer.device, modelType: .left))
        let rightMesh = try XCTUnwrap(IRMetalDistortionMesh(device: renderer.device, modelType: .right))
        let frame = makeRGBFrame()

        XCTAssertTrue(renderer.renderDistortion(frame: frame,
                                                leftMesh: leftMesh,
                                                rightMesh: rightMesh,
                                                to: drawable,
                                                drawableSize: CGSize(width: 4, height: 4),
                                                contentMode: .scaleAspectFit))
        let firstTexture = try XCTUnwrap(
            renderer.distortionTargetSnapshot
        )

        XCTAssertTrue(renderer.renderDistortion(frame: frame,
                                                leftMesh: leftMesh,
                                                rightMesh: rightMesh,
                                                to: drawable,
                                                drawableSize: CGSize(width: 4, height: 4),
                                                contentMode: .scaleAspectFit))
        let secondTexture = try XCTUnwrap(
            renderer.distortionTargetSnapshot
        )

        XCTAssertTrue(firstTexture === secondTexture)
        XCTAssertEqual(
            renderer.distortionTargetDiagnostics.reuseCount,
            1
        )
    }
}

private final class IRDistortionTestMetalDrawable: NSObject, CAMetalDrawable {
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
