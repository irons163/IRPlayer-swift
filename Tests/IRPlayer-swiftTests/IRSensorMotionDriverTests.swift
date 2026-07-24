import XCTest
@testable import IRPlayer_swift

final class IRSensorMotionDriverTests: XCTestCase {
    func testQuaternionNormalizesFiniteValues() throws {
        let quaternion = try XCTUnwrap(
            IRSensorQuaternion(
                x: 0,
                y: 0,
                z: 0,
                w: 2
            ).normalized()
        )

        XCTAssertEqual(quaternion.x, 0)
        XCTAssertEqual(quaternion.y, 0)
        XCTAssertEqual(quaternion.z, 0)
        XCTAssertEqual(quaternion.w, 1)
    }

    func testQuaternionRejectsInvalidNorms() {
        XCTAssertNil(
            IRSensorQuaternion(
                x: 0,
                y: 0,
                z: 0,
                w: 0
            ).normalized()
        )
        XCTAssertNil(
            IRSensorQuaternion(
                x: .infinity,
                y: 0,
                z: 0,
                w: 1
            ).normalized()
        )
    }

    func testRelativeQuaternionUsesCurrentTimesInverseReference()
        throws
    {
        let quarterTurn = Double.pi / 2
        let current = IRSensorQuaternion(
            x: sin(quarterTurn / 2),
            y: 0,
            z: 0,
            w: cos(quarterTurn / 2)
        )
        let relative = try XCTUnwrap(
            current.relative(
                to: IRSensorQuaternion(
                    x: 0,
                    y: 0,
                    z: 0,
                    w: 1
                )
            )
        )

        XCTAssertEqual(
            relative.x,
            current.x,
            accuracy: 0.000_001
        )
        XCTAssertEqual(
            relative.w,
            current.w,
            accuracy: 0.000_001
        )
    }

    func testRelativeQuaternionNormalizesAndRejectsInvalidValues()
        throws
    {
        let angle = 20.0 * Double.pi / 180.0
        let relative = try XCTUnwrap(
            IRSensorQuaternion(
                x: sin(angle / 2) * 2,
                y: 0,
                z: 0,
                w: cos(angle / 2) * 2
            ).relative(
                to: IRSensorQuaternion(
                    x: 0,
                    y: 0,
                    z: 0,
                    w: 1
                )
            )
        )

        XCTAssertEqual(
            relative.x,
            sin(angle / 2),
            accuracy: 0.000_001
        )
        XCTAssertEqual(
            relative.w,
            cos(angle / 2),
            accuracy: 0.000_001
        )
        XCTAssertNil(
            IRSensorQuaternion(
                x: .nan,
                y: 0,
                z: 0,
                w: 1
            ).normalized()
        )
    }

    func testMotionSampleRequiresEveryComponentToBeFinite() {
        XCTAssertTrue(
            IRSensorMotionSample(
                quaternion: IRSensorQuaternion(
                    x: 0,
                    y: 0,
                    z: 0,
                    w: 1
                ),
                pitchDegrees: 20,
                rollDegrees: 0
            ).isFinite
        )
        XCTAssertFalse(
            IRSensorMotionSample(
                quaternion: IRSensorQuaternion(
                    x: 0,
                    y: 0,
                    z: 0,
                    w: 1
                ),
                pitchDegrees: .nan,
                rollDegrees: 0
            ).isFinite
        )
    }
}
