import XCTest
@testable import IRPlayer_swift

final class IRGLTransform2DSemanticsTests: XCTestCase {

    func testScaleRangeExpansionPreservesExistingValuesAndRaisesMaxima() throws {
        let range = IRGLScaleRange(
            minScaleX: 0.5,
            minScaleY: 0.6,
            maxScaleX: 2,
            maxScaleY: 3,
            defaultScaleX: 1.2,
            defaultScaleY: 1.3
        )

        let expanded = try XCTUnwrap(
            IRGLTransformController2D.expandedScaleRange(
                range,
                defaultScaleX: 5,
                defaultScaleY: 4
            )
        )

        XCTAssertEqual(expanded.minScaleX, 0.5, accuracy: 0.0001)
        XCTAssertEqual(expanded.minScaleY, 0.6, accuracy: 0.0001)
        XCTAssertEqual(expanded.maxScaleX, 5, accuracy: 0.0001)
        XCTAssertEqual(expanded.maxScaleY, 4, accuracy: 0.0001)
        XCTAssertEqual(expanded.defaultScaleX, 1.2, accuracy: 0.0001)
        XCTAssertEqual(expanded.defaultScaleY, 1.3, accuracy: 0.0001)
    }

    func testScaleRangeExpansionUsesUnitDefaultsWhenRangeIsMissing() throws {
        let expanded = try XCTUnwrap(
            IRGLTransformController2D.expandedScaleRange(
                nil,
                defaultScaleX: 3,
                defaultScaleY: 2
            )
        )

        XCTAssertEqual(expanded.minScaleX, 1, accuracy: 0.0001)
        XCTAssertEqual(expanded.minScaleY, 1, accuracy: 0.0001)
        XCTAssertEqual(expanded.maxScaleX, 3, accuracy: 0.0001)
        XCTAssertEqual(expanded.maxScaleY, 2, accuracy: 0.0001)
        XCTAssertEqual(expanded.defaultScaleX, 1, accuracy: 0.0001)
        XCTAssertEqual(expanded.defaultScaleY, 1, accuracy: 0.0001)
    }

    func testScaleRangeExpansionRejectsMalformedOrNonFiniteInput() {
        let malformed = IRGLScaleRange(
            minScaleX: 2,
            minScaleY: 1,
            maxScaleX: 1,
            maxScaleY: 4,
            defaultScaleX: 1,
            defaultScaleY: 1
        )

        XCTAssertNil(
            IRGLTransformController2D.expandedScaleRange(
                malformed,
                defaultScaleX: 3,
                defaultScaleY: 2
            )
        )
        XCTAssertNil(
            IRGLTransformController2D.expandedScaleRange(
                nil,
                defaultScaleX: .infinity,
                defaultScaleY: 2
            )
        )
    }

    func testDegreeScrollUnitsUseContentSizeAndWideDegree() throws {
        XCTAssertEqual(
            try XCTUnwrap(
                IRGLTransformController2D.degreeScrollUnits(
                    width: 100,
                    height: 80,
                    scaleX: 2,
                    scaleY: 3,
                    range: IRGLScopeRange(
                        minLat: -20,
                        maxLat: 20,
                        minLng: -50,
                        maxLng: 50,
                        defaultLat: 0,
                        defaultLng: 0
                    )
                )
            ),
            IRGLTransformController2D.DegreeScrollUnits(
                unitX: 2,
                unitY: 6
            )
        )
        XCTAssertEqual(
            try XCTUnwrap(
                IRGLTransformController2D.degreeScrollUnits(
                    width: 100,
                    height: 80,
                    scaleX: 2,
                    scaleY: 3,
                    range: nil
                )
            ),
            IRGLTransformController2D.DegreeScrollUnits(
                unitX: 0,
                unitY: 0
            )
        )
    }

    func testDegreeScrollUnitsRejectInvalidAndDerivedOverflow() {
        XCTAssertNil(
            IRGLTransformController2D.degreeScrollUnits(
                width: 0,
                height: 80,
                scaleX: 2,
                scaleY: 3,
                range: nil
            )
        )
        XCTAssertNil(
            IRGLTransformController2D.degreeScrollUnits(
                width: 2,
                height: 80,
                scaleX: .greatestFiniteMagnitude,
                scaleY: 3,
                range: IRGLScopeRange(
                    minLat: -20,
                    maxLat: 20,
                    minLng: -50,
                    maxLng: 50,
                    defaultLat: 0,
                    defaultLng: 0
                )
            )
        )
    }

