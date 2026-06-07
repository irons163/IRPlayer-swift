import simd
import XCTest
@testable import IRPlayer_swift

final class IRGLTransformController2DTests: XCTestCase {

    func testSetupDefaultTransformExpandsScaleRangeWhenNeeded() {
        let controller = IRGLTransformController2D(viewportWidth: 100, viewportHeight: 80)

        controller.setupDefaultTransform(scaleX: 5, scaleY: 4.5)

        XCTAssertEqual(controller.getDefaultTransformScale().x, 5, accuracy: 0.0001)
        XCTAssertEqual(controller.getDefaultTransformScale().y, 4.5, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(controller.scaleRange).maxScaleX, 5, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(controller.scaleRange).maxScaleY, 4.5, accuracy: 0.0001)
    }

    func testScrollClampsToBoundsAndReportsStatus() {
        let controller = IRGLTransformController2D(viewportWidth: 100, viewportHeight: 100)
        let delegate = TransformDelegateSpy()
        controller.delegate = delegate
        controller.update(fx: 50, fy: 50, sx: 2, sy: 2)

        controller.scroll(dx: 1_000, dy: -1_000)

        XCTAssertEqual(controller.getScope().offsetX, 50, accuracy: 0.0001)
        XCTAssertEqual(controller.getScope().offsetY, 0, accuracy: 0.0001)
        XCTAssertTrue(delegate.didScrollStatuses.last?.contains(.toMaxX) == true)
        XCTAssertTrue(delegate.didScrollStatuses.last?.contains(.toMinY) == true)
    }

    func testScrollRespectsDelegateAxisDecisions() {
        let controller = IRGLTransformController2D(viewportWidth: 100, viewportHeight: 100)
        let delegate = TransformDelegateSpy()
        delegate.allowHorizontal = false
        controller.delegate = delegate
        controller.update(fx: 50, fy: 50, sx: 2, sy: 2)
        let initialOffsetX = controller.getScope().offsetX
        let initialOffsetY = controller.getScope().offsetY

        controller.scroll(dx: 20, dy: 40)

        XCTAssertEqual(controller.getScope().offsetX, initialOffsetX, accuracy: 0.0001)
        XCTAssertEqual(controller.getScope().offsetY, initialOffsetY + 20, accuracy: 0.0001)
        XCTAssertEqual(delegate.horizontalStatuses.count, 1)
        XCTAssertEqual(delegate.verticalStatuses.count, 1)
        XCTAssertEqual(delegate.didScrollStatuses.count, 1)
    }

    func testDegreeScrollUsesFullScopeRangeWidth() {
        let controller = IRGLTransformController2D(viewportWidth: 100, viewportHeight: 100)
        let delegate = TransformDelegateSpy()
        controller.delegate = delegate
        controller.update(fx: 50, fy: 50, sx: 2, sy: 2)
        controller.scopeRange = IRGLScopeRange(minLat: -50,
                                               maxLat: 50,
                                               minLng: -100,
                                               maxLng: 100,
                                               defaultLat: 0,
                                               defaultLng: 0)

        controller.scroll(degreeX: 20, degreeY: 10)

        XCTAssertEqual(controller.getScope().offsetX, 35, accuracy: 0.0001)
        XCTAssertEqual(controller.getScope().offsetY, 35, accuracy: 0.0001)
    }

    func testResetViewportToZeroSizeKeepsMatrixFinite() {
        let controller = IRGLTransformController2D(viewportWidth: 100, viewportHeight: 100)
        controller.update(fx: 50, fy: 50, sx: 2, sy: 2)

        controller.resetViewport(width: 0, height: 0, resetTransform: false)

        assertFinite(controller.getModelViewProjectionMatrix())
    }

    func testUpdateWithZeroViewportKeepsMatrixFinite() {
        let controller = IRGLTransformController2D()

        controller.update(fx: 0, fy: 0, sx: 2, sy: 2)

        assertFinite(controller.getModelViewProjectionMatrix())
        XCTAssertEqual(controller.getScope().scaleX, 1, accuracy: 0.0001)
        XCTAssertEqual(controller.getScope().scaleY, 1, accuracy: 0.0001)
    }

    func testUpdateIgnoresInvalidScaleValues() {
        let controller = IRGLTransformController2D(viewportWidth: 100, viewportHeight: 100)

        controller.update(fx: 50, fy: 50, sx: 0, sy: .nan)

        assertFinite(controller.getModelViewProjectionMatrix())
        XCTAssertEqual(controller.getScope().scaleX, 1, accuracy: 0.0001)
        XCTAssertEqual(controller.getScope().scaleY, 1, accuracy: 0.0001)
    }

    func testUpdateIgnoresInvalidFocalPoints() {
        let controller = IRGLTransformController2D(viewportWidth: 100, viewportHeight: 100)

        controller.update(fx: .nan, fy: .infinity, sx: 2, sy: 2)

        assertFinite(controller.getModelViewProjectionMatrix())
        XCTAssertEqual(controller.getScope().offsetX, 0, accuracy: 0.0001)
        XCTAssertEqual(controller.getScope().offsetY, 0, accuracy: 0.0001)
        XCTAssertEqual(controller.getScope().scaleX, 1, accuracy: 0.0001)
        XCTAssertEqual(controller.getScope().scaleY, 1, accuracy: 0.0001)
    }

