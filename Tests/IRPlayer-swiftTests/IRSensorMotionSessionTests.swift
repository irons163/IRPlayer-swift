import Foundation
import XCTest
import UIKit
#if SWIFT_PACKAGE
@testable import IRPlayerSwift
#else
@testable import IRPlayer_swift
#endif

final class IRSensorMotionSessionTests: XCTestCase {
    func testNormalizedDeltaWrapsAcrossHalfTurns() {
        XCTAssertEqual(
            IRSensorMotionSession.normalizedDelta(
                current: -170,
                previous: 170
            ),
            20,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            IRSensorMotionSession.normalizedDelta(
                current: 170,
                previous: -170
            ),
            -20,
            accuracy: 0.0001
        )
    }

    func testNormalizedDeltaKeepsSmallOffsets() {
        XCTAssertEqual(
            IRSensorMotionSession.normalizedDelta(
                current: 45,
                previous: 15
            ),
            30,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            IRSensorMotionSession.normalizedDelta(
                current: -20,
                previous: 15
            ),
            -35,
            accuracy: 0.0001
        )
    }

    func testNormalizedDeltaRejectsNonFiniteInputs() {
        XCTAssertEqual(
            IRSensorMotionSession.normalizedDelta(
                current: .nan,
                previous: 15
            ),
            0
        )
        XCTAssertEqual(
            IRSensorMotionSession.normalizedDelta(
                current: 15,
                previous: .infinity
            ),
            0
        )
    }

    func testNormalizedDeltaRejectsOverflow() {
        XCTAssertEqual(
            IRSensorMotionSession.normalizedDelta(
                current: .greatestFiniteMagnitude,
                previous: -.greatestFiniteMagnitude
            ),
            0
        )
    }

    func testScrollShiftConvertsFiniteDeltasWithoutOutput() {
        let output = captureStandardOutput {
            guard let shift =
                    IRSensorMotionSession.scrollShift(
                        dx: 12.5,
                        dy: -6.25
                    ) else {
                XCTFail("Expected a finite shift")
                return
            }

            XCTAssertEqual(
                shift.degreeX,
                12.5,
                accuracy: 0.0001
            )
            XCTAssertEqual(
                shift.degreeY,
                -6.25,
                accuracy: 0.0001
            )
        }

        XCTAssertEqual(output, "")
    }

    func testScrollShiftRejectsNonFiniteDeltas() {
        XCTAssertNil(
            IRSensorMotionSession.scrollShift(
                dx: .nan,
                dy: 1
            )
        )
        XCTAssertNil(
            IRSensorMotionSession.scrollShift(
                dx: 1,
                dy: .infinity
            )
        )
    }

    func testDegreesMapsSupportedOrientations() throws {
        let inversePitch = Double.pi / 6
        let inverseRoll = Double.pi / 3

        let portrait = try XCTUnwrap(
            IRSensorMotionSession.degrees(
                inversePitchRadians: inversePitch,
                inverseRollRadians: inverseRoll,
                pitchDegrees: 20,
                rollDegrees: 0,
                orientation: .portrait
            )
        )
        XCTAssertEqual(
            portrait.degreeX,
            60,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            portrait.degreeY,
            30,
            accuracy: 0.0001
        )

        let upsideDown = try XCTUnwrap(
            IRSensorMotionSession.degrees(
                inversePitchRadians: inversePitch,
                inverseRollRadians: inverseRoll,
                pitchDegrees: -20,
                rollDegrees: 0,
                orientation: .portraitUpsideDown
            )
        )
        XCTAssertEqual(
            upsideDown.degreeX,
            -60,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            upsideDown.degreeY,
            -30,
            accuracy: 0.0001
        )

        let landscapeLeft = try XCTUnwrap(
            IRSensorMotionSession.degrees(
                inversePitchRadians: inversePitch,
                inverseRollRadians: inverseRoll,
                pitchDegrees: 0,
                rollDegrees: 20,
                orientation: .landscapeLeft
            )
        )
        XCTAssertEqual(
            landscapeLeft.degreeX,
            -30,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            landscapeLeft.degreeY,
            60,
            accuracy: 0.0001
        )

        let landscapeRight = try XCTUnwrap(
            IRSensorMotionSession.degrees(
                inversePitchRadians: inversePitch,
                inverseRollRadians: inverseRoll,
                pitchDegrees: 0,
                rollDegrees: -20,
                orientation: .landscapeRight
            )
        )
        XCTAssertEqual(
            landscapeRight.degreeX,
            30,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            landscapeRight.degreeY,
            -60,
            accuracy: 0.0001
        )
    }

    func testDegreesRejectsUnsupportedOrientationsAndThresholds() {
        XCTAssertNil(
            IRSensorMotionSession.degrees(
                inversePitchRadians: 0,
                inverseRollRadians: 0,
                pitchDegrees: 14.9,
                rollDegrees: 0,
                orientation: .portrait
            )
        )
        XCTAssertNil(
            IRSensorMotionSession.degrees(
                inversePitchRadians: 0,
                inverseRollRadians: 0,
                pitchDegrees: -14.9,
                rollDegrees: 0,
                orientation: .portraitUpsideDown
            )
        )
        XCTAssertNil(
            IRSensorMotionSession.degrees(
                inversePitchRadians: 0,
                inverseRollRadians: 0,
                pitchDegrees: 0,
                rollDegrees: 14.9,
                orientation: .landscapeLeft
            )
        )
        XCTAssertNil(
            IRSensorMotionSession.degrees(
                inversePitchRadians: 0,
                inverseRollRadians: 0,
                pitchDegrees: 0,
                rollDegrees: -14.9,
                orientation: .landscapeRight
            )
        )
        XCTAssertNil(
            IRSensorMotionSession.degrees(
                inversePitchRadians: 0,
                inverseRollRadians: 0,
                pitchDegrees: 0,
                rollDegrees: 0,
                orientation: .unknown
            )
        )
        XCTAssertNil(
            IRSensorMotionSession.degrees(
                inversePitchRadians: .nan,
                inverseRollRadians: 0,
                pitchDegrees: 20,
                rollDegrees: 0,
                orientation: .portrait
            )
        )
    }