    func testUpdateDecisionRejectsInvalidInputsAndDerivedOverflow() {
        let invalidSize = IRGLTransformController2D.Scope(
            width: 0,
            height: 100,
            scaleX: 1,
            scaleY: 1,
            offsetX: 0,
            offsetY: 0
        )
        let scope = invalidSize.with(width: 100)

        XCTAssertNil(
            IRGLTransformController2D.updateDecision(
                scope: invalidSize,
                fx: 0,
                fy: 0,
                sx: 2,
                sy: 2,
                scaleRange: nil
            )
        )
        XCTAssertNil(
            IRGLTransformController2D.updateDecision(
                scope: scope,
                fx: .nan,
                fy: 0,
                sx: 2,
                sy: 2,
                scaleRange: nil
            )
        )
        XCTAssertNil(
            IRGLTransformController2D.updateDecision(
                scope: scope,
                fx: 0,
                fy: 0,
                sx: 0,
                sy: 2,
                scaleRange: nil
            )
        )
        XCTAssertNil(
            IRGLTransformController2D.updateDecision(
                scope: scope,
                fx: .greatestFiniteMagnitude,
                fy: 0,
                sx: 4,
                sy: 4,
                scaleRange: IRGLScaleRange(
                    minScaleX: 1,
                    minScaleY: 1,
                    maxScaleX: 4,
                    maxScaleY: 4,
                    defaultScaleX: 1,
                    defaultScaleY: 1
                )
            )
        )
    }

    func testUpdateDecisionClampsScaleAndOffsets() throws {
        let scope = IRGLTransformController2D.Scope(
            width: 100,
            height: 100,
            scaleX: 1,
            scaleY: 1,
            offsetX: 0,
            offsetY: 0
        )
        let range = IRGLScaleRange(
            minScaleX: 1,
            minScaleY: 1,
            maxScaleX: 4,
            maxScaleY: 4,
            defaultScaleX: 1,
            defaultScaleY: 1
        )

        let zoomIn = try XCTUnwrap(
            IRGLTransformController2D.updateDecision(
                scope: scope,
                fx: 50,
                fy: 50,
                sx: 2,
                sy: 2,
                scaleRange: range
            )
        )
        XCTAssertEqual(zoomIn.scaleX, 2, accuracy: 0.0001)
        XCTAssertEqual(zoomIn.scaleY, 2, accuracy: 0.0001)
        XCTAssertEqual(zoomIn.offsetX, 25, accuracy: 0.0001)
        XCTAssertEqual(zoomIn.offsetY, 25, accuracy: 0.0001)
        XCTAssertEqual(zoomIn.maxX0, 50, accuracy: 0.0001)
        XCTAssertEqual(zoomIn.maxY0, 50, accuracy: 0.0001)

        let clamped = try XCTUnwrap(
            IRGLTransformController2D.updateDecision(
                scope: scope,
                fx: 50,
                fy: 50,
                sx: 10,
                sy: 10,
                scaleRange: range
            )
        )
        XCTAssertEqual(clamped.scaleX, 4, accuracy: 0.0001)
        XCTAssertEqual(clamped.scaleY, 4, accuracy: 0.0001)
        XCTAssertEqual(clamped.offsetX, 37.5, accuracy: 0.0001)
        XCTAssertEqual(clamped.offsetY, 37.5, accuracy: 0.0001)
    }

    func testUpdateDecisionNormalizesSubUnitScaleByDominantAxis() throws {
        let scope = IRGLTransformController2D.Scope(
            width: 100,
            height: 80,
            scaleX: 2,
            scaleY: 4,
            offsetX: 0,
            offsetY: 0
        )

        let xDominant = try XCTUnwrap(
            IRGLTransformController2D.updateDecision(
                scope: scope,
                fx: 0,
                fy: 0,
                sx: 0.5,
                sy: 0.8,
                scaleRange: nil
            )
        )
        XCTAssertEqual(xDominant.scaleX, 0.5, accuracy: 0.0001)
        XCTAssertEqual(xDominant.scaleY, 1, accuracy: 0.0001)

        let yDominant = try XCTUnwrap(
            IRGLTransformController2D.updateDecision(
                scope: scope,
                fx: 0,
                fy: 0,
                sx: 0.8,
                sy: 0.5,
                scaleRange: nil
            )
        )
        XCTAssertEqual(yDominant.scaleX, 1, accuracy: 0.0001)
        XCTAssertEqual(yDominant.scaleY, 2, accuracy: 0.0001)
    }

