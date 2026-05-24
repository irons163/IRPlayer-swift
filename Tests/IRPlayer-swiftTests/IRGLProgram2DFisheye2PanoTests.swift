import XCTest
@testable import IRPlayer_swift

final class IRGLProgram2DFisheye2PanoTests: XCTestCase {

    func testTextureSizeRejectsMissingParamsAndReturnsExistingDimensions() {
        XCTAssertNil(IRGLProgram2DFisheye2Pano.textureSize(from: nil))

        let params = IRGLFish2PanoShaderParams()
        params.textureWidth = 1920
        params.textureHeight = 960

        let size = IRGLProgram2DFisheye2Pano.textureSize(from: params)
        XCTAssertEqual(size?.width, 1920)
        XCTAssertEqual(size?.height, 960)
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
}
