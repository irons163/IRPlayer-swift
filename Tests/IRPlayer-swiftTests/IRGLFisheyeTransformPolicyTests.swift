import XCTest
@testable import IRPlayer_swift

final class IRGLFisheyeTransformPolicyTests: XCTestCase {

    func testScopeRangesMatchFisheyeTiltDefaults() {
        assertScopeRange(
            IRGLFisheyeTransformPolicy.scopeRange(for: .up),
            minLat: -80,
            maxLat: 80,
            minLng: -75,
            maxLng: 75,
            defaultLat: 0,
            defaultLng: 0
        )
        assertScopeRange(
            IRGLFisheyeTransformPolicy.scopeRange(for: .toward),
            minLat: 0,
            maxLat: 80,
            minLng: -180,
            maxLng: 180,
            defaultLat: 80,
            defaultLng: -90
        )
        assertScopeRange(
            IRGLFisheyeTransformPolicy.scopeRange(for: .backward),
            minLat: -85,
            maxLat: -20,
            minLng: -180,
            maxLng: 180,
            defaultLat: -80,
            defaultLng: 90
        )
        assertScopeRange(
            IRGLFisheyeTransformPolicy.scopeRange(for: .unknown),
            minLat: 0,
            maxLat: 0,
            minLng: 0,
            maxLng: 0,
            defaultLat: 0,
            defaultLng: 0
        )
    }

    func testAspectRatioFallsBackForInvalidDimensions() {
        XCTAssertEqual(IRGLFisheyeTransformPolicy.aspectRatio(width: 1920, height: 960), 2, accuracy: 0.0001)
        XCTAssertEqual(IRGLFisheyeTransformPolicy.aspectRatio(width: 0, height: 960), 1, accuracy: 0.0001)
        XCTAssertEqual(IRGLFisheyeTransformPolicy.aspectRatio(width: 1920, height: 0), 1, accuracy: 0.0001)
        XCTAssertEqual(IRGLFisheyeTransformPolicy.aspectRatio(width: -1, height: 960), 1, accuracy: 0.0001)
    }

    func testScaleDecisionRejectsInvalidInputs() {
        XCTAssertNil(IRGLFisheyeTransformPolicy.scaleDecision(requestedScale: .nan, maxScale: 4, tanbase: 1))
        XCTAssertNil(IRGLFisheyeTransformPolicy.scaleDecision(requestedScale: 2, maxScale: .nan, tanbase: 1))
        XCTAssertNil(IRGLFisheyeTransformPolicy.scaleDecision(requestedScale: 2, maxScale: 4, tanbase: .nan))
        XCTAssertNil(IRGLFisheyeTransformPolicy.scaleDecision(requestedScale: 0, maxScale: 4, tanbase: 1))
    }

    func testScaleDecisionClampsScaleAndCalculatesFov() throws {
        let defaultDecision = try XCTUnwrap(IRGLFisheyeTransformPolicy.scaleDecision(requestedScale: 0.5, maxScale: 4, tanbase: 1))
        XCTAssertEqual(defaultDecision.scale, 1, accuracy: 0.0001)
        XCTAssertEqual(defaultDecision.fovDegrees, 90, accuracy: 0.0001)

        let clampedDecision = try XCTUnwrap(IRGLFisheyeTransformPolicy.scaleDecision(requestedScale: 10, maxScale: 4, tanbase: 1))
        XCTAssertEqual(clampedDecision.scale, 4, accuracy: 0.0001)
        XCTAssertEqual(clampedDecision.fovDegrees, 28.0725, accuracy: 0.0001)
    }

    func testScrollDecisionRejectsNonFiniteDeltas() {
        let range = IRGLFisheyeTransformPolicy.scopeRange(for: .up)

        XCTAssertNil(IRGLFisheyeTransformPolicy.scrollDecision(currentLat: 0, currentLng: 0, dx: .nan, dy: 0, friction: 0.15, range: range))
        XCTAssertNil(IRGLFisheyeTransformPolicy.scrollDecision(currentLat: 0, currentLng: 0, dx: 0, dy: .infinity, friction: 0.15, range: range))
    }

    func testScrollDecisionAppliesFrictionAndReportsBounds() throws {
        let range = IRGLFisheyeTransformPolicy.scopeRange(for: .up)

        let maxDecision = try XCTUnwrap(IRGLFisheyeTransformPolicy.scrollDecision(currentLat: 0, currentLng: 0, dx: -1_000, dy: -1_000, friction: 0.15, range: range))
        XCTAssertEqual(maxDecision.lat, 150, accuracy: 0.0001)
        XCTAssertEqual(maxDecision.lng, 150, accuracy: 0.0001)
        XCTAssertTrue(maxDecision.status.contains(.toMaxX))
        XCTAssertTrue(maxDecision.status.contains(.toMaxY))

        let minDecision = try XCTUnwrap(IRGLFisheyeTransformPolicy.scrollDecision(currentLat: 0, currentLng: 0, dx: 1_000, dy: 1_000, friction: 0.15, range: range))
        XCTAssertEqual(minDecision.lat, -150, accuracy: 0.0001)
        XCTAssertEqual(minDecision.lng, -150, accuracy: 0.0001)
        XCTAssertTrue(minDecision.status.contains(.toMinX))
        XCTAssertTrue(minDecision.status.contains(.toMinY))
    }

    func testNormalizedScopeWrapsAndClampsLatitudeAndLongitude() {
        let range = IRGLFisheyeTransformPolicy.scopeRange(for: .up)

        XCTAssertEqual(
            IRGLFisheyeTransformPolicy.normalizedScope(lat: 150, lng: 150, fov: 60, range: range),
            IRGLFisheyeTransformPolicy.NormalizedScope(lat: -30, lng: 75)
        )
        XCTAssertEqual(
            IRGLFisheyeTransformPolicy.normalizedScope(lat: -150, lng: -150, fov: 60, range: range),
            IRGLFisheyeTransformPolicy.NormalizedScope(lat: 50, lng: -75)
        )
        XCTAssertEqual(
            IRGLFisheyeTransformPolicy.normalizedScope(lat: 80, lng: 540, fov: 60, range: range),
            IRGLFisheyeTransformPolicy.NormalizedScope(lat: 50, lng: 75)
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
    XCTAssertEqual(range.minLat, minLat, accuracy: 0.0001, file: file, line: line)
    XCTAssertEqual(range.maxLat, maxLat, accuracy: 0.0001, file: file, line: line)
    XCTAssertEqual(range.minLng, minLng, accuracy: 0.0001, file: file, line: line)
    XCTAssertEqual(range.maxLng, maxLng, accuracy: 0.0001, file: file, line: line)
    XCTAssertEqual(range.defaultLat, defaultLat, accuracy: 0.0001, file: file, line: line)
    XCTAssertEqual(range.defaultLng, defaultLng, accuracy: 0.0001, file: file, line: line)
}
