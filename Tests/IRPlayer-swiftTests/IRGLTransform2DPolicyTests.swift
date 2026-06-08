import XCTest
@testable import IRPlayer_swift

final class IRGLTransform2DPolicyTests: XCTestCase {

    func testScaleRangeExpansionPreservesExistingValuesAndRaisesMaxima() {
        let range = IRGLScaleRange(minScaleX: 0.5, minScaleY: 0.6, maxScaleX: 2, maxScaleY: 3, defaultScaleX: 1.2, defaultScaleY: 1.3)

        let expanded = IRGLTransform2DPolicy.expandedScaleRange(range, defaultScaleX: 5, defaultScaleY: 4)

        XCTAssertEqual(expanded.minScaleX, 0.5, accuracy: 0.0001)
        XCTAssertEqual(expanded.minScaleY, 0.6, accuracy: 0.0001)
        XCTAssertEqual(expanded.maxScaleX, 5, accuracy: 0.0001)
        XCTAssertEqual(expanded.maxScaleY, 4, accuracy: 0.0001)
        XCTAssertEqual(expanded.defaultScaleX, 1.2, accuracy: 0.0001)
        XCTAssertEqual(expanded.defaultScaleY, 1.3, accuracy: 0.0001)
    }

    func testDegreeScrollUnitsUseContentSizeAndWideDegree() {
        XCTAssertEqual(
            IRGLTransform2DPolicy.degreeScrollUnits(width: 100, height: 80, scaleX: 2, scaleY: 3, range: IRGLScopeRange(minLat: -20, maxLat: 20, minLng: -50, maxLng: 50, defaultLat: 0, defaultLng: 0)),
            IRGLTransform2DPolicy.DegreeScrollUnits(unitX: 2, unitY: 6)
        )
        XCTAssertEqual(
            IRGLTransform2DPolicy.degreeScrollUnits(width: 100, height: 80, scaleX: 2, scaleY: 3, range: nil),
            IRGLTransform2DPolicy.DegreeScrollUnits(unitX: 0, unitY: 0)
        )
    }

    func testUpdateDecisionRejectsInvalidInputs() {
        let scope = IRGLTransform2DPolicy.Scope(width: 0, height: 100, scaleX: 1, scaleY: 1, offsetX: 0, offsetY: 0)

        XCTAssertNil(IRGLTransform2DPolicy.updateDecision(scope: scope, fx: 0, fy: 0, sx: 2, sy: 2, scaleRange: nil))
        XCTAssertNil(IRGLTransform2DPolicy.updateDecision(scope: scope.with(width: 100), fx: .nan, fy: 0, sx: 2, sy: 2, scaleRange: nil))
        XCTAssertNil(IRGLTransform2DPolicy.updateDecision(scope: scope.with(width: 100), fx: 0, fy: 0, sx: 0, sy: 2, scaleRange: nil))
    }

    func testUpdateDecisionClampsScaleAndOffsets() throws {
        let scope = IRGLTransform2DPolicy.Scope(width: 100, height: 100, scaleX: 1, scaleY: 1, offsetX: 0, offsetY: 0)
        let range = IRGLScaleRange(minScaleX: 1, minScaleY: 1, maxScaleX: 4, maxScaleY: 4, defaultScaleX: 1, defaultScaleY: 1)

        let zoomIn = try XCTUnwrap(IRGLTransform2DPolicy.updateDecision(scope: scope, fx: 50, fy: 50, sx: 2, sy: 2, scaleRange: range))
        XCTAssertEqual(zoomIn.scaleX, 2, accuracy: 0.0001)
        XCTAssertEqual(zoomIn.scaleY, 2, accuracy: 0.0001)
        XCTAssertEqual(zoomIn.offsetX, 25, accuracy: 0.0001)
        XCTAssertEqual(zoomIn.offsetY, 25, accuracy: 0.0001)
        XCTAssertEqual(zoomIn.maxX0, 50, accuracy: 0.0001)
        XCTAssertEqual(zoomIn.maxY0, 50, accuracy: 0.0001)

        let clamped = try XCTUnwrap(IRGLTransform2DPolicy.updateDecision(scope: scope, fx: 50, fy: 50, sx: 10, sy: 10, scaleRange: range))
        XCTAssertEqual(clamped.scaleX, 4, accuracy: 0.0001)
        XCTAssertEqual(clamped.scaleY, 4, accuracy: 0.0001)
        XCTAssertEqual(clamped.offsetX, 37.5, accuracy: 0.0001)
        XCTAssertEqual(clamped.offsetY, 37.5, accuracy: 0.0001)
    }

    func testScrollDecisionClampsOffsetsAndReportsStatus() throws {
        let decision = try XCTUnwrap(IRGLTransform2DPolicy.scrollDecision(offsetX: 25, offsetY: 25, scaleX: 2, scaleY: 2, maxX0: 50, maxY0: 50, dx: 1_000, dy: -1_000))

        XCTAssertEqual(decision.offsetX, 50, accuracy: 0.0001)
        XCTAssertEqual(decision.offsetY, 0, accuracy: 0.0001)
        XCTAssertTrue(decision.status.contains(.toMaxX))
        XCTAssertTrue(decision.status.contains(.toMinY))
    }

    func testScrollDecisionRejectsInvalidInputs() {
        XCTAssertNil(IRGLTransform2DPolicy.scrollDecision(offsetX: 0, offsetY: 0, scaleX: 0, scaleY: 1, maxX0: 0, maxY0: 0, dx: 1, dy: 1))
        XCTAssertNil(IRGLTransform2DPolicy.scrollDecision(offsetX: 0, offsetY: 0, scaleX: 1, scaleY: 1, maxX0: 0, maxY0: 0, dx: .nan, dy: 1))
    }

    func testResizeDecisionScalesOffsetsAndRecomputesBounds() throws {
        let decision = try XCTUnwrap(IRGLTransform2DPolicy.resizeDecision(width: 200, height: 100, scaleX: 2, scaleY: 4, offsetX: 25, offsetY: 10, oldRW: 0.02, oldRH: 0.04))

        XCTAssertEqual(decision.rW, 0.01, accuracy: 0.0001)
        XCTAssertEqual(decision.rH, 0.04, accuracy: 0.0001)
        XCTAssertEqual(decision.maxX0, 100, accuracy: 0.0001)
        XCTAssertEqual(decision.maxY0, 75, accuracy: 0.0001)
        XCTAssertEqual(decision.offsetX, 50, accuracy: 0.0001)
        XCTAssertEqual(decision.offsetY, 10, accuracy: 0.0001)
    }
}

private extension IRGLTransform2DPolicy.Scope {
    func with(width: Int) -> IRGLTransform2DPolicy.Scope {
        return IRGLTransform2DPolicy.Scope(width: width, height: height, scaleX: scaleX, scaleY: scaleY, offsetX: offsetX, offsetY: offsetY)
    }
}
