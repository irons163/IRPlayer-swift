//
//  IRSensorTests.swift
//  IRPlayer-swiftTests
//
//  Created by Codex on 2026/6/2.
//

import CoreGraphics
import Foundation
import XCTest
import UIKit
@testable import IRPlayer_swift

final class IRSensorTests: XCTestCase {
    func testResetPublishesActiveGenerationAndOwnedQueue() {
        let fixture = SensorFixture()

        XCTAssertTrue(fixture.sensor.resetUnit())

        let diagnostics = fixture.sensor.diagnostics
        XCTAssertEqual(diagnostics.phase, .active)
        XCTAssertEqual(diagnostics.generation, 1)
        XCTAssertFalse(diagnostics.hasReferenceQuaternion)
        XCTAssertEqual(
            fixture.driver.operations,
            [.stop, .start]
        )
        XCTAssertEqual(
            fixture.driver.startedQueues.first?
                .maxConcurrentOperationCount,
            1
        )
        XCTAssertEqual(
            fixture.driver.startedQueues.first?.name,
            "test.irplayer.sensor.motion"
        )
    }

    func testResetRejectsUnavailableDriver() {
        let fixture = SensorFixture(isAvailable: false)

        XCTAssertFalse(fixture.sensor.resetUnit())

        XCTAssertEqual(fixture.sensor.diagnostics.phase, .idle)
        XCTAssertEqual(fixture.sensor.diagnostics.generation, 1)
        XCTAssertEqual(fixture.driver.startCount, 0)
        XCTAssertEqual(fixture.driver.stopCount, 1)
    }

    func testResetFailureReturnsSessionToIdle() {
        let fixture = SensorFixture(shouldStart: false)

        XCTAssertFalse(fixture.sensor.resetUnit())

        XCTAssertEqual(fixture.sensor.diagnostics.phase, .idle)
        XCTAssertEqual(fixture.driver.startCount, 1)
        XCTAssertEqual(fixture.driver.stopCount, 2)
    }

    func testFirstSampleCapturesReferenceAndRelativeSampleScrolls()
        throws
    {
        let fixture = SensorFixture()
        XCTAssertTrue(fixture.sensor.resetUnit())

        fixture.driver.emitLatest(Self.sample())

        XCTAssertTrue(
            fixture.sensor.diagnostics
                .hasReferenceQuaternion
        )
        XCTAssertTrue(fixture.shifts.values.isEmpty)

        fixture.driver.emitLatest(
            Self.sample(rotationXDegrees: 10)
        )

        let shift = try XCTUnwrap(
            fixture.shifts.values.first
        )
        XCTAssertEqual(shift.degreeX, 0, accuracy: 0.0001)
        XCTAssertEqual(
            shift.degreeY,
            -10,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            fixture.sensor.diagnostics.previousOffsetY,
            -10,
            accuracy: 0.0001
        )
    }

    func testInvalidSampleClearsTrackingAndRequiresNewReference() {
        let fixture = SensorFixture()
        XCTAssertTrue(fixture.sensor.resetUnit())
        fixture.driver.emitLatest(Self.sample())

        fixture.driver.emitLatest(
            IRSensorMotionSample(
                quaternion: IRSensorQuaternion(
                    x: 0,
                    y: 0,
                    z: 0,
                    w: 0
                ),
                pitchDegrees: 20,
                rollDegrees: 0
            )
        )

        XCTAssertFalse(
            fixture.sensor.diagnostics
                .hasReferenceQuaternion
        )
        fixture.driver.emitLatest(
            Self.sample(rotationXDegrees: 10)
        )
        XCTAssertTrue(
            fixture.sensor.diagnostics
                .hasReferenceQuaternion
        )
        XCTAssertTrue(fixture.shifts.values.isEmpty)
    }

    func testOrientationIneligibleSampleCannotBecomeReference() {
        let fixture = SensorFixture()
        XCTAssertTrue(fixture.sensor.resetUnit())

        fixture.driver.emitLatest(
            Self.sample(pitchDegrees: 14.9)
        )

        XCTAssertFalse(
            fixture.sensor.diagnostics
                .hasReferenceQuaternion
        )
        fixture.driver.emitLatest(Self.sample())
        XCTAssertTrue(
            fixture.sensor.diagnostics
                .hasReferenceQuaternion
        )
        XCTAssertTrue(fixture.shifts.values.isEmpty)
    }

