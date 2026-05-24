import simd
import XCTest
@testable import IRPlayer_swift

final class IRGLTransformController3DFisheyeTests: XCTestCase {

    func testScopeRangesMatchTiltDefaults() {
        assertScopeRange(
            IRGLTransformController3DFisheye.getScopeRange(of: .up),
            minLat: -80,
            maxLat: 80,
            minLng: -75,
            maxLng: 75,
            defaultLat: 0,
            defaultLng: 0
        )
        assertScopeRange(
            IRGLTransformController3DFisheye.getScopeRange(of: .toward),
            minLat: 0,
            maxLat: 80,
            minLng: -180,
            maxLng: 180,
            defaultLat: 80,
            defaultLng: -90
        )
        assertScopeRange(
            IRGLTransformController3DFisheye.getScopeRange(of: .backward),
            minLat: -85,
            maxLat: -20,
            minLng: -180,
            maxLng: 180,
            defaultLat: -80,
            defaultLng: 90
        )
    }

    func testScrollClampsToBoundsAndReportsStatus() {
        let controller = IRGLTransformController3DFisheye(viewportWidth: 100, viewportHeight: 100, tileType: .up)
        let delegate = FisheyeTransformDelegateSpy()
        controller.delegate = delegate

        controller.scroll(dx: -1_000, dy: -1_000)

        XCTAssertEqual(controller.getScope().lng, 75, accuracy: 0.0001)
        XCTAssertEqual(controller.getScope().lat, -30, accuracy: 0.0001)
        XCTAssertTrue(delegate.didScrollStatuses.last?.contains(.toMaxX) == true)
        XCTAssertTrue(delegate.didScrollStatuses.last?.contains(.toMaxY) == true)
    }

    func testScrollRespectsDelegateAxisDecisions() {
        let controller = IRGLTransformController3DFisheye(viewportWidth: 100, viewportHeight: 100, tileType: .up)
        let delegate = FisheyeTransformDelegateSpy()
        delegate.allowHorizontal = false
        controller.delegate = delegate
        let scope = controller.getScope()

        controller.scroll(dx: -1_000, dy: -1_000)

        XCTAssertEqual(scope.lng, 0, accuracy: 0.0001)
        XCTAssertEqual(scope.lat, -30, accuracy: 0.0001)
        XCTAssertFalse(delegate.didScrollStatuses.last?.contains(.toMaxX) == true)
        XCTAssertTrue(delegate.didScrollStatuses.last?.contains(.toMaxY) == true)
    }

    func testRotateOnlyUpdatesUpTilt() {
        let upController = IRGLTransformController3DFisheye(viewportWidth: 100, viewportHeight: 100, tileType: .up)
        let towardController = IRGLTransformController3DFisheye(viewportWidth: 100, viewportHeight: 100, tileType: .toward)

        upController.rotate(degree: 30)
        towardController.rotate(degree: 30)

        XCTAssertEqual(upController.getScope().panDegree, 30, accuracy: 0.0001)
        XCTAssertEqual(towardController.getScope().panDegree, 0, accuracy: 0.0001)
    }

    func testResetViewportToZeroSizeKeepsMatrixFinite() {
        let controller = IRGLTransformController3DFisheye(viewportWidth: 100, viewportHeight: 100, tileType: .up)

        controller.resetViewport(width: 0, height: 0, resetTransform: true)

        assertFinite(controller.getModelViewProjectionMatrix())
    }

    private func assertFinite(
        _ matrix: simd_float4x4,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        for column in [matrix.columns.0, matrix.columns.1, matrix.columns.2, matrix.columns.3] {
            XCTAssertTrue(column.x.isFinite, file: file, line: line)
            XCTAssertTrue(column.y.isFinite, file: file, line: line)
            XCTAssertTrue(column.z.isFinite, file: file, line: line)
            XCTAssertTrue(column.w.isFinite, file: file, line: line)
        }
    }
}

private func assertScopeRange(
    _ range: IRGLScopeRange,
    minLat: Float,
    maxLat: Float,
    minLng: Float,
    maxLng: Float,
    defaultLat: Float,
    defaultLng: Float,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    XCTAssertEqual(range.minLat, minLat, accuracy: 0.0001, file: file, line: line)
    XCTAssertEqual(range.maxLat, maxLat, accuracy: 0.0001, file: file, line: line)
    XCTAssertEqual(range.minLng, minLng, accuracy: 0.0001, file: file, line: line)
    XCTAssertEqual(range.maxLng, maxLng, accuracy: 0.0001, file: file, line: line)
    XCTAssertEqual(range.defaultLat, defaultLat, accuracy: 0.0001, file: file, line: line)
    XCTAssertEqual(range.defaultLng, defaultLng, accuracy: 0.0001, file: file, line: line)
}

private final class FisheyeTransformDelegateSpy: IRGLTransformControllerDelegate {
    var allowHorizontal = true
    var allowVertical = true
    private(set) var didScrollStatuses: [IRGLTransformController.ScrollStatus] = []

    func willScroll(dx: Float, dy: Float, transformController: IRGLTransformController) {}

    func doScrollHorizontal(status: IRGLTransformController.ScrollStatus, transformController: IRGLTransformController) -> Bool {
        return allowHorizontal
    }

    func doScrollVertical(status: IRGLTransformController.ScrollStatus, transformController: IRGLTransformController) -> Bool {
        return allowVertical
    }

    func didScroll(status: IRGLTransformController.ScrollStatus, transformController: IRGLTransformController) {
        didScrollStatuses.append(status)
    }
}
