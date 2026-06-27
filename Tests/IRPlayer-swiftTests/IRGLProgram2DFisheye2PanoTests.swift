import XCTest
@testable import IRPlayer_swift

final class IRGLProgram2DFisheye2PanoTests: XCTestCase {

    func testPanoShaderParamPolicyWrappersRemainSourceCompatible() {
        XCTAssertEqual(
            IRGLFish2PanoShaderParams.outputSize(forTextureWidth: 640, height: 480)?.width,
            IRGLFish2PanoShaderParamsPolicy.outputSize(forTextureWidth: 640, height: 480)?.width
        )
        XCTAssertEqual(
            IRGLFish2PanoShaderParams.outputSize(forTextureWidth: 640, height: 480)?.height,
            IRGLFish2PanoShaderParamsPolicy.outputSize(forTextureWidth: 640, height: 480)?.height
        )
        XCTAssertEqual(
            IRGLFish2PanoShaderParams.pixelMapTextureCount(antialias: 3),
            IRGLFish2PanoShaderParamsPolicy.pixelMapTextureCount(antialias: 3)
        )
        XCTAssertEqual(
            IRGLFish2PanoShaderParams.pixelMapCapacity(outputWidth: 10, outputHeight: 20),
            IRGLFish2PanoShaderParamsPolicy.pixelMapCapacity(outputWidth: 10, outputHeight: 20)
        )
        XCTAssertEqual(
            IRGLFish2PanoShaderParams.pixelMapUVOffset(outputWidth: 10, outputHeight: 20, x: 3, y: 2),
            IRGLFish2PanoShaderParamsPolicy.pixelMapUVOffset(outputWidth: 10, outputHeight: 20, x: 3, y: 2)
        )
    }

    func testStaticPolicyWrappersRemainSourceCompatible() {
        let params = IRGLFish2PanoShaderParams()
        params.textureWidth = 1920
        params.textureHeight = 960

        XCTAssertEqual(
            IRGLProgram2DFisheye2Pano.textureSize(from: params)?.width,
            IRGLProgram2DFisheye2PanoPolicy.textureSize(from: params)?.width
        )
        XCTAssertEqual(
            IRGLProgram2DFisheye2Pano.textureSize(from: params)?.height,
            IRGLProgram2DFisheye2PanoPolicy.textureSize(from: params)?.height
        )
        XCTAssertEqual(
            IRGLProgram2DFisheye2Pano.normalizedOffsetX(currentOffset: 0, delta: 260, outputWidth: 100),
            IRGLProgram2DFisheye2PanoPolicy.normalizedOffsetX(currentOffset: 0, delta: 260, outputWidth: 100)
        )
    }

    func testTextureSizeRejectsMissingParamsAndReturnsExistingDimensions() {
        XCTAssertNil(IRGLProgram2DFisheye2Pano.textureSize(from: nil))

        let params = IRGLFish2PanoShaderParams()
        params.textureWidth = 1920
        params.textureHeight = 960

        let size = IRGLProgram2DFisheye2Pano.textureSize(from: params)
        XCTAssertEqual(size?.width, 1920)
        XCTAssertEqual(size?.height, 960)
    }

    func testProgramInitializesAndUpdatesFish2PanoShaderParams() throws {
        let program = IRGLProgram2DFisheye2Pano(pixelFormat: .RGB_IRPixelFormat,
                                                viewportRange: .zero,
                                                parameter: nil)
        let params = try XCTUnwrap(program.metalFish2PanoParams)

        program.updateTextureWidth(64, height: 48)

        let outputSize = try XCTUnwrap(IRGLFish2PanoShaderParams.outputSize(forTextureWidth: 64, height: 48))
        XCTAssertEqual(params.textureWidth, 64)
        XCTAssertEqual(params.textureHeight, 48)
        XCTAssertEqual(params.fishcenterx, 32)
        XCTAssertEqual(params.fishcentery, 24)
        XCTAssertEqual(params.fishradiush, 32)
        XCTAssertEqual(params.fishradiusv, 24)
        XCTAssertEqual(params.outputWidth, GLint(outputSize.width))
        XCTAssertEqual(params.outputHeight, GLint(outputSize.height))
        XCTAssertEqual(params.enableTransformX, 1)
        XCTAssertEqual(params.enableTransformZ, 1)
        XCTAssertEqual(params.transformZ, -90, accuracy: 0.0001)
    }

