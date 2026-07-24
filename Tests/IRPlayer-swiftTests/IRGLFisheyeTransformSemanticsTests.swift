import XCTest
@testable import IRPlayer_swift

final class IRGLFisheyeTransformSemanticsTests: XCTestCase {

    func testScopeRangesMatchFisheyeTiltDefaults() {
        assertScopeRange(
            IRGLTransformController3DFisheye.scopeRange(for: .up),
            minLat: -80,
            maxLat: 80,
            minLng: -75,
            maxLng: 75,
            defaultLat: 0,
            defaultLng: 0
        )
        assertScopeRange(
            IRGLTransformController3DFisheye.scopeRange(for: .toward),
            minLat: 0,
            maxLat: 80,
            minLng: -180,
            maxLng: 180,
            defaultLat: 80,
            defaultLng: -90
        )
        assertScopeRange(
            IRGLTransformController3DFisheye.scopeRange(for: .backward),
            minLat: -85,
            maxLat: -20,
            minLng: -180,
            maxLng: 180,
            defaultLat: -80,
            defaultLng: 90
        )
        assertScopeRange(
            IRGLTransformController3DFisheye.scopeRange(for: .unknown),
            minLat: 0,
            maxLat: 0,
            minLng: 0,
            maxLng: 0,
            defaultLat: 0,
            defaultLng: 0
        )
    }

    func testAspectRatioFallsBackForInvalidDimensions() {
        XCTAssertEqual(
            IRGLTransformController3DFisheye.aspectRatio(
                width: 1920,
                height: 960
            ),
            2,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            IRGLTransformController3DFisheye.aspectRatio(
                width: 0,
                height: 960
            ),
            1,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            IRGLTransformController3DFisheye.aspectRatio(
                width: 1920,
                height: 0
            ),
            1,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            IRGLTransformController3DFisheye.aspectRatio(
                width: -1,
                height: 960
            ),
            1,
            accuracy: 0.0001
        )
    }

    func testScaleDecisionRejectsInvalidInputs() {
        XCTAssertNil(
            IRGLTransformController3DFisheye.scaleDecision(
                requestedScale: .nan,
                maxScale: 4,
                tanbase: 1
            )
        )
        XCTAssertNil(
            IRGLTransformController3DFisheye.scaleDecision(
                requestedScale: 2,
                maxScale: 0.5,
                tanbase: 1
            )
        )
        XCTAssertNil(
            IRGLTransformController3DFisheye.scaleDecision(
                requestedScale: 2,
                maxScale: 4,
                tanbase: 0
            )
        )
        XCTAssertNil(
            IRGLTransformController3DFisheye.scaleDecision(
                requestedScale: 0,
                maxScale: 4,
                tanbase: 1
            )
        )
    }

    func testScaleDecisionClampsScaleAndCalculatesFov() throws {
        let defaultDecision = try XCTUnwrap(
            IRGLTransformController3DFisheye.scaleDecision(
                requestedScale: 0.5,
                maxScale: 4,
                tanbase: 1
            )
        )
        XCTAssertEqual(defaultDecision.scale, 1, accuracy: 0.0001)
        XCTAssertEqual(
            defaultDecision.fovDegrees,
            90,
            accuracy: 0.0001
        )

        let clampedDecision = try XCTUnwrap(
            IRGLTransformController3DFisheye.scaleDecision(
                requestedScale: 10,
                maxScale: 4,
                tanbase: 1
            )
        )
        XCTAssertEqual(clampedDecision.scale, 4, accuracy: 0.0001)
        XCTAssertEqual(
            clampedDecision.fovDegrees,
            28.0725,
            accuracy: 0.0001
        )
    }

    func testScrollDecisionRejectsMalformedAndDerivedOverflow() {
        let range =
            IRGLTransformController3DFisheye.scopeRange(for: .up)

        XCTAssertNil(
            IRGLTransformController3DFisheye.scrollDecision(
                currentLat: 0,
                currentLng: 0,
                dx: .nan,
                dy: 0,
                friction: 0.15,
                range: range
            )
        )
        XCTAssertNil(
            IRGLTransformController3DFisheye.scrollDecision(
                currentLat: 0,
                currentLng: 0,
                dx: 0,
                dy: 0,
                friction: -1,
                range: range
            )
        )
        XCTAssertNil(
            IRGLTransformController3DFisheye.scrollDecision(
                currentLat: .greatestFiniteMagnitude,
                currentLng: 0,
                dx: -.greatestFiniteMagnitude,
                dy: -.greatestFiniteMagnitude,
                friction: 1,
                range: range
            )
        )
    }

    func testScrollDecisionAppliesFrictionAndReportsBounds() throws {
        let range =
            IRGLTransformController3DFisheye.scopeRange(for: .up)

        let maxDecision = try XCTUnwrap(
            IRGLTransformController3DFisheye.scrollDecision(
                currentLat: 0,
                currentLng: 0,
                dx: -1_000,
                dy: -1_000,
                friction: 0.15,
                range: range
            )
        )
        XCTAssertEqual(maxDecision.lat, 150, accuracy: 0.0001)
        XCTAssertEqual(maxDecision.lng, 150, accuracy: 0.0001)
        XCTAssertTrue(maxDecision.status.contains(.toMaxX))
        XCTAssertTrue(maxDecision.status.contains(.toMaxY))

        let minDecision = try XCTUnwrap(
            IRGLTransformController3DFisheye.scrollDecision(
                currentLat: 0,
                currentLng: 0,
                dx: 1_000,
                dy: 1_000,
                friction: 0.15,
                range: range
            )
        )
        XCTAssertEqual(minDecision.lat, -150, accuracy: 0.0001)
        XCTAssertEqual(minDecision.lng, -150, accuracy: 0.0001)
        XCTAssertTrue(minDecision.status.contains(.toMinX))
        XCTAssertTrue(minDecision.status.contains(.toMinY))
    }