    func testPreparedGenerationMustActivateExactly() {
        let session = IRSensorMotionSession(
            orientation: .portrait
        )
        let generation = session.prepareRestart(
            orientation: nil
        )

        XCTAssertEqual(generation, 1)
        XCTAssertFalse(session.activate(generation: 2))
        XCTAssertTrue(session.activate(generation: 1))
        XCTAssertEqual(session.snapshot.phase, .active)
        XCTAssertEqual(session.snapshot.generation, 1)
    }

    func testFirstSampleCapturesReferenceBeforeShift() throws {
        let session = try activeSession()

        XCTAssertNil(
            session.process(
                Self.sample(),
                generation: 1
            )
        )
        XCTAssertTrue(
            session.snapshot.hasReferenceQuaternion
        )

        let shift = try XCTUnwrap(
            session.process(
                Self.sample(rotationXDegrees: 15),
                generation: 1
            )
        )
        XCTAssertEqual(shift.generation, 1)
        XCTAssertEqual(
            shift.expectedOrientation,
            .portrait
        )
        XCTAssertEqual(shift.degreeX, 0, accuracy: 0.0001)
        XCTAssertEqual(
            shift.degreeY,
            -15,
            accuracy: 0.0001
        )
    }

    func testWrongGenerationCannotMutateTracking() throws {
        let session = try activeSession()

        XCTAssertNil(
            session.process(
                Self.sample(),
                generation: 2
            )
        )
        XCTAssertFalse(
            session.snapshot.hasReferenceQuaternion
        )
    }

    func testDeactivateOnlyMatchesActiveGeneration() throws {
        let session = try activeSession()

        session.deactivate(generation: 2)
        XCTAssertEqual(session.snapshot.phase, .active)

        session.deactivate(generation: 1)
        XCTAssertEqual(session.snapshot.phase, .idle)
    }

    func testStopRevokesActiveGenerationAndIsRepeatable()
        throws
    {
        let session = try activeSession()

        session.stop()
        let generation = session.snapshot.generation
        session.stop()

        XCTAssertEqual(session.snapshot.phase, .idle)
        XCTAssertEqual(generation, 2)
        XCTAssertEqual(
            session.snapshot.generation,
            generation
        )
    }

    func testDeliveryAdmissionRebaselinesOrientation()
        throws
    {
        let session = try activeSession()
        _ = session.process(
            Self.sample(),
            generation: 1
        )
        let shift = try XCTUnwrap(
            session.process(
                Self.sample(rotationXDegrees: 10),
                generation: 1
            )
        )

        XCTAssertFalse(
            session.admitsDelivery(
                generation: shift.generation,
                expectedOrientation:
                    shift.expectedOrientation,
                currentOrientation: .landscapeLeft
            )
        )
        XCTAssertEqual(
            session.snapshot.orientation,
            .landscapeLeft
        )
        XCTAssertFalse(
            session.snapshot.hasReferenceQuaternion
        )
    }

    func testConcurrentProcessRestartStopAndSnapshot()
        throws
    {
        let session = try activeSession()

        DispatchQueue.concurrentPerform(iterations: 400) {
            index in
            switch index % 5 {
            case 0:
                _ = session.process(
                    Self.sample(
                        rotationXDegrees:
                            Double(index % 30)
                    ),
                    generation:
                        session.snapshot.generation
                )
            case 1:
                if let generation = session.prepareRestart(
                    orientation:
                        index % 10 == 1
                            ? .portrait
                            : .landscapeLeft
                ) {
                    _ = session.activate(
                        generation: generation
                    )
                }
            case 2:
                session.stop()
            case 3:
                session.updateOrientation(
                    index % 10 == 3
                        ? .portrait
                        : .landscapeRight
                )
            default:
                _ = session.snapshot
            }
        }

        let snapshot = session.snapshot
        XCTAssertGreaterThan(snapshot.generation, 0)
        XCTAssertTrue(snapshot.previousOffsetX.isFinite)
        XCTAssertTrue(snapshot.previousOffsetY.isFinite)
        if snapshot.phase == .idle {
            XCTAssertFalse(snapshot.hasReferenceQuaternion)
            XCTAssertEqual(snapshot.previousOffsetX, 0)
            XCTAssertEqual(snapshot.previousOffsetY, 0)
        }
    }

    private func activeSession()
        throws -> IRSensorMotionSession
    {
        let session = IRSensorMotionSession(
            orientation: .portrait
        )
        let generation = try XCTUnwrap(
            session.prepareRestart(orientation: nil)
        )
        XCTAssertTrue(
            session.activate(generation: generation)
        )
        return session
    }

    private static func sample(
        rotationXDegrees: Double = 0
    ) -> IRSensorMotionSample {
        let radians =
            rotationXDegrees * Double.pi / 180.0
        return IRSensorMotionSample(
            quaternion: IRSensorQuaternion(
                x: sin(radians / 2),
                y: 0,
                z: 0,
                w: cos(radians / 2)
            ),
            pitchDegrees: 20,
            rollDegrees: 0
        )
    }
}
