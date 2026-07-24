import XCTest
#if SWIFT_PACKAGE
@testable import IRPlayerSwift
#else
@testable import IRPlayer_swift
#endif

final class IRPlaybackTimeRangeTests: XCTestCase {

    func testInitializerAcceptsFiniteNonNegativeDuration() {
        XCTAssertEqual(
            IRPlaybackTimeRange(duration: 0),
            IRPlaybackTimeRange(duration: 0)
        )
        XCTAssertEqual(
            IRPlaybackTimeRange(duration: 12)?.duration,
            12
        )
    }

    func testInitializerRejectsInvalidDuration() {
        for duration in [
            -1,
            TimeInterval.nan,
            .infinity,
            -.infinity
        ] {
            XCTAssertNil(IRPlaybackTimeRange(duration: duration))
        }
    }

    func testClampPreservesInRangeTime() throws {
        let range = try XCTUnwrap(
            IRPlaybackTimeRange(duration: 10)
        )

        XCTAssertEqual(range.clamped(4), 4)
    }

    func testClampBoundsTimeToClosedRange() throws {
        let range = try XCTUnwrap(
            IRPlaybackTimeRange(duration: 10)
        )

        XCTAssertEqual(range.clamped(-1), 0)
        XCTAssertEqual(range.clamped(12), 10)
    }

    func testZeroDurationAlwaysClampsToZero() throws {
        let range = try XCTUnwrap(
            IRPlaybackTimeRange(duration: 0)
        )

        XCTAssertEqual(range.clamped(-1), 0)
        XCTAssertEqual(range.clamped(0), 0)
        XCTAssertEqual(range.clamped(1), 0)
    }

    func testClampRejectsNonFiniteTime() throws {
        let range = try XCTUnwrap(
            IRPlaybackTimeRange(duration: 10)
        )

        XCTAssertNil(range.clamped(.nan))
        XCTAssertNil(range.clamped(.infinity))
        XCTAssertNil(range.clamped(-.infinity))
    }
}
