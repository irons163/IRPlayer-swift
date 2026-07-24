//
//  IRGLRenderStrategyFactoryTests.swift
//  IRPlayer-swiftTests
//
//  Created by Codex on 2026/5/24.
//

import Metal
import QuartzCore
import simd
import XCTest
@testable import IRPlayer_swift

final class IRGLRenderStrategyFactoryTests: XCTestCase {

    private func makeRendererAndDrawable() throws -> (renderer: IRMetalRenderer, drawable: IRStrategyTestMetalDrawable) {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("Metal device unavailable")
        }
        guard let renderer = IRMetalRenderer(device: device) else {
            throw XCTSkip("Metal renderer unavailable")
        }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm,
                                                                  width: 2,
                                                                  height: 2,
                                                                  mipmapped: false)
        descriptor.usage = [.renderTarget, .shaderRead]
        guard let texture = device.makeTexture(descriptor: descriptor) else {
            throw XCTSkip("Offscreen Metal texture unavailable")
        }
        return (renderer, IRStrategyTestMetalDrawable(texture: texture))
    }

    func testStrategyKindMatchesRenderModeTypePrecedence() {
        XCTAssertEqual(IRGLRenderStrategyFactory.strategyKind(for: IRGLRenderModeDistortion()), .distortion)
        XCTAssertEqual(IRGLRenderStrategyFactory.strategyKind(for: IRGLRenderMode2DFisheye2Pano()), .fish2Pano)
        XCTAssertEqual(IRGLRenderStrategyFactory.strategyKind(for: IRGLRenderModeVR()), .vr)
        XCTAssertEqual(IRGLRenderStrategyFactory.strategyKind(for: IRGLRenderModeMulti4P()), .multi4P)
        XCTAssertEqual(IRGLRenderStrategyFactory.strategyKind(for: IRGLRenderMode3DFisheye()), .fisheye)
        XCTAssertEqual(IRGLRenderStrategyFactory.strategyKind(for: IRGLRenderMode2D()), .twoD)
        XCTAssertEqual(IRGLRenderStrategyFactory.strategyKind(for: IRGLRenderMode()), .twoD)
    }

    func testMakeCreatesIndependentStrategiesForEveryRenderModeKind() throws {
        let renderer = try makeRendererAndDrawable().renderer
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
            let first = IRGLRenderStrategyFactory.make(for: renderMode, renderer: renderer)
            let second = IRGLRenderStrategyFactory.make(for: renderMode, renderer: renderer)

            XCTAssertFalse(first === second)
        }
    }

    func testFactoryStrategiesForwardUnsupportedFramesThroughRenderer() throws {
        let (renderer, drawable) = try makeRendererAndDrawable()
        let strategy = IRGLRenderStrategyFactory.make(for: IRGLRenderMode2D(), renderer: renderer)
        let frame = IRFFVideoFrame()
        XCTAssertTrue(frame.setDimensions(width: 2, height: 2))
        let drawableSize = CGSize(width: 2, height: 2)
        let viewport = CGRect(origin: .zero, size: drawableSize)
        let params = IRMetalRenderer.Fish2PanoParams(fishwidth: 2,
                                                     fishheight: 2,
                                                     panowidth: 2,
                                                     panoheight: 2,
                                                     antialias: 0,
                                                     offsetX: 0)
        let leftMesh = try XCTUnwrap(IRMetalDistortionMesh(device: drawable.texture.device, modelType: .left))
        let rightMesh = try XCTUnwrap(IRMetalDistortionMesh(device: drawable.texture.device, modelType: .right))
        let fisheyeMesh = try makeTriangleFisheyeMesh(device: drawable.texture.device)

        XCTAssertFalse(strategy.render(frame: frame,
                                       to: drawable,
                                       contentMode: .scaleAspectFit,
                                       drawableSize: drawableSize,
                                       zoomScale: 1,
                                       translation: SIMD2<Float>(repeating: 0)))
        XCTAssertFalse(strategy.renderMulti(frame: frame,
                                            to: drawable,
                                            drawableSize: drawableSize,
                                            viewports: [viewport],
                                            contentModes: [.scaleAspectFit],
                                            zoomScales: [],
                                            translations: []))
        strategy.renderClear(to: drawable)
        XCTAssertFalse(strategy.renderFish2Pano(frame: frame,
                                                params: params,
                                                texUVTextures: [],
                                                to: drawable,
                                                drawableSize: drawableSize,
                                                viewport: viewport,
                                                contentMode: .scaleAspectFit,
                                                outputSize: drawableSize,
                                                zoomScale: 1,
                                                translation: SIMD2<Float>(repeating: 0)))
        XCTAssertFalse(strategy.renderDistortion(frame: frame,
                                                 leftMesh: leftMesh,
                                                 rightMesh: rightMesh,
                                                 to: drawable,
                                                 drawableSize: drawableSize,
                                                 contentMode: .scaleAspectFit))
        XCTAssertFalse(strategy.renderFisheye(frame: frame,
                                              mesh: fisheyeMesh,
                                              mvp: matrix_identity_float4x4,
                                              textureMatrix: matrix_identity_float4x4,
                                              to: drawable,
                                              drawableSize: drawableSize,
                                              viewport: viewport))
        XCTAssertFalse(strategy.renderFisheyeMulti(frame: frame,
                                                   mesh: fisheyeMesh,
                                                   mvpList: [matrix_identity_float4x4],
                                                   textureMatrix: matrix_identity_float4x4,
                                                   to: drawable,
                                                   drawableSize: drawableSize,
                                                   viewports: [viewport]))
    }

    private func makeTriangleFisheyeMesh(device: MTLDevice) throws -> IRMetalFisheyeMesh {
        try XCTUnwrap(
            IRMetalFisheyeMesh(device: device,
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
                               indices: [0, 1, 2])
        )
    }
}

private final class IRStrategyTestMetalDrawable: NSObject, CAMetalDrawable {
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