    func testRestartRejectsOlderCapturedHandler() {
        let fixture = SensorFixture()
        XCTAssertTrue(fixture.sensor.resetUnit())
        fixture.driver.emit(
            Self.sample(),
            handlerAt: 0
        )

        XCTAssertTrue(fixture.sensor.resetUnit())
        fixture.driver.emit(
            Self.sample(rotationXDegrees: 10),
            handlerAt: 0
        )
        XCTAssertTrue(fixture.shifts.values.isEmpty)

        fixture.driver.emit(
            Self.sample(),
            handlerAt: 1
        )
        fixture.driver.emit(
            Self.sample(rotationXDegrees: 10),
            handlerAt: 1
        )
        XCTAssertEqual(fixture.shifts.values.count, 1)
        XCTAssertEqual(
            fixture.sensor.diagnostics.generation,
            2
        )
    }

    func testStopRejectsCallbackAndQueuedMainDelivery() {
        let fixture = SensorFixture(queuesDeliveries: true)
        XCTAssertTrue(fixture.sensor.resetUnit())
        fixture.driver.emitLatest(Self.sample())
        fixture.driver.emitLatest(
            Self.sample(rotationXDegrees: 10)
        )
        XCTAssertEqual(fixture.delivery.pendingCount, 1)

        fixture.sensor.stopMotionDetection()
        fixture.driver.emitLatest(
            Self.sample(rotationXDegrees: 20)
        )
        fixture.delivery.drain()

        XCTAssertEqual(fixture.sensor.diagnostics.phase, .idle)
        XCTAssertTrue(fixture.shifts.values.isEmpty)
    }

    func testRestartRejectsQueuedDeliveryFromPreviousGeneration() {
        let fixture = SensorFixture(queuesDeliveries: true)
        XCTAssertTrue(fixture.sensor.resetUnit())
        fixture.driver.emitLatest(Self.sample())
        fixture.driver.emitLatest(
            Self.sample(rotationXDegrees: 10)
        )
        XCTAssertEqual(fixture.delivery.pendingCount, 1)

        XCTAssertTrue(fixture.sensor.resetUnit())
        fixture.delivery.drain()
        XCTAssertTrue(fixture.shifts.values.isEmpty)

        fixture.driver.emitLatest(Self.sample())
        fixture.driver.emitLatest(
            Self.sample(rotationXDegrees: 10)
        )
        fixture.delivery.drain()
        XCTAssertEqual(fixture.shifts.values.count, 1)
    }

    func testStopIsRepeatableAndRevokesGenerationOnce() {
        let fixture = SensorFixture()
        XCTAssertTrue(fixture.sensor.resetUnit())
        XCTAssertEqual(fixture.sensor.diagnostics.generation, 1)

        fixture.sensor.stopMotionDetection()
        let stoppedGeneration =
            fixture.sensor.diagnostics.generation
        fixture.sensor.stopMotionDetection()

        XCTAssertEqual(stoppedGeneration, 2)
        XCTAssertEqual(
            fixture.sensor.diagnostics.generation,
            stoppedGeneration
        )
        XCTAssertEqual(fixture.sensor.diagnostics.phase, .idle)
    }

    func testOrientationChangeDropsShiftAndRebaselines() {
        let fixture = SensorFixture()
        XCTAssertTrue(fixture.sensor.resetUnit())
        fixture.driver.emitLatest(Self.sample())

        fixture.orientation.value = .landscapeLeft
        fixture.driver.emitLatest(
            Self.sample(rotationXDegrees: 10)
        )

        XCTAssertTrue(fixture.shifts.values.isEmpty)
        XCTAssertEqual(
            fixture.sensor.diagnostics.orientation,
            .landscapeLeft
        )
        XCTAssertFalse(
            fixture.sensor.diagnostics
                .hasReferenceQuaternion
        )

        fixture.driver.emitLatest(
            Self.sample(
                rollDegrees: 20
            )
        )
        fixture.driver.emitLatest(
            Self.sample(
                rotationYDegrees: 10,
                rollDegrees: 20
            )
        )

        XCTAssertEqual(fixture.shifts.values.count, 1)
        XCTAssertEqual(
            fixture.shifts.values[0].degreeY,
            -10,
            accuracy: 0.0001
        )
    }

    func testWeakTargetsAreSynchronizedAndDiagnosed() {
        let fixture = SensorFixture()

        XCTAssertTrue(
            fixture.sensor.targetView === fixture.view
        )
        XCTAssertTrue(
            fixture.sensor.smoothScroll === fixture.scroll
        )
        XCTAssertTrue(
            fixture.sensor.diagnostics.hasTargetView
        )
        XCTAssertTrue(
            fixture.sensor.diagnostics.hasSmoothScroll
        )

        fixture.sensor.targetView = nil
        fixture.sensor.smoothScroll = nil

        XCTAssertFalse(
            fixture.sensor.diagnostics.hasTargetView
        )
        XCTAssertFalse(
            fixture.sensor.diagnostics.hasSmoothScroll
        )
    }