    func testProgramSetRenderFrameUpdatesFish2PanoTextureSize() throws {
        let program = IRGLProgram2DFisheye2Pano(pixelFormat: .RGB_IRPixelFormat,
                                                viewportRange: .zero,
                                                parameter: nil)
        let params = try XCTUnwrap(program.metalFish2PanoParams)
        let frame = IRFFVideoFrame()
        frame.width = 32
        frame.height = 24

        program.setRenderFrame(frame)

        XCTAssertEqual(params.textureWidth, 32)
        XCTAssertEqual(params.textureHeight, 24)
    }

    func testProgramHorizontalBoundsScrollWrapsFish2PanoOffset() throws {
        let program = IRGLProgram2DFisheye2Pano(pixelFormat: .RGB_IRPixelFormat,
                                                viewportRange: .zero,
                                                parameter: nil)
        let params = try XCTUnwrap(program.metalFish2PanoParams)
        params.outputWidth = 100
        params.offsetX = 0
        let controller = Fish2PanoRecordingTransformController(scope: IRGLScope2D(scaleX: 2,
                                                                                  scaleY: 1,
                                                                                  offsetX: 0,
                                                                                  offsetY: 0,
                                                                                  panDegree: 0,
                                                                                  w: 50,
                                                                                  h: 50))
        program.tramsformController = controller

        program.willScroll(dx: 50, dy: 0, transformController: controller)
        let shouldContinue = program.doScrollHorizontal(status: .toMaxX, transformController: controller)

        XCTAssertFalse(shouldContinue)
        XCTAssertEqual(params.offsetX, -50, accuracy: 0.0001)
    }

    func testProgramHorizontalBoundsScrollStopsWhenTransformControllerIsMissing() throws {
        let program = IRGLProgram2DFisheye2Pano(pixelFormat: .RGB_IRPixelFormat,
                                                viewportRange: .zero,
                                                parameter: nil)
        let params = try XCTUnwrap(program.metalFish2PanoParams)
        params.outputWidth = 100
        params.offsetX = 25

        program.willScroll(dx: 50, dy: 0, transformController: Fish2PanoRecordingTransformController(scope: IRGLScope2D()))
        let shouldContinue = program.doScrollHorizontal(status: .toMinX, transformController: IRGLTransformController())

        XCTAssertFalse(shouldContinue)
        XCTAssertEqual(params.offsetX, 25)
    }

    func testProgramDoubleTapRemainsCallableWithoutTransformController() {
        let program = IRGLProgram2DFisheye2Pano(pixelFormat: .RGB_IRPixelFormat,
                                                viewportRange: .zero,
                                                parameter: nil)

        program.didDoubleTap()

        XCTAssertNotNil(program.metalFish2PanoParams)
    }

    func testPanoShaderParamsDefaultValuesMatchExpectedProjectionInputs() {
        let params = IRGLFish2PanoShaderParams()

        XCTAssertEqual(params.textureWidth, 0)
        XCTAssertEqual(params.textureHeight, 0)
        XCTAssertEqual(params.fishaperture, 180, accuracy: 0.0001)
        XCTAssertEqual(params.fishcenterx, -1)
        XCTAssertEqual(params.fishcentery, -1)
        XCTAssertEqual(params.fishradiush, -1)
        XCTAssertEqual(params.fishradiusv, -1)
        XCTAssertEqual(params.outputWidth, 1024)
        XCTAssertEqual(params.outputHeight, 0)
        XCTAssertEqual(params.antialias, 1)
        XCTAssertEqual(params.vaperture, 60, accuracy: 0.0001)
        XCTAssertEqual(params.lat1, -100, accuracy: 0.0001)
        XCTAssertEqual(params.lat2, 100, accuracy: 0.0001)
        XCTAssertEqual(params.long1, 0, accuracy: 0.0001)
        XCTAssertEqual(params.long2, 360, accuracy: 0.0001)
        XCTAssertEqual(params.transformZ, -90, accuracy: 0.0001)
    }

    func testPanoShaderParamsZeroDimensionTextureUpdateDoesNotBuildOutputMap() {
        let params = IRGLFish2PanoShaderParams()
        let delegate = ShaderParamsDelegateSpy()
        params.delegate = delegate

        params.updateTextureWidth(640, height: 0)

        XCTAssertEqual(params.textureWidth, 640)
        XCTAssertEqual(params.textureHeight, 0)
        XCTAssertEqual(params.fishcenterx, 320)
        XCTAssertEqual(params.fishcentery, 0)
        XCTAssertEqual(params.fishradiush, 320)
        XCTAssertEqual(params.fishradiusv, 0)
        XCTAssertEqual(params.outputWidth, 1024)
        XCTAssertEqual(params.outputHeight, 0)
        XCTAssertTrue(delegate.outputSizes.isEmpty)
    }

