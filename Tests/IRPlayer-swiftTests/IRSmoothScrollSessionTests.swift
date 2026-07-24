import UIKit
import XCTest
#if SWIFT_PACKAGE
@testable import IRPlayerSwift
#else
@testable import IRPlayer_swift
#endif

final class IRSmoothScrollSessionTests: XCTestCase {
    func testVelocityTargetPreservesExistingCurve() {
        let target =
            IRSmoothScrollSession.smoothScrollTarget(
                for: CGPoint(x: 300, y: 400)
            )

        XCTAssertEqual(
            target.point.x,
            37.5,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            target.point.y,
            50,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            target.duration,
            0.25,
            accuracy: 0.0001
        )
    }

    func testVelocityTargetRejectsZeroNonFiniteAndOverflow() {
        XCTAssertEqual(
            IRSmoothScrollSession.smoothScrollTarget(
                for: .zero
            ).point,
            .zero
        )
        XCTAssertEqual(
            IRSmoothScrollSession.smoothScrollTarget(
                for: CGPoint(x: CGFloat.nan, y: 1)
            ).point,
            .zero
        )
        XCTAssertEqual(
            IRSmoothScrollSession.smoothScrollTarget(
                for: CGPoint(
                    x: CGFloat.greatestFiniteMagnitude,
                    y: CGFloat.greatestFiniteMagnitude
                )
            ).point,
            .zero
        )
    }

    func testStepCalculatesEaseOutMovement() throws {
        let step = try XCTUnwrap(
            IRSmoothScrollSession.step(
                finalPoint: CGPoint(x: 100, y: 50),
                alreadyPoint: CGPoint(x: 20, y: 5),
                elapsed: 0.25,
                duration: 1
            )
        )

        XCTAssertEqual(
            step.move.x,
            23.75,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            step.move.y,
            16.875,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            step.alreadyPoint,
            CGPoint(x: 43.75, y: 21.875)
        )
        XCTAssertFalse(step.isFinished)
    }

    func testStepClampsAndFinishesByElapsedTime()
        throws
    {
        let step = try XCTUnwrap(
            IRSmoothScrollSession.step(
                finalPoint: CGPoint(x: 100, y: 50),
                alreadyPoint:
                    CGPoint(x: 43.75, y: 21.875),
                elapsed: 2,
                duration: 1
            )
        )

        XCTAssertEqual(
            step.alreadyPoint,
            CGPoint(x: 100, y: 50)
        )
        XCTAssertTrue(step.isFinished)
    }

    func testStepRejectsInvalidGeometryAndTiming() {
        XCTAssertNil(
            IRSmoothScrollSession.step(
                finalPoint: CGPoint(x: 10, y: 10),
                alreadyPoint: .zero,
                elapsed: 0.1,
                duration: 0
            )
        )
        XCTAssertNil(
            IRSmoothScrollSession.step(
                finalPoint: CGPoint(
                    x: CGFloat.nan,
                    y: 10
                ),
                alreadyPoint: .zero,
                elapsed: 0.1,
                duration: 1
            )
        )
    }

    func testVelocityStartPublishesCoherentActiveGeneration() {
        let session = IRSmoothScrollSession()
        session.setPaned(true)

        XCTAssertTrue(
            session.start(
                velocity: CGPoint(x: 300, y: 400)
            )
        )

        let snapshot = session.snapshot
        XCTAssertEqual(snapshot.phase, .active)
        XCTAssertEqual(snapshot.generation, 1)
        XCTAssertEqual(
            snapshot.finalPoint,
            CGPoint(x: 37.5, y: 50)
        )
        XCTAssertTrue(snapshot.isPaned)
        XCTAssertNil(snapshot.startTimestamp)
    }

    func testAdvanceCapturesStartAndCompletesAtomically()
        throws
    {
        let session = IRSmoothScrollSession()
        XCTAssertTrue(
            session.start(
                velocity: CGPoint(x: 300, y: 400)
            )
        )

        let first = try XCTUnwrap(
            session.advance(timestamp: 10)
        )
        XCTAssertEqual(first.move, .zero)
        XCTAssertFalse(first.isFinished)
        XCTAssertEqual(
            session.snapshot.startTimestamp,
            10
        )

        let final = try XCTUnwrap(
            session.advance(timestamp: 10.25)
        )
        XCTAssertEqual(
            final.move,
            CGPoint(x: 37.5, y: 50)
        )
        XCTAssertTrue(final.isFinished)
        XCTAssertEqual(session.snapshot.phase, .idle)
    }

    func testInvalidTimestampRevokesAnimation() {
        let session = IRSmoothScrollSession()
        XCTAssertTrue(
            session.start(
                velocity: CGPoint(x: 300, y: 400)
            )
        )

        XCTAssertNil(session.advance(timestamp: .nan))
        XCTAssertEqual(session.snapshot.phase, .idle)
        XCTAssertEqual(session.snapshot.generation, 2)
    }