    func testDriverCallbackDoesNotRetainReleasedSensor() {
        let driver = SensorMotionDriverProbe()
        let orientation = SensorOrientationProbe(.portrait)
        let delivery = SensorDeliveryProbe()
        let shifts = SensorShiftRecorder()
        weak var weakSensor: IRSensor?

        autoreleasepool {
            var sensor: IRSensor? = IRSensor(
                dependencies: Self.dependencies(
                    driver: driver,
                    orientation: orientation,
                    delivery: delivery,
                    shifts: shifts
                )
            )
            weakSensor = sensor
            XCTAssertTrue(sensor?.resetUnit() == true)
            sensor = nil
        }

        XCTAssertNil(weakSensor)
        XCTAssertGreaterThanOrEqual(driver.stopCount, 2)
        driver.emit(
            Self.sample(),
            handlerAt: 0
        )
        XCTAssertTrue(shifts.values.isEmpty)
    }

    func testConcurrentLifecycleSamplesAndTargetsRemainCoherent() {
        let fixture = SensorFixture(queuesDeliveries: true)
        XCTAssertTrue(fixture.sensor.resetUnit())

        DispatchQueue.concurrentPerform(iterations: 400) {
            index in
            switch index % 8 {
            case 0:
                _ = fixture.sensor.resetUnit()
            case 1:
                fixture.sensor.stopMotionDetection()
            case 2:
                fixture.sensor.updateDeviceOrientation(
                    orientation:
                        index % 16 == 2
                            ? .portrait
                            : .landscapeLeft
                )
            case 3:
                _ = fixture.sensor.diagnostics
            case 4:
                fixture.driver.emitLatest(
                    Self.sample(
                        rotationXDegrees:
                            Double(index % 30)
                    )
                )
            case 5:
                fixture.sensor.targetView =
                    index % 16 == 5
                        ? fixture.view
                        : nil
            case 6:
                fixture.sensor.smoothScroll =
                    index % 16 == 6
                        ? fixture.scroll
                        : nil
            default:
                _ = fixture.sensor.targetView
                _ = fixture.sensor.smoothScroll
            }
        }
        fixture.sensor.stopMotionDetection()
        fixture.delivery.drain()

        XCTAssertEqual(fixture.sensor.diagnostics.phase, .idle)
        XCTAssertGreaterThan(fixture.driver.stopCount, 0)
    }

    private static func sample(
        rotationXDegrees: Double = 0,
        rotationYDegrees: Double = 0,
        pitchDegrees: Double = 20,
        rollDegrees: Double = 0
    ) -> IRSensorMotionSample {
        let xRadians =
            rotationXDegrees * Double.pi / 180.0
        let yRadians =
            rotationYDegrees * Double.pi / 180.0
        let xQuaternion = IRSensorQuaternion(
            x: sin(xRadians / 2),
            y: 0,
            z: 0,
            w: cos(xRadians / 2)
        )
        let yQuaternion = IRSensorQuaternion(
            x: 0,
            y: sin(yRadians / 2),
            z: 0,
            w: cos(yRadians / 2)
        )
        let quaternion: IRSensorQuaternion
        if rotationYDegrees == 0 {
            quaternion = xQuaternion
        } else if rotationXDegrees == 0 {
            quaternion = yQuaternion
        } else {
            fatalError(
                "Test samples support one rotation axis"
            )
        }
        return IRSensorMotionSample(
            quaternion: quaternion,
            pitchDegrees: pitchDegrees,
            rollDegrees: rollDegrees
        )
    }

    fileprivate static func dependencies(
        driver: SensorMotionDriverProbe,
        orientation: SensorOrientationProbe,
        delivery: SensorDeliveryProbe,
        shifts: SensorShiftRecorder,
        queuesDeliveries: Bool = false
    ) -> IRSensorDependencies {
        let callbackQueue = OperationQueue()
        callbackQueue.name = "test.irplayer.sensor.motion"
        callbackQueue.maxConcurrentOperationCount = 1
        return IRSensorDependencies(
            motionDriver: driver,
            callbackQueue: callbackQueue,
            currentOrientation: {
                orientation.value
            },
            deliverOnMain: {
                work in
                if queuesDeliveries {
                    delivery.enqueue(work)
                } else {
                    work()
                }
            },
            applyShift: {
                _,
                degreeX,
                degreeY in
                shifts.append(
                    SensorShift(
                        degreeX: degreeX,
                        degreeY: degreeY
                    )
                )
            }
        )
    }
}

private final class SensorFixture {
    let driver: SensorMotionDriverProbe
    let orientation: SensorOrientationProbe
    let delivery: SensorDeliveryProbe
    let shifts: SensorShiftRecorder
    let view: IRGLView
    let scroll: IRSmoothScrollController
    let sensor: IRSensor