    func testPanoShaderParamsConsumePixUVWhenMapIsReady() throws {
        let params = IRGLFish2PanoShaderParams()

        XCTAssertNil(params.consumePixUVIfReady())

        params.updateTextureWidth(32, height: 24)
        let pixUV = try waitForPixUV(from: params)

        XCTAssertEqual(pixUV.count, 1)
        params.releaseConsumedPixUV(pixUV)
        XCTAssertNil(params.consumePixUVIfReady())
    }

    func testPanoShaderParamsReleaseConsumedPixUVIsIdempotent() throws {
        let params = IRGLFish2PanoShaderParams()

        params.updateTextureWidth(32, height: 24)
        let pixUV = try waitForPixUV(from: params)

        params.releaseConsumedPixUV(pixUV)
        params.releaseConsumedPixUV(pixUV)

        XCTAssertNil(params.consumePixUVIfReady())
    }

    func testPanoShaderParamsHugeTextureUpdateDoesNotBuildOutputMap() {
        let params = IRGLFish2PanoShaderParams()
        let delegate = ShaderParamsDelegateSpy()
        params.delegate = delegate

        params.updateTextureWidth(Int.max, height: 480)

        XCTAssertEqual(params.textureWidth, 0)
        XCTAssertEqual(params.textureHeight, 0)
        XCTAssertEqual(params.outputWidth, 1024)
        XCTAssertEqual(params.outputHeight, 0)
        XCTAssertTrue(delegate.outputSizes.isEmpty)
    }

    func testPanoOutputSizeRejectsInvalidTextureDimensions() {
        XCTAssertNil(IRGLFish2PanoShaderParams.outputSize(forTextureWidth: 0, height: 480))
        XCTAssertNil(IRGLFish2PanoShaderParams.outputSize(forTextureWidth: 640, height: 0))
        XCTAssertNil(IRGLFish2PanoShaderParams.outputSize(forTextureWidth: -640, height: 480))
        XCTAssertNil(IRGLFish2PanoShaderParams.outputSize(forTextureWidth: 640, height: -480))
        XCTAssertNil(IRGLFish2PanoShaderParams.outputSize(forTextureWidth: Int.max, height: 480))
    }

    func testPanoOutputSizeUsesExpectedAspectForValidTextureDimensions() throws {
        let outputSize = try XCTUnwrap(IRGLFish2PanoShaderParams.outputSize(forTextureWidth: 640, height: 480))

        XCTAssertEqual(outputSize.width, 910)
        XCTAssertEqual(outputSize.height, 167)
    }

    func testPanoPixelMapTextureCountRejectsInvalidOrOverflowingAntialias() {
        XCTAssertNil(IRGLFish2PanoShaderParams.pixelMapTextureCount(antialias: 0))
        XCTAssertNil(IRGLFish2PanoShaderParams.pixelMapTextureCount(antialias: -1))
        XCTAssertNil(IRGLFish2PanoShaderParams.pixelMapTextureCount(antialias: GLint.max))
    }

    func testPanoPixelMapTextureCountSquaresAntialias() {
        XCTAssertEqual(IRGLFish2PanoShaderParams.pixelMapTextureCount(antialias: 1), 1)
        XCTAssertEqual(IRGLFish2PanoShaderParams.pixelMapTextureCount(antialias: 3), 9)
    }

    func testPanoPixelMapCapacityRejectsInvalidOrOverflowingDimensions() {
        XCTAssertNil(IRGLFish2PanoShaderParams.pixelMapCapacity(outputWidth: 0, outputHeight: 10))
        XCTAssertNil(IRGLFish2PanoShaderParams.pixelMapCapacity(outputWidth: 10, outputHeight: 0))
        XCTAssertNil(IRGLFish2PanoShaderParams.pixelMapCapacity(outputWidth: GLint.max, outputHeight: 2))
    }

    func testPanoPixelMapCapacityCountsUVPairs() {
        XCTAssertEqual(IRGLFish2PanoShaderParams.pixelMapCapacity(outputWidth: 10, outputHeight: 20), 400)
    }