    func testUpdateDecisionClampsOversizedScaleByDominantAxis() throws {
        let scope = IRGLTransformController2D.Scope(
            width: 100,
            height: 80,
            scaleX: 2,
            scaleY: 4,
            offsetX: 0,
            offsetY: 0
        )
        let range = IRGLScaleRange(
            minScaleX: 1,
            minScaleY: 1,
            maxScaleX: 3,
            maxScaleY: 5,
            defaultScaleX: 1,
            defaultScaleY: 1
        )

        let xDominant = try XCTUnwrap(
            IRGLTransformController2D.updateDecision(
                scope: scope,
                fx: 0,
                fy: 0,
                sx: 8,
                sy: 10,
                scaleRange: range
            )
        )
        XCTAssertEqual(xDominant.scaleX, 2.5, accuracy: 0.0001)
        XCTAssertEqual(xDominant.scaleY, 5, accuracy: 0.0001)

        let nilRangeXDominant = try XCTUnwrap(
            IRGLTransformController2D.updateDecision(
                scope: scope,
                fx: 0,
                fy: 0,
                sx: 8,
                sy: 10,
                scaleRange: nil
            )
        )
        XCTAssertEqual(nilRangeXDominant.scaleX, 0.5, accuracy: 0.0001)
        XCTAssertEqual(nilRangeXDominant.scaleY, 1, accuracy: 0.0001)

        let nilRangeYDominant = try XCTUnwrap(
            IRGLTransformController2D.updateDecision(
                scope: scope,
                fx: 0,
                fy: 0,
                sx: 10,
                sy: 8,
                scaleRange: nil
            )
        )
        XCTAssertEqual(nilRangeYDominant.scaleX, 1, accuracy: 0.0001)
        XCTAssertEqual(nilRangeYDominant.scaleY, 2, accuracy: 0.0001)
    }

    func testScrollDecisionClampsOffsetsAndReportsStatus() throws {
        let decision = try XCTUnwrap(
            IRGLTransformController2D.scrollDecision(
                offsetX: 25,
                offsetY: 25,
                scaleX: 2,
                scaleY: 2,
                maxX0: 50,
                maxY0: 50,
                dx: 1_000,
                dy: -1_000
            )
        )

        XCTAssertEqual(decision.offsetX, 50, accuracy: 0.0001)
        XCTAssertEqual(decision.offsetY, 0, accuracy: 0.0001)
        XCTAssertTrue(decision.status.contains(.toMaxX))
        XCTAssertTrue(decision.status.contains(.toMinY))
    }

    func testScrollDecisionReportsMinimumXAndMaximumYBounds() throws {
        let decision = try XCTUnwrap(
            IRGLTransformController2D.scrollDecision(
                offsetX: 25,
                offsetY: 25,
                scaleX: 2,
                scaleY: 2,
                maxX0: 50,
                maxY0: 50,
                dx: -1_000,
                dy: 1_000
            )
        )

        XCTAssertEqual(decision.offsetX, 0, accuracy: 0.0001)
        XCTAssertEqual(decision.offsetY, 50, accuracy: 0.0001)
        XCTAssertTrue(decision.status.contains(.toMinX))
        XCTAssertTrue(decision.status.contains(.toMaxY))
    }

    func testScrollDecisionRejectsInvalidInputsAndDerivedOverflow() {
        XCTAssertNil(
            IRGLTransformController2D.scrollDecision(
                offsetX: 0,
                offsetY: 0,
                scaleX: 0,
                scaleY: 1,
                maxX0: 0,
                maxY0: 0,
                dx: 1,
                dy: 1
            )
        )
        XCTAssertNil(
            IRGLTransformController2D.scrollDecision(
                offsetX: 0,
                offsetY: 0,
                scaleX: 1,
                scaleY: 1,
                maxX0: -1,
                maxY0: 0,
                dx: 1,
                dy: 1
            )
        )
        XCTAssertNil(
            IRGLTransformController2D.scrollDecision(
                offsetX: .greatestFiniteMagnitude,
                offsetY: 0,
                scaleX: 1,
                scaleY: 1,
                maxX0: .greatestFiniteMagnitude,
                maxY0: 0,
                dx: .greatestFiniteMagnitude,
                dy: 0
            )
        )
    }

