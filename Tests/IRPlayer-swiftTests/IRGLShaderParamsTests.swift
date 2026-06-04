import XCTest
@testable import IRPlayer_swift

final class IRGLShaderParamsTests: XCTestCase {

    func testStaticPolicyWrappersRemainSourceCompatible() {
        XCTAssertEqual(IRGLShaderParams.boundedGLint(from: 42), IRGLShaderParamsPolicy.boundedGLint(from: 42))
        XCTAssertEqual(IRGLShaderParams.boundedGLint(from: Double(GLint.max)), IRGLShaderParamsPolicy.boundedGLint(from: Double(GLint.max)))
        XCTAssertEqual(IRGLShaderParams.boundedGLint(from: Double(GLint.min)), IRGLShaderParamsPolicy.boundedGLint(from: Double(GLint.min)))
        XCTAssertNil(IRGLShaderParams.boundedGLint(from: .nan))
        XCTAssertNil(IRGLShaderParamsPolicy.boundedGLint(from: .nan))
    }

    func testDefaultDimensionsAreZero() {
        let params = IRGLShaderParams()

        XCTAssertEqual(params.textureWidth, 0)
        XCTAssertEqual(params.textureHeight, 0)
        XCTAssertEqual(params.outputWidth, 0)
        XCTAssertEqual(params.outputHeight, 0)
    }

    func testTextureUpdateStoresOutputDimensionsAndNotifiesOnlyWhenChanged() {
        let params = IRGLShaderParams()
        let delegate = ShaderParamsDelegateSpy()
        params.delegate = delegate

        params.updateTextureWidth(320, height: 180)
        params.updateTextureWidth(320, height: 180)
        params.updateTextureWidth(640, height: 180)

        XCTAssertEqual(params.textureWidth, 640)
        XCTAssertEqual(params.textureHeight, 180)
        XCTAssertEqual(params.outputWidth, 640)
        XCTAssertEqual(params.outputHeight, 180)
        XCTAssertEqual(
            delegate.outputSizes.map { "\($0.width)x\($0.height)" },
            ["320x180", "640x180"]
        )
    }

    func testTextureUpdateIgnoresDimensionsOutsideGLintRange() {
        let params = IRGLShaderParams()
        let delegate = ShaderParamsDelegateSpy()
        params.delegate = delegate

        params.updateTextureWidth(Int.max, height: 180)

        XCTAssertEqual(params.textureWidth, 0)
        XCTAssertEqual(params.textureHeight, 0)
        XCTAssertEqual(params.outputWidth, 0)
        XCTAssertEqual(params.outputHeight, 0)
        XCTAssertTrue(delegate.outputSizes.isEmpty)
    }
}