    func testPanoPixelMapUVOffsetRejectsOutOfBoundsOrOverflowingCoordinates() {
        XCTAssertNil(IRGLFish2PanoShaderParams.pixelMapUVOffset(outputWidth: 0, outputHeight: 10, x: 0, y: 0))
        XCTAssertNil(IRGLFish2PanoShaderParams.pixelMapUVOffset(outputWidth: 10, outputHeight: 0, x: 0, y: 0))
        XCTAssertNil(IRGLFish2PanoShaderParams.pixelMapUVOffset(outputWidth: 10, outputHeight: 10, x: -1, y: 0))
        XCTAssertNil(IRGLFish2PanoShaderParams.pixelMapUVOffset(outputWidth: 10, outputHeight: 10, x: 10, y: 0))
        XCTAssertNil(IRGLFish2PanoShaderParams.pixelMapUVOffset(outputWidth: 10, outputHeight: 10, x: 0, y: 10))
        XCTAssertNil(IRGLFish2PanoShaderParams.pixelMapUVOffset(outputWidth: GLint.max, outputHeight: 2, x: 0, y: 1))
    }

    func testPanoPixelMapUVOffsetCalculatesInterleavedUVBaseIndex() {
        XCTAssertEqual(IRGLFish2PanoShaderParams.pixelMapUVOffset(outputWidth: 10, outputHeight: 20, x: 3, y: 2), 46)
    }

    func testNormalizedOffsetRejectsInvalidOutputWidth() {
        XCTAssertNil(IRGLProgram2DFisheye2Pano.normalizedOffsetX(currentOffset: 0, delta: 20, outputWidth: 0))
        XCTAssertNil(IRGLProgram2DFisheye2Pano.normalizedOffsetX(currentOffset: 0, delta: 20, outputWidth: -1))
    }

    func testNormalizedOffsetRejectsNonFiniteInputs() {
        XCTAssertNil(IRGLProgram2DFisheye2Pano.normalizedOffsetX(currentOffset: .nan, delta: 20, outputWidth: 100))
        XCTAssertNil(IRGLProgram2DFisheye2Pano.normalizedOffsetX(currentOffset: 0, delta: .infinity, outputWidth: 100))
    }

    func testNormalizedOffsetWrapsWithinOutputWidth() throws {
        let wrappedLeft = try XCTUnwrap(
            IRGLProgram2DFisheye2Pano.normalizedOffsetX(currentOffset: 0, delta: 260, outputWidth: 100)
        )
        let wrappedRight = try XCTUnwrap(
            IRGLProgram2DFisheye2Pano.normalizedOffsetX(currentOffset: 0, delta: -260, outputWidth: 100)
        )

        XCTAssertEqual(wrappedLeft, -60, accuracy: 0.0001)
        XCTAssertEqual(wrappedRight, 60, accuracy: 0.0001)
    }

    func testRotationHelpersRotateAroundExpectedAxes() {
        let point = XYZ(x: 1, y: 2, z: 3)
        let quarterTurn = GLfloat.pi / 2

        assertXYZ(PRotateX(point, quarterTurn), x: 1, y: 3, z: -2)
        assertXYZ(PRotateY(point, quarterTurn), x: -3, y: 2, z: 1)
        assertXYZ(PRotateZ(point, quarterTurn), x: 2, y: -1, z: 3)
    }

    private func assertXYZ(
        _ value: XYZ,
        x: GLfloat,
        y: GLfloat,
        z: GLfloat,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(value.x, x, accuracy: 0.0001, file: file, line: line)
        XCTAssertEqual(value.y, y, accuracy: 0.0001, file: file, line: line)
        XCTAssertEqual(value.z, z, accuracy: 0.0001, file: file, line: line)
    }

    private func waitForPixUV(
        from params: IRGLFish2PanoShaderParams,
        timeout: TimeInterval = 1,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> [UnsafeMutablePointer<GLfloat>] {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let pixUV = params.consumePixUVIfReady() {
                return pixUV
            }
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
        }
        XCTFail("Expected fish2pano pixel map to become ready", file: file, line: line)
        throw XCTSkip("Pixel map did not become ready before timeout")
    }
}

private final class Fish2PanoRecordingTransformController: IRGLTransformController {
    private let scope: IRGLScope2D

    init(scope: IRGLScope2D) {
        self.scope = scope
        super.init()
    }

    override func getScope() -> IRGLScope2D {
        scope
    }
}