    init(
        isAvailable: Bool = true,
        shouldStart: Bool = true,
        queuesDeliveries: Bool = false
    ) {
        let driver = SensorMotionDriverProbe(
            isAvailable: isAvailable,
            shouldStart: shouldStart
        )
        let orientation =
            SensorOrientationProbe(.portrait)
        let delivery = SensorDeliveryProbe()
        let shifts = SensorShiftRecorder()
        let view = IRGLView(frame: .zero)
        let scroll =
            IRSmoothScrollController(targetView: view)
        let sensor = IRSensor(
            dependencies: IRSensorTests.dependencies(
                driver: driver,
                orientation: orientation,
                delivery: delivery,
                shifts: shifts,
                queuesDeliveries: queuesDeliveries
            )
        )
        sensor.targetView = view
        sensor.smoothScroll = scroll

        self.driver = driver
        self.orientation = orientation
        self.delivery = delivery
        self.shifts = shifts
        self.view = view
        self.scroll = scroll
        self.sensor = sensor
    }
}

private final class SensorMotionDriverProbe:
    IRSensorMotionDriving,
    @unchecked Sendable
{
    enum Operation: Equatable {
        case start
        case stop
    }

    private let lock = NSLock()
    private var storedIsAvailable: Bool
    private var storedShouldStart: Bool
    private var handlers:
        [(IRSensorMotionSample) -> Void] = []
    private var queues: [OperationQueue] = []
    private var operationLog: [Operation] = []
    private var starts = 0
    private var stops = 0

    init(
        isAvailable: Bool = true,
        shouldStart: Bool = true
    ) {
        storedIsAvailable = isAvailable
        storedShouldStart = shouldStart
    }

    var isDeviceMotionAvailable: Bool {
        lock.lock()
        defer { lock.unlock() }
        return storedIsAvailable
    }

    var startCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return starts
    }

    var stopCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return stops
    }

    var operations: [Operation] {
        lock.lock()
        defer { lock.unlock() }
        return operationLog
    }

    var startedQueues: [OperationQueue] {
        lock.lock()
        defer { lock.unlock() }
        return queues
    }

    @discardableResult
    func startDeviceMotionUpdates(
        to queue: OperationQueue,
        handler: @escaping (IRSensorMotionSample) -> Void
    ) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        starts += 1
        operationLog.append(.start)
        queues.append(queue)
        guard storedShouldStart else {
            return false
        }
        handlers.append(handler)
        return true
    }

    func stopDeviceMotionUpdates() {
        lock.lock()
        stops += 1
        operationLog.append(.stop)
        lock.unlock()
    }

    func emitLatest(_ sample: IRSensorMotionSample) {
        let handler: ((IRSensorMotionSample) -> Void)?
        lock.lock()
        handler = handlers.last
        lock.unlock()
        handler?(sample)
    }

    func emit(
        _ sample: IRSensorMotionSample,
        handlerAt index: Int
    ) {
        let handler: ((IRSensorMotionSample) -> Void)?
        lock.lock()
        handler = handlers.indices.contains(index)
            ? handlers[index]
            : nil
        lock.unlock()
        handler?(sample)
    }
}

private final class SensorOrientationProbe:
    @unchecked Sendable
{
    private let lock = NSLock()
    private var storedValue: UIInterfaceOrientation

    init(_ value: UIInterfaceOrientation) {
        storedValue = value
    }

    var value: UIInterfaceOrientation {
        get {
            lock.lock()
            defer { lock.unlock() }
            return storedValue
        }
        set {
            lock.lock()
            storedValue = newValue
            lock.unlock()
        }
    }
}

private final class SensorDeliveryProbe:
    @unchecked Sendable
{
    private let lock = NSLock()
    private var pending: [() -> Void] = []

    var pendingCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return pending.count
    }

    func enqueue(_ work: @escaping () -> Void) {
        lock.lock()
        pending.append(work)
        lock.unlock()
    }

    func drain() {
        let work: [() -> Void]
        lock.lock()
        work = pending
        pending.removeAll()
        lock.unlock()
        work.forEach { $0() }
    }
}

private struct SensorShift: Equatable {
    let degreeX: Float
    let degreeY: Float
}

private final class SensorShiftRecorder:
    @unchecked Sendable
{
    private let lock = NSLock()
    private var storedValues: [SensorShift] = []

    var values: [SensorShift] {
        lock.lock()
        defer { lock.unlock() }
        return storedValues
    }

    func append(_ shift: SensorShift) {
        lock.lock()
        storedValues.append(shift)
        lock.unlock()
    }
}