    func testUpdateDoesNotWriteDebugOutput() {
        let controller = IRGLTransformController2D(viewportWidth: 100, viewportHeight: 100)

        let output = captureStandardOutput {
            controller.update(fx: 50, fy: 50, sx: 2, sy: 2)
        }

        XCTAssertEqual(output, "")
    }

    func testBaseControllerInitializesRangesAndDefaultScale() throws {
        let scopeRange = IRGLScopeRange(minLat: -10,
                                        maxLat: 20,
                                        minLng: -30,
                                        maxLng: 40,
                                        defaultLat: 5,
                                        defaultLng: 6)
        let scaleRange = IRGLScaleRange(minScaleX: 0.5,
                                        minScaleY: 0.75,
                                        maxScaleX: 3,
                                        maxScaleY: 4,
                                        defaultScaleX: 1.5,
                                        defaultScaleY: 2)

        let controller = IRGLTransformController(scopeRange: scopeRange, scaleRange: scaleRange)

        XCTAssertTrue(controller.scopeRange === scopeRange)
        XCTAssertTrue(controller.scaleRange === scaleRange)
        XCTAssertEqual(controller.getDefaultTransformScale().x, 1.5, accuracy: 0.0001)
        XCTAssertEqual(controller.getDefaultTransformScale().y, 2, accuracy: 0.0001)
        XCTAssertEqual(scopeRange.wideDegreeX, 70, accuracy: 0.0001)
        XCTAssertEqual(scopeRange.wideDegreeY, 30, accuracy: 0.0001)
    }

    func testBaseControllerReturnsDefaultScopeAndIdentityMatrix() {
        let controller = IRGLTransformController()

        let scope = controller.getScope()
        XCTAssertEqual(scope.w, 0)
        XCTAssertEqual(scope.h, 0)
        XCTAssertEqual(scope.scaleX, 1, accuracy: 0.0001)
        XCTAssertEqual(scope.scaleY, 1, accuracy: 0.0001)
        assertIdentity(controller.getModelViewProjectionMatrix())
    }

    func testBaseControllerNoOpMethodsRemainCallable() {
        let controller = IRGLTransformController()

        controller.setupDefaultTransform(scaleX: 2, scaleY: 3)
        controller.updateToDefault()
        controller.scroll(degreeX: 10, degreeY: 20)
        controller.update(fx: 1, fy: 2, sx: 3, sy: 4)
        controller.scroll(dx: 5, dy: 6)
        controller.rotate(degree: 45)
        controller.updateVertices()
        controller.resetViewport(width: 320, height: 180, resetTransform: true)
        controller.reset()

        XCTAssertEqual(controller.getDefaultTransformScale().x, 2, accuracy: 0.0001)
        XCTAssertEqual(controller.getDefaultTransformScale().y, 3, accuracy: 0.0001)
        assertIdentity(controller.getModelViewProjectionMatrix())
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

    private func assertIdentity(
        _ matrix: simd_float4x4,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(matrix.columns.0.x, 1, accuracy: 0.0001, file: file, line: line)
        XCTAssertEqual(matrix.columns.1.y, 1, accuracy: 0.0001, file: file, line: line)
        XCTAssertEqual(matrix.columns.2.z, 1, accuracy: 0.0001, file: file, line: line)
        XCTAssertEqual(matrix.columns.3.w, 1, accuracy: 0.0001, file: file, line: line)
        XCTAssertEqual(matrix.columns.0.y, 0, accuracy: 0.0001, file: file, line: line)
        XCTAssertEqual(matrix.columns.1.x, 0, accuracy: 0.0001, file: file, line: line)
        XCTAssertEqual(matrix.columns.2.x, 0, accuracy: 0.0001, file: file, line: line)
        XCTAssertEqual(matrix.columns.3.x, 0, accuracy: 0.0001, file: file, line: line)
    }

}

private final class TransformDelegateSpy: IRGLTransformControllerDelegate {
    var allowHorizontal = true
    var allowVertical = true
    private(set) var horizontalStatuses: [IRGLTransformController.ScrollStatus] = []
    private(set) var verticalStatuses: [IRGLTransformController.ScrollStatus] = []
    private(set) var didScrollStatuses: [IRGLTransformController.ScrollStatus] = []

    func willScroll(dx: Float, dy: Float, transformController: IRGLTransformController) {}

    func doScrollHorizontal(status: IRGLTransformController.ScrollStatus, transformController: IRGLTransformController) -> Bool {
        horizontalStatuses.append(status)
        return allowHorizontal
    }

    func doScrollVertical(status: IRGLTransformController.ScrollStatus, transformController: IRGLTransformController) -> Bool {
        verticalStatuses.append(status)
        return allowVertical
    }

    func didScroll(status: IRGLTransformController.ScrollStatus, transformController: IRGLTransformController) {
        didScrollStatuses.append(status)
    }
}