    func testScrollDecisionUsesNoBoundsWhenRangeIsMissing() throws {
        let decision = try XCTUnwrap(
            IRGLTransformController3DFisheye.scrollDecision(
                currentLat: 0,
                currentLng: 0,
                dx: 1,
                dy: -1,
                friction: 1,
                range: nil
            )
        )

        XCTAssertEqual(decision.lat, 1, accuracy: 0.0001)
        XCTAssertEqual(decision.lng, -1, accuracy: 0.0001)
        XCTAssertTrue(decision.status.isEmpty)
    }

    func testNormalizedScopeWrapsAndClampsLatitudeAndLongitude() {
        let range =
            IRGLTransformController3DFisheye.scopeRange(for: .up)

        XCTAssertEqual(
            IRGLTransformController3DFisheye.normalizedScope(
                lat: 150,
                lng: 150,
                fov: 60,
                range: range
            ),
            IRGLTransformController3DFisheye.NormalizedScope(
                lat: -30,
                lng: 75
            )
        )
        XCTAssertEqual(
            IRGLTransformController3DFisheye.normalizedScope(
                lat: -150,
                lng: -150,
                fov: 60,
                range: range
            ),
            IRGLTransformController3DFisheye.NormalizedScope(
                lat: 30,
                lng: -75
            )
        )
        XCTAssertEqual(
            IRGLTransformController3DFisheye.normalizedScope(
                lat: 80,
                lng: 540,
                fov: 60,
                range: range
            ),
            IRGLTransformController3DFisheye.NormalizedScope(
                lat: 50,
                lng: 75
            )
        )
        XCTAssertEqual(
            IRGLTransformController3DFisheye.normalizedScope(
                lat: 0,
                lng: -540,
                fov: 60,
                range: range
            ),
            IRGLTransformController3DFisheye.NormalizedScope(
                lat: 0,
                lng: 75
            )
        )
        XCTAssertEqual(
            IRGLTransformController3DFisheye.normalizedScope(
                lat: -450,
                lng: 181,
                fov: 60,
                range: range
            ),
            IRGLTransformController3DFisheye.NormalizedScope(
                lat: 50,
                lng: -75
            )
        )
    }

    func testNormalizedScopeHandlesHugeFiniteAnglesInConstantWork() throws {
        let range =
            IRGLTransformController3DFisheye.scopeRange(for: .up)
        let normalized = try XCTUnwrap(
            IRGLTransformController3DFisheye.normalizedScope(
                lat: .greatestFiniteMagnitude,
                lng: -.greatestFiniteMagnitude,
                fov: 60,
                range: range
            )
        )

        XCTAssertGreaterThanOrEqual(normalized.lat, -80)
        XCTAssertLessThanOrEqual(normalized.lat, 50)
        XCTAssertGreaterThanOrEqual(normalized.lng, -75)
        XCTAssertLessThanOrEqual(normalized.lng, 75)
    }

    func testNormalizedScopeRejectsInvalidAndDerivedOverflow() {
        let range =
            IRGLTransformController3DFisheye.scopeRange(for: .up)
        let malformed = IRGLScopeRange(
            minLat: 80,
            maxLat: -80,
            minLng: -75,
            maxLng: 75,
            defaultLat: 0,
            defaultLng: 0
        )

        XCTAssertNil(
            IRGLTransformController3DFisheye.normalizedScope(
                lat: .nan,
                lng: 0,
                fov: 60,
                range: range
            )
        )
        XCTAssertNil(
            IRGLTransformController3DFisheye.normalizedScope(
                lat: 0,
                lng: 0,
                fov: .greatestFiniteMagnitude,
                range: range
            )
        )
        XCTAssertNil(
            IRGLTransformController3DFisheye.normalizedScope(
                lat: 0,
                lng: 0,
                fov: 60,
                range: malformed
            )
        )
    }

    func testNormalizedScopeUsesZeroBoundsWhenRangeIsMissing() {
        XCTAssertEqual(
            IRGLTransformController3DFisheye.normalizedScope(
                lat: 30,
                lng: 45,
                fov: 60,
                range: nil
            ),
            IRGLTransformController3DFisheye.NormalizedScope(
                lat: 0,
                lng: 0
            )
        )
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
    XCTAssertEqual(
        range.minLat,
        minLat,
        accuracy: 0.0001,
        file: file,
        line: line
    )
    XCTAssertEqual(
        range.maxLat,
        maxLat,
        accuracy: 0.0001,
        file: file,
        line: line
    )
    XCTAssertEqual(
        range.minLng,
        minLng,
        accuracy: 0.0001,
        file: file,
        line: line
    )
    XCTAssertEqual(
        range.maxLng,
        maxLng,
        accuracy: 0.0001,
        file: file,
        line: line
    )
    XCTAssertEqual(
        range.defaultLat,
        defaultLat,
        accuracy: 0.0001,
        file: file,
        line: line
    )
    XCTAssertEqual(
        range.defaultLng,
        defaultLng,
        accuracy: 0.0001,
        file: file,
        line: line
    )
}
