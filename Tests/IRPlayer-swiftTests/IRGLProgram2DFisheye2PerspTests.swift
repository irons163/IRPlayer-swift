import XCTest
@testable import IRPlayer_swift

final class IRGLProgram2DFisheye2PerspTests: XCTestCase {

    func testPerspShaderParamsPolicyMatchesAppliedOutputConfiguration() {
        let params = IRGLFish2PerspShaderParams()

        params.updateOutputWH()
        let configuration = IRGLFish2PerspShaderParamsPolicy.outputConfiguration()

        XCTAssertEqual(params.outputWidth, configuration.outputWidth)
        XCTAssertEqual(params.outputHeight, configuration.outputHeight)
        XCTAssertEqual(params.fishcenterx, configuration.fishCenterX)
        XCTAssertEqual(params.fishcentery, configuration.fishCenterY)
        XCTAssertEqual(params.fishradiush, configuration.fishRadiusH)
        XCTAssertEqual(params.enableTransformX, configuration.enableTransformX)
        XCTAssertEqual(params.enableTransformY, configuration.enableTransformY)
        XCTAssertEqual(params.enableTransformZ, configuration.enableTransformZ)
        XCTAssertEqual(params.fishfov, configuration.fishFov, accuracy: 0.0001)
        XCTAssertEqual(params.perspfov, configuration.perspFov, accuracy: 0.0001)
    }

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

    func testPerspShaderParamsHugeTextureUpdateDoesNotBuildOutput() {
        let params = IRGLFish2PerspShaderParams()
        let delegate = ShaderParamsDelegateSpy()
        params.delegate = delegate

        params.updateTextureWidth(Int.max, height: 960)

        XCTAssertEqual(params.textureWidth, -1)
        XCTAssertEqual(params.textureHeight, -1)
        XCTAssertEqual(params.outputWidth, 1024)
        XCTAssertEqual(params.outputHeight, -1)
        XCTAssertTrue(delegate.outputSizes.isEmpty)
    }

    func testSetRenderFrameUpdatesPerspShaderTextureSize() {
        let program = IRGLProgram2DFisheye2Persp()
        guard let params = program.metalFish2PerspParams else {
            return XCTFail("Expected fisheye-to-perspective params")
        }
        let frame = IRFFVideoFrame()
        frame.width = 1920
        frame.height = 960

        program.setRenderFrame(frame)

        XCTAssertEqual(params.textureWidth, 1920)
        XCTAssertEqual(params.textureHeight, 960)
        XCTAssertEqual(params.outputWidth, 1280)
        XCTAssertEqual(params.outputHeight, 720)

        params.outputWidth = 777
        program.setRenderFrame(frame)

        XCTAssertEqual(params.outputWidth, 777)
    }

    func testVerticalBoundsScrollIgnoresInvalidFishRadius() {
        let program = IRGLProgram2DFisheye2Persp()
        guard let params = program.metalFish2PerspParams else {
            return XCTFail("Expected fisheye-to-perspective params")
        }
        params.transformX = 10

        program.willScroll(dx: 0, dy: 20, transformController: IRGLTransformController())
        let shouldContinue = program.doScrollVertical(status: [.toMaxY], transformController: IRGLTransformController())

        XCTAssertFalse(shouldContinue)
        XCTAssertEqual(params.transformX, 10, accuracy: 0.0001)
    }

    func testHorizontalBoundsScrollIgnoresInvalidOutputWidth() {
        let program = IRGLProgram2DFisheye2Persp()
        guard let params = program.metalFish2PerspParams else {
            return XCTFail("Expected fisheye-to-perspective params")
        }
        params.outputWidth = -1
        params.transformY = -90

        program.willScroll(dx: 20, dy: 0, transformController: IRGLTransformController())
        let shouldContinue = program.doScrollHorizontal(status: [.toMaxX], transformController: IRGLTransformController())

        XCTAssertFalse(shouldContinue)
        XCTAssertEqual(params.transformY, -90, accuracy: 0.0001)
    }

    func testHorizontalBoundsScrollUpdatesTransformY() {
        let program = IRGLProgram2DFisheye2Persp()
        guard let params = program.metalFish2PerspParams else {
            return XCTFail("Expected fisheye-to-perspective params")
        }
        params.outputWidth = 360
        params.transformY = -90

        program.willScroll(dx: 18, dy: 0, transformController: IRGLTransformController())
        let shouldContinue = program.doScrollHorizontal(status: [.toMinX], transformController: IRGLTransformController())

        XCTAssertFalse(shouldContinue)
        XCTAssertEqual(params.transformY, -81, accuracy: 0.0001)
    }

    func testVerticalBoundsScrollUpdatesAndClampsTransformX() {
        let program = IRGLProgram2DFisheye2Persp()
        guard let params = program.metalFish2PerspParams else {
            return XCTFail("Expected fisheye-to-perspective params")
        }
        params.fishradiush = 90
        params.transformX = 10

        program.willScroll(dx: 0, dy: -100, transformController: IRGLTransformController())
        let shouldContinueAtMax = program.doScrollVertical(status: [.toMaxY], transformController: IRGLTransformController())

        XCTAssertFalse(shouldContinueAtMax)
        XCTAssertEqual(params.transformX, 55, accuracy: 0.0001)

        program.willScroll(dx: 0, dy: 100, transformController: IRGLTransformController())
        let shouldContinueAtMin = program.doScrollVertical(status: [.toMinY], transformController: IRGLTransformController())

        XCTAssertFalse(shouldContinueAtMin)
        XCTAssertEqual(params.transformX, 0, accuracy: 0.0001)
    }

    func testScrollAwayFromBoundsContinuesControllerHandling() {
        let program = IRGLProgram2DFisheye2Persp()
        guard let params = program.metalFish2PerspParams else {
            return XCTFail("Expected fisheye-to-perspective params")
        }
        params.outputWidth = 360
        params.fishradiush = 90
        params.transformX = 10
        params.transformY = -90

        program.willScroll(dx: 18, dy: -18, transformController: IRGLTransformController())

        XCTAssertTrue(program.doScrollHorizontal(status: [], transformController: IRGLTransformController()))
        XCTAssertTrue(program.doScrollVertical(status: [], transformController: IRGLTransformController()))
        XCTAssertEqual(params.transformX, 10, accuracy: 0.0001)
        XCTAssertEqual(params.transformY, -90, accuracy: 0.0001)
    }
}
