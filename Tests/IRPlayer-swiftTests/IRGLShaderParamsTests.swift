import XCTest
@testable import IRPlayer_swift

final class IRGLShaderParamsTests: XCTestCase {

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

final class IRMetalRendererPixelFormatTests: XCTestCase {

    func testRGBTextureLayoutRejectsInvalidOrOverflowingInputs() {
        XCTAssertNil(IRMetalRenderer.rgbTextureLayout(width: 0, height: 1, linesize: 4, byteCount: 4))
        XCTAssertNil(IRMetalRenderer.rgbTextureLayout(width: 1, height: 0, linesize: 4, byteCount: 4))
        XCTAssertNil(IRMetalRenderer.rgbTextureLayout(width: Int.max, height: 2, linesize: Int.max, byteCount: Int.max))
    }

    func testRGBTextureLayoutRequiresExpectedBGRABytesPerRowAndBufferSize() {
        XCTAssertNil(IRMetalRenderer.rgbTextureLayout(width: 2, height: 2, linesize: 7, byteCount: 16))
        XCTAssertNil(IRMetalRenderer.rgbTextureLayout(width: 2, height: 2, linesize: 8, byteCount: 15))
        XCTAssertEqual(
            IRMetalRenderer.rgbTextureLayout(width: 2, height: 2, linesize: 8, byteCount: 16)?.bytesPerRow,
            8
        )
    }
}

final class IRMetalFisheyeMeshTests: XCTestCase {

    func testBufferByteLengthRejectsInvalidOrOverflowingInputs() {
        XCTAssertNil(IRMetalFisheyeMesh.bufferByteLength(elementCount: 0, stride: MemoryLayout<UInt16>.stride))
        XCTAssertNil(IRMetalFisheyeMesh.bufferByteLength(elementCount: 1, stride: 0))
        XCTAssertNil(IRMetalFisheyeMesh.bufferByteLength(elementCount: Int.max, stride: 2))
    }

    func testBufferByteLengthCalculatesStrideStorage() {
        XCTAssertEqual(
            IRMetalFisheyeMesh.bufferByteLength(elementCount: 4, stride: MemoryLayout<UInt16>.stride),
            8
        )
    }
}

final class IRMetalDistortionMeshTests: XCTestCase {

    func testBufferByteLengthRejectsInvalidOrOverflowingInputs() {
        XCTAssertNil(IRMetalDistortionMesh.bufferByteLength(elementCount: 0, stride: MemoryLayout<UInt16>.stride))
        XCTAssertNil(IRMetalDistortionMesh.bufferByteLength(elementCount: 1, stride: 0))
        XCTAssertNil(IRMetalDistortionMesh.bufferByteLength(elementCount: Int.max, stride: 2))
    }

    func testBufferByteLengthCalculatesStrideStorage() {
        XCTAssertEqual(
            IRMetalDistortionMesh.bufferByteLength(elementCount: 4, stride: MemoryLayout<UInt16>.stride),
            8
        )
    }
}