    func testResetIsRepeatableAndRevokesOnce() {
        let session = IRSmoothScrollSession()
        XCTAssertTrue(
            session.start(
                velocity: CGPoint(x: 300, y: 400)
            )
        )

        XCTAssertTrue(session.reset())
        let generation = session.snapshot.generation
        XCTAssertFalse(session.reset())

        XCTAssertEqual(generation, 2)
        XCTAssertEqual(
            session.snapshot.generation,
            generation
        )
        XCTAssertEqual(session.snapshot.phase, .idle)
    }

    func testInvalidStartRevokesPreviousAnimation() {
        let session = IRSmoothScrollSession()
        XCTAssertTrue(
            session.start(
                velocity: CGPoint(x: 300, y: 400)
            )
        )

        XCTAssertFalse(session.start(velocity: .zero))

        XCTAssertEqual(session.snapshot.phase, .idle)
        XCTAssertEqual(session.snapshot.generation, 2)
    }

    func testDegreeShiftComposesRemainingMovement() {
        let session = IRSmoothScrollSession()
        session.setPaned(true)
        XCTAssertTrue(
            session.start(
                velocity: CGPoint(x: 300, y: 400)
            )
        )

        XCTAssertTrue(
            session.startDegreeShift(
                degreeX: 10,
                degreeY: 5
            )
        )

        let snapshot = session.snapshot
        XCTAssertEqual(
            snapshot.finalPoint,
            CGPoint(x: 47.5, y: 45)
        )
        XCTAssertEqual(
            snapshot.duration,
            0.5,
            accuracy: 0.0001
        )
        XCTAssertFalse(snapshot.isPaned)
        XCTAssertEqual(snapshot.generation, 2)
    }

    func testBoundsAdmissionMasksAxesAndIsOneShot() {
        let session = IRSmoothScrollSession()
        XCTAssertTrue(
            session.startDegreeShift(
                degreeX: 30,
                degreeY: 40
            )
        )

        let horizontal =
            session.admitBounds(.horizontal)
        XCTAssertEqual(horizontal.horizontal?.amount, 30)
        XCTAssertEqual(
            horizontal.horizontal?.direction,
            .right
        )
        XCTAssertNil(horizontal.vertical)

        let secondHorizontal =
            session.admitBounds(.horizontal)
        XCTAssertNil(secondHorizontal.horizontal)

        let vertical = session.admitBounds(.vertical)
        XCTAssertNil(vertical.horizontal)
        XCTAssertEqual(vertical.vertical?.amount, -40)
        XCTAssertEqual(vertical.vertical?.direction, .up)
    }

    func testBoundsAdmissionIgnoresIdleAndMissingBounds() {
        let session = IRSmoothScrollSession()
        XCTAssertNil(
            session.admitBounds(.both).horizontal
        )
        XCTAssertNil(
            session.admitBounds(.both).vertical
        )
        XCTAssertTrue(
            session.startDegreeShift(
                degreeX: 30,
                degreeY: 40
            )
        )

        let requests = session.admitBounds(.none)

        XCTAssertNil(requests.horizontal)
        XCTAssertNil(requests.vertical)
    }

    func testConcurrentLifecycleAndSnapshotsRemainCoherent() {
        let session = IRSmoothScrollSession()

        DispatchQueue.concurrentPerform(iterations: 600) {
            index in
            switch index % 7 {
            case 0:
                _ = session.start(
                    velocity: CGPoint(
                        x: CGFloat(index),
                        y: CGFloat(index + 1)
                    )
                )
            case 1:
                _ = session.startDegreeShift(
                    degreeX: Float(index % 30),
                    degreeY: Float(index % 20)
                )
            case 2:
                _ = session.advance(
                    timestamp: TimeInterval(index) / 60
                )
            case 3:
                _ = session.reset()
            case 4:
                session.setPaned(index.isMultiple(of: 2))
            case 5:
                _ = session.admitBounds(.both)
            default:
                _ = session.snapshot
            }
        }

        let snapshot = session.snapshot
        XCTAssertGreaterThan(snapshot.generation, 0)
        XCTAssertTrue(snapshot.finalPoint.x.isFinite)
        XCTAssertTrue(snapshot.finalPoint.y.isFinite)
        XCTAssertTrue(snapshot.alreadyPoint.x.isFinite)
        XCTAssertTrue(snapshot.alreadyPoint.y.isFinite)
        if snapshot.phase == .idle {
            XCTAssertEqual(snapshot.finalPoint, .zero)
            XCTAssertEqual(snapshot.alreadyPoint, .zero)
            XCTAssertEqual(snapshot.duration, 0)
        }
    }
}
