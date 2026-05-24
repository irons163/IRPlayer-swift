import XCTest
@testable import IRPlayer_swift

final class IRGLProgram2DFisheye2PerspTests: XCTestCase {

    func testPerspShaderParamsDefaultValuesMatchExpectedProjectionInputs() {
        let params = IRGLFish2PerspShaderParams()

        XCTAssertEqual(params.textureWidth, -1)
        XCTAssertEqual(params.textureHeight, -1)
        XCTAssertEqual(params.fishaperture, 180, accuracy: 0.0001)
        XCTAssertEqual(params.fishcenterx, -1)
        XCTAssertEqual(params.fishcentery, -1)
        XCTAssertEqual(params.fishradiush, -1)
        XCTAssertEqual(params.fishradiusv, -1)
        XCTAssertEqual(params.outputWidth, 1024)
        XCTAssertEqual(params.outputHeight, -1)
        XCTAssertEqual(params.antialias, 2)
        XCTAssertEqual(params.enableTransformX, 1)
        XCTAssertEqual(params.enableTransformY, 1)
        XCTAssertEqual(params.enableTransformZ, 1)
        XCTAssertEqual(params.transformX, 0, accuracy: 0.0001)
        XCTAssertEqual(params.transformY, -90, accuracy: 0.0001)
        XCTAssertEqual(params.transformZ, 0, accuracy: 0.0001)
        XCTAssertEqual(params.fishfov, GLfloat.pi, accuracy: 0.0001)
        XCTAssertEqual(params.perspfov, 100 * GLfloat.pi / 180, accuracy: 0.0001)
    }

    func testPerspShaderParamsSettersStoreFieldOfViewValues() {
        let params = IRGLFish2PerspShaderParams()
        let fishFov = 120 * GLfloat.pi / 180
        let perspFov = 90 * GLfloat.pi / 180

        params.setFishfov(fishFov)
        params.setPerspfov(perspFov)

        XCTAssertEqual(params.fishfov, fishFov, accuracy: 0.0001)
        XCTAssertEqual(params.perspfov, perspFov, accuracy: 0.0001)
    }

    func testPerspShaderParamsTextureUpdateBuildsExpectedOutputAndNotifiesDelegate() {
        let params = IRGLFish2PerspShaderParams()
        let delegate = ShaderParamsDelegateSpy()
        params.delegate = delegate

        params.updateTextureWidth(1920, height: 960)

        XCTAssertEqual(params.textureWidth, 1920)
        XCTAssertEqual(params.textureHeight, 960)
        XCTAssertEqual(params.outputWidth, 1280)
        XCTAssertEqual(params.outputHeight, 720)
        XCTAssertEqual(params.fishcenterx, 680)
        XCTAssertEqual(params.fishcentery, 545)
        XCTAssertEqual(params.fishradiush, 515)
        XCTAssertEqual(params.enableTransformX, 1)
        XCTAssertEqual(params.enableTransformY, 1)
        XCTAssertEqual(params.enableTransformZ, 1)
        XCTAssertEqual(params.fishfov, GLfloat.pi, accuracy: 0.0001)
        XCTAssertEqual(params.perspfov, 100 * GLfloat.pi / 180, accuracy: 0.0001)
        XCTAssertEqual(delegate.outputSizes.map { "\($0.width)x\($0.height)" }, ["1280x720"])
    }
}
