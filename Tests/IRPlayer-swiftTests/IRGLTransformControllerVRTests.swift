import simd
import XCTest
@testable import IRPlayer_swift

final class IRGLTransformControllerVRTests: XCTestCase {

    func testScopeRangesMatchVRDefaults() {
        assertVRScopeRange(
            IRGLTransformControllerVR.getScopeRange(of: .up),
            minLat: -190,
            maxLat: 190,
            minLng: -180,
            maxLng: 180
        )
        assertVRScopeRange(
            IRGLTransformControllerVR.getScopeRange(of: .toward),
            minLat: -90,
            maxLat: 90,
            minLng: -180,
            maxLng: 180
        )
        assertVRScopeRange(
            IRGLTransformControllerVR.getScopeRange(of: .backward),
            minLat: -90,
            maxLat: 90,
            minLng: -180,
            maxLng: 180
        )
    }

    func testDistortionControllerProducesDistinctEyeMatrices() {
        let controller = IRGLTransformControllerDistortion(viewportWidth: 100, viewportHeight: 100, tileType: .up)

        let leftMatrix = controller.getModelViewProjectionMatrix()
        let rightMatrix = controller.getModelViewProjectionMatrix2()

        XCTAssertFalse(matrixAlmostEqual(leftMatrix, rightMatrix))
    }
}

private func assertVRScopeRange(
    _ range: IRGLScopeRange,
    minLat: Float,
    maxLat: Float,
    minLng: Float,
    maxLng: Float,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    XCTAssertEqual(range.minLat, minLat, accuracy: 0.0001, file: file, line: line)
    XCTAssertEqual(range.maxLat, maxLat, accuracy: 0.0001, file: file, line: line)
    XCTAssertEqual(range.minLng, minLng, accuracy: 0.0001, file: file, line: line)
    XCTAssertEqual(range.maxLng, maxLng, accuracy: 0.0001, file: file, line: line)
    XCTAssertEqual(range.defaultLat, 0, accuracy: 0.0001, file: file, line: line)
    XCTAssertEqual(range.defaultLng, 0, accuracy: 0.0001, file: file, line: line)
}

private func matrixAlmostEqual(_ lhs: simd_float4x4, _ rhs: simd_float4x4, accuracy: Float = 0.0001) -> Bool {
    for column in 0..<4 {
        for row in 0..<4 where abs(lhs[column][row] - rhs[column][row]) > accuracy {
            return false
        }
    }
    return true
}
