import XCTest
@testable import IRPlayer_swift

final class IRGLRenderAdapterTests: XCTestCase {

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
}
