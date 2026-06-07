import Metal
import QuartzCore
import simd
import XCTest
@testable import IRPlayer_swift

final class IRGLRenderAdapterTests: XCTestCase {

    private func makeOffscreenDrawable() throws -> IRTestMetalDrawable {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("Metal device unavailable")
        }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm,
                                                                  width: 2,
                                                                  height: 2,
                                                                  mipmapped: false)
        descriptor.usage = [.renderTarget, .shaderRead]
        guard let texture = device.makeTexture(descriptor: descriptor) else {
            throw XCTSkip("Offscreen Metal texture unavailable")
        }
        return IRTestMetalDrawable(texture: texture)
    }

    func testPublicRenderAdaptersAreRenderInternals() {
        let nv12: IRGLRender = IRGLRenderNV12()
        let yuv: IRGLRender = IRGLRenderYUV()

        XCTAssertTrue(nv12 is IRGLRenderNV12)
        XCTAssertTrue(yuv is IRGLRenderYUV)
        XCTAssertNotNil(nv12 as? IRGLRenderInternal)
        XCTAssertNotNil(yuv as? IRGLRenderInternal)
    }

    func testRenderAdaptersCreateIndependentInstances() {
        let first = IRGLRenderNV12()
        let second = IRGLRenderNV12()

        XCTAssertFalse(first === second)
    }

    func testRenderAdaptersRejectUnsupportedFrameTypes() throws {
        let drawable = try makeOffscreenDrawable()
        let frame = IRFFVideoFrame()
        let adapters: [IRGLRenderInternal] = [IRGLRenderNV12(), IRGLRenderYUV()]

        for adapter in adapters {
            XCTAssertFalse(adapter.render(frame: frame,
                                          to: drawable,
                                          contentMode: .scaleAspectFit,
                                          drawableSize: CGSize(width: 2, height: 2),
                                          zoomScale: 1,
                                          translation: SIMD2<Float>(repeating: 0)))
        }
    }

    func testRenderAdaptersRejectMismatchedMultiViewportInputs() throws {
        let drawable = try makeOffscreenDrawable()
        let frame = IRFFVideoFrame()
        let adapters: [IRGLRenderInternal] = [IRGLRenderNV12(), IRGLRenderYUV()]

        for adapter in adapters {
            XCTAssertFalse(adapter.renderMulti(frame: frame,
                                               to: drawable,
                                               drawableSize: CGSize(width: 2, height: 2),
                                               viewports: [],
                                               contentModes: [],
                                               zoomScales: [],
                                               translations: []))
            XCTAssertFalse(adapter.renderMulti(frame: frame,
                                               to: drawable,
                                               drawableSize: CGSize(width: 2, height: 2),
                                               viewports: [CGRect(x: 0, y: 0, width: 2, height: 2)],
                                               contentModes: [],
                                               zoomScales: [],
                                               translations: []))
        }
    }

    func testRenderAdaptersRejectUnsupportedFish2PanoFrames() throws {
        let drawable = try makeOffscreenDrawable()
        let frame = IRFFVideoFrame()
        let params = IRMetalRenderer.Fish2PanoParams(fishwidth: 2,
                                                     fishheight: 2,
                                                     panowidth: 2,
                                                     panoheight: 2,
                                                     antialias: 0,
                                                     offsetX: 0)
        let adapters: [IRGLRenderInternal] = [IRGLRenderNV12(), IRGLRenderYUV()]

        for adapter in adapters {
            XCTAssertFalse(adapter.renderFish2Pano(frame: frame,
                                                   params: params,
                                                   texUVTextures: [],
                                                   to: drawable,
                                                   drawableSize: CGSize(width: 2, height: 2),
                                                   viewport: CGRect(x: 0, y: 0, width: 2, height: 2),
                                                   contentMode: .scaleAspectFit,
                                                   outputSize: CGSize(width: 2, height: 2),
                                                   zoomScale: 1,
                                                   translation: SIMD2<Float>(repeating: 0)))
        }
    }

    func testRenderAdaptersClearOffscreenDrawableWithoutCrashing() throws {
        let drawable = try makeOffscreenDrawable()
        let adapters: [IRGLRenderInternal] = [IRGLRenderNV12(), IRGLRenderYUV()]

        for adapter in adapters {
            adapter.renderClear(to: drawable)
        }
    }
}

private final class IRTestMetalDrawable: NSObject, CAMetalDrawable {
    let texture: MTLTexture
    let layer = CAMetalLayer()
    private(set) var presentCount = 0

    init(texture: MTLTexture) {
        self.texture = texture
        super.init()
    }

    func present() {
        presentCount += 1
    }

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