    func testResizeDecisionScalesOffsetsAndRecomputesBounds() throws {
        let decision = try XCTUnwrap(
            IRGLTransformController2D.resizeDecision(
                width: 200,
                height: 100,
                scaleX: 2,
                scaleY: 4,
                offsetX: 25,
                offsetY: 10,
                oldRW: 0.02,
                oldRH: 0.04
            )
        )

        XCTAssertEqual(decision.rW, 0.01, accuracy: 0.0001)
        XCTAssertEqual(decision.rH, 0.04, accuracy: 0.0001)
        XCTAssertEqual(decision.maxX0, 100, accuracy: 0.0001)
        XCTAssertEqual(decision.maxY0, 75, accuracy: 0.0001)
        XCTAssertEqual(decision.offsetX, 50, accuracy: 0.0001)
        XCTAssertEqual(decision.offsetY, 10, accuracy: 0.0001)
    }

    func testResizeDecisionRejectsInvalidInputsAndDerivedOverflow() {
        XCTAssertNil(
            IRGLTransformController2D.resizeDecision(
                width: 0,
                height: 100,
                scaleX: 1,
                scaleY: 1,
                offsetX: 0,
                offsetY: 0,
                oldRW: 1,
                oldRH: 1
            )
        )
        XCTAssertNil(
            IRGLTransformController2D.resizeDecision(
                width: 100,
                height: 100,
                scaleX: 1,
                scaleY: 1,
                offsetX: 0,
                offsetY: 0,
                oldRW: 0,
                oldRH: 1
            )
        )
        XCTAssertNil(
            IRGLTransformController2D.resizeDecision(
                width: 100,
                height: 100,
                scaleX: 1,
                scaleY: 1,
                offsetX: .greatestFiniteMagnitude,
                offsetY: 0,
                oldRW: .greatestFiniteMagnitude,
                oldRH: 1
            )
        )
    }

    func testResizeDecisionClampsOffsetsToRecomputedBounds() throws {
        let decision = try XCTUnwrap(
            IRGLTransformController2D.resizeDecision(
                width: 100,
                height: 100,
                scaleX: 2,
                scaleY: 2,
                offsetX: 100,
                offsetY: -10,
                oldRW: 0.02,
                oldRH: 0.02
            )
        )

        XCTAssertEqual(decision.maxX0, 50, accuracy: 0.0001)
        XCTAssertEqual(decision.maxY0, 50, accuracy: 0.0001)
        XCTAssertEqual(decision.offsetX, 50, accuracy: 0.0001)
        XCTAssertEqual(decision.offsetY, 0, accuracy: 0.0001)
    }

    func testResizeDecisionUsesZeroBoundsForSubUnitScale() throws {
        let decision = try XCTUnwrap(
            IRGLTransformController2D.resizeDecision(
                width: 100,
                height: 100,
                scaleX: 0.5,
                scaleY: 0.75,
                offsetX: 10,
                offsetY: 20,
                oldRW: 0.01,
                oldRH: 0.02
            )
        )

        XCTAssertEqual(decision.maxX0, 0, accuracy: 0.0001)
        XCTAssertEqual(decision.maxY0, 0, accuracy: 0.0001)
        XCTAssertEqual(decision.offsetX, 0, accuracy: 0.0001)
        XCTAssertEqual(decision.offsetY, 0, accuracy: 0.0001)
        XCTAssertEqual(decision.rW, 0.005, accuracy: 0.0001)
        XCTAssertEqual(decision.rH, 0.0075, accuracy: 0.0001)
    }
}

private extension IRGLTransformController2D.Scope {
    func with(width: Int) -> IRGLTransformController2D.Scope {
        return IRGLTransformController2D.Scope(
            width: width,
            height: height,
            scaleX: scaleX,
            scaleY: scaleY,
            offsetX: offsetX,
            offsetY: offsetY
        )
    }
}
