//
//  IRSensorMotionDriver.swift
//  IRPlayer-swift
//
//  Created by Codex on 2026/7/24.
//

import CoreMotion
import Foundation

struct IRSensorQuaternion: Equatable, Sendable {
    let x: Double
    let y: Double
    let z: Double
    let w: Double

    init(
        x: Double,
        y: Double,
        z: Double,
        w: Double
    ) {
        self.x = x
        self.y = y
        self.z = z
        self.w = w
    }

    init(_ quaternion: CMQuaternion) {
        self.init(
            x: quaternion.x,
            y: quaternion.y,
            z: quaternion.z,
            w: quaternion.w
        )
    }

    var isFinite: Bool {
        x.isFinite
            && y.isFinite
            && z.isFinite
            && w.isFinite
    }

    func normalized() -> IRSensorQuaternion? {
        guard isFinite else {
            return nil
        }
        let normSquared =
            x * x
            + y * y
            + z * z
            + w * w
        guard normSquared.isFinite,
              normSquared > .leastNonzeroMagnitude else {
            return nil
        }
        let norm = sqrt(normSquared)
        guard norm.isFinite, norm > 0 else {
            return nil
        }
        return IRSensorQuaternion(
            x: x / norm,
            y: y / norm,
            z: z / norm,
            w: w / norm
        )
    }

    func relative(
        to reference: IRSensorQuaternion
    ) -> IRSensorQuaternion? {
        guard let current = normalized(),
              let reference = reference.normalized() else {
            return nil
        }
        let inverseReference = IRSensorQuaternion(
            x: -reference.x,
            y: -reference.y,
            z: -reference.z,
            w: reference.w
        )
        return current
            .multiplied(by: inverseReference)
            .normalized()
    }

    private func multiplied(
        by other: IRSensorQuaternion
    ) -> IRSensorQuaternion {
        IRSensorQuaternion(
            x: w * other.x
                + x * other.w
                + y * other.z
                - z * other.y,
            y: w * other.y
                - x * other.z
                + y * other.w
                + z * other.x,
            z: w * other.z
                + x * other.y
                - y * other.x
                + z * other.w,
            w: w * other.w
                - x * other.x
                - y * other.y
                - z * other.z
        )
    }
}

struct IRSensorMotionSample: Equatable, Sendable {
    let quaternion: IRSensorQuaternion
    let pitchDegrees: Double
    let rollDegrees: Double

    var isFinite: Bool {
        quaternion.isFinite
            && pitchDegrees.isFinite
            && rollDegrees.isFinite
    }
}

protocol IRSensorMotionDriving: AnyObject {
    var isDeviceMotionAvailable: Bool { get }

    @discardableResult
    func startDeviceMotionUpdates(
        to queue: OperationQueue,
        handler: @escaping (IRSensorMotionSample) -> Void
    ) -> Bool

    func stopDeviceMotionUpdates()
}

final class IRSystemSensorMotionDriver:
    IRSensorMotionDriving
{
    private let manager: CMMotionManager

    init(
        manager: CMMotionManager = CMMotionManager(),
        updateInterval: TimeInterval = 1.0 / 60.0
    ) {
        self.manager = manager
        if updateInterval.isFinite, updateInterval > 0 {
            manager.deviceMotionUpdateInterval = updateInterval
        }
    }

    var isDeviceMotionAvailable: Bool {
        manager.isDeviceMotionAvailable
    }

    @discardableResult
    func startDeviceMotionUpdates(
        to queue: OperationQueue,
        handler: @escaping (IRSensorMotionSample) -> Void
    ) -> Bool {
        guard manager.isDeviceMotionAvailable else {
            return false
        }
        manager.startDeviceMotionUpdates(to: queue) {
            motion,
            _ in
            guard let attitude = motion?.attitude else {
                return
            }
            let radiansToDegrees = 180.0 / Double.pi
            handler(
                IRSensorMotionSample(
                    quaternion:
                        IRSensorQuaternion(
                            attitude.quaternion
                        ),
                    pitchDegrees:
                        attitude.pitch * radiansToDegrees,
                    rollDegrees:
                        attitude.roll * radiansToDegrees
                )
            )
        }
        return true
    }

    func stopDeviceMotionUpdates() {
        manager.stopDeviceMotionUpdates()
    }
}
