//
//  IRSensorMotionSession.swift
//  IRPlayer-swift
//
//  Created by Codex on 2026/7/24.
//

import CoreGraphics
import Foundation
import UIKit

enum IRSensorMotionPhase: Equatable {
    case idle
    case active
}

struct IRSensorMotionSnapshot: Equatable {
    let phase: IRSensorMotionPhase
    let generation: UInt64
    let hasReferenceQuaternion: Bool
    let orientation: UIInterfaceOrientation
    let previousOffsetX: CGFloat
    let previousOffsetY: CGFloat
}

struct IRSensorMotionShift: Equatable, Sendable {
    let generation: UInt64
    let expectedOrientation: UIInterfaceOrientation
    let degreeX: Float
    let degreeY: Float
}

final class IRSensorMotionSession:
    @unchecked Sendable
{
    private struct ActiveState {
        let generation: UInt64
        var referenceQuaternion: IRSensorQuaternion?
        var previousOffsetX: CGFloat = 0
        var previousOffsetY: CGFloat = 0

        mutating func resetTracking() {
            referenceQuaternion = nil
            previousOffsetX = 0
            previousOffsetY = 0
        }
    }

    private enum State {
        case idle
        case active(ActiveState)
    }

    private let lock = NSLock()
    private var generation: UInt64 = 0
    private var state: State = .idle
    private var orientation: UIInterfaceOrientation

    init(orientation: UIInterfaceOrientation) {
        self.orientation = orientation
    }

    var snapshot: IRSensorMotionSnapshot {
        lock.lock()
        defer { lock.unlock() }
        switch state {
        case .idle:
            return IRSensorMotionSnapshot(
                phase: .idle,
                generation: generation,
                hasReferenceQuaternion: false,
                orientation: orientation,
                previousOffsetX: 0,
                previousOffsetY: 0
            )
        case .active(let active):
            return IRSensorMotionSnapshot(
                phase: .active,
                generation: active.generation,
                hasReferenceQuaternion:
                    active.referenceQuaternion != nil,
                orientation: orientation,
                previousOffsetX: active.previousOffsetX,
                previousOffsetY: active.previousOffsetY
            )
        }
    }

    func prepareRestart(
        orientation newOrientation:
            UIInterfaceOrientation?
    ) -> UInt64? {
        lock.lock()
        defer { lock.unlock() }
        guard let nextGeneration =
                nextGenerationLocked() else {
            state = .idle
            return nil
        }
        if let newOrientation {
            orientation = newOrientation
        }
        state = .idle
        return nextGeneration
    }

    func activate(generation requestGeneration: UInt64)
        -> Bool
    {
        lock.lock()
        defer { lock.unlock() }
        guard generation == requestGeneration,
              case .idle = state else {
            return false
        }
        state = .active(
            ActiveState(generation: requestGeneration)
        )
        return true
    }

    func deactivate(generation requestGeneration: UInt64) {
        lock.lock()
        defer { lock.unlock() }
        guard case .active(let active) = state,
              active.generation == requestGeneration else {
            return
        }
        state = .idle
    }

    func stop() {
        lock.lock()
        defer { lock.unlock() }
        guard case .active = state else {
            return
        }
        _ = nextGenerationLocked()
        state = .idle
    }

    func updateOrientation(
        _ newOrientation: UIInterfaceOrientation
    ) {
        lock.lock()
        defer { lock.unlock() }
        guard orientation != newOrientation else {
            return
        }
        orientation = newOrientation
        resetActiveTrackingLocked()
    }

    func process(
        _ sample: IRSensorMotionSample,
        generation requestGeneration: UInt64
    ) -> IRSensorMotionShift? {
        lock.lock()
        defer { lock.unlock() }
        guard case .active(var active) = state,
              active.generation == requestGeneration else {
            return nil
        }
        guard sample.isFinite,
              let quaternion =
                sample.quaternion.normalized(),
              Self.orientationIsEligible(
                  pitchDegrees: sample.pitchDegrees,
                  rollDegrees: sample.rollDegrees,
                  orientation: orientation
              ) else {
            active.resetTracking()
            state = .active(active)
            return nil
        }
        guard let referenceQuaternion =
                active.referenceQuaternion else {
            active.referenceQuaternion = quaternion
            state = .active(active)
            return nil
        }
        guard let relativeQuaternion =
                quaternion.relative(
                    to: referenceQuaternion
                ) else {
            active.resetTracking()
            state = .active(active)
            return nil
        }

        let inversePitch = atan2(
            2 * (
                relativeQuaternion.x
                    * relativeQuaternion.w
                + relativeQuaternion.y
                    * relativeQuaternion.z
            ),
            1
                - 2 * relativeQuaternion.x
                    * relativeQuaternion.x
                - 2 * relativeQuaternion.z
                    * relativeQuaternion.z
        )
        let inverseRoll = atan2(
            2 * (
                relativeQuaternion.y
                    * relativeQuaternion.w
                - relativeQuaternion.x
                    * relativeQuaternion.z
            ),
            1
                - 2 * relativeQuaternion.y
                    * relativeQuaternion.y
                - 2 * relativeQuaternion.z
                    * relativeQuaternion.z
        )
        guard let degrees = Self.degrees(
            inversePitchRadians: inversePitch,
            inverseRollRadians: inverseRoll,
            pitchDegrees: sample.pitchDegrees,
            rollDegrees: sample.rollDegrees,
            orientation: orientation
        ) else {
            active.resetTracking()
            state = .active(active)
            return nil
        }

        let nextOffsetX = degrees.degreeX
        let nextOffsetY = -degrees.degreeY
        let dx = Self.normalizedDelta(
            current: nextOffsetX,
            previous: active.previousOffsetX
        )
        let dy =
            nextOffsetY - active.previousOffsetY
        active.previousOffsetX = nextOffsetX
        active.previousOffsetY = nextOffsetY
        state = .active(active)

        guard let shift = Self.scrollShift(
            dx: dx,
            dy: dy
        ) else {
            return nil
        }
        return IRSensorMotionShift(
            generation: requestGeneration,
            expectedOrientation: orientation,
            degreeX: shift.degreeX,
            degreeY: shift.degreeY
        )
    }

    func admitsDelivery(
        generation requestGeneration: UInt64,
        expectedOrientation: UIInterfaceOrientation,
        currentOrientation: UIInterfaceOrientation
    ) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard case .active(var active) = state,
              active.generation == requestGeneration else {
            return false
        }
        guard orientation == currentOrientation else {
            orientation = currentOrientation
            active.resetTracking()
            state = .active(active)
            return false
        }
        return orientation == expectedOrientation
    }

    static func normalizedDelta(
        current: CGFloat,
        previous: CGFloat
    ) -> CGFloat {
        guard current.isFinite, previous.isFinite else {
            return 0
        }
        let delta = current - previous
        guard delta.isFinite else {
            return 0
        }
        if delta < -180 {
            return 360 + delta
        } else if delta > 180 {
            return delta - 360
        }
        return delta
    }

    static func scrollShift(
        dx: CGFloat,
        dy: CGFloat
    ) -> (degreeX: Float, degreeY: Float)? {
        guard dx.isFinite, dy.isFinite else {
            return nil
        }
        let degreeX = Float(dx)
        let degreeY = Float(dy)
        guard degreeX.isFinite, degreeY.isFinite else {
            return nil
        }
        return (degreeX, degreeY)
    }

    static func degrees(
        inversePitchRadians: Double,
        inverseRollRadians: Double,
        pitchDegrees: Double,
        rollDegrees: Double,
        orientation: UIInterfaceOrientation
    ) -> (degreeX: CGFloat, degreeY: CGFloat)? {
        guard inversePitchRadians.isFinite,
              inverseRollRadians.isFinite,
              orientationIsEligible(
                  pitchDegrees: pitchDegrees,
                  rollDegrees: rollDegrees,
                  orientation: orientation
              ) else {
            return nil
        }
        let radiansToDegrees = 180.0 / Double.pi
        switch orientation {
        case .portrait:
            return (
                CGFloat(
                    inverseRollRadians * radiansToDegrees
                ),
                CGFloat(
                    inversePitchRadians * radiansToDegrees
                )
            )
        case .portraitUpsideDown:
            return (
                -CGFloat(
                    inverseRollRadians * radiansToDegrees
                ),
                -CGFloat(
                    inversePitchRadians * radiansToDegrees
                )
            )
        case .landscapeLeft:
            return (
                -CGFloat(
                    inversePitchRadians * radiansToDegrees
                ),
                CGFloat(
                    inverseRollRadians * radiansToDegrees
                )
            )
        case .landscapeRight:
            return (
                CGFloat(
                    inversePitchRadians * radiansToDegrees
                ),
                -CGFloat(
                    inverseRollRadians * radiansToDegrees
                )
            )
        default:
            return nil
        }
    }

    static func orientationIsEligible(
        pitchDegrees: Double,
        rollDegrees: Double,
        orientation: UIInterfaceOrientation
    ) -> Bool {
        guard pitchDegrees.isFinite,
              rollDegrees.isFinite else {
            return false
        }
        switch orientation {
        case .portrait:
            return pitchDegrees >= 15
        case .portraitUpsideDown:
            return pitchDegrees <= -15
        case .landscapeLeft:
            return rollDegrees >= 15
        case .landscapeRight:
            return rollDegrees <= -15
        default:
            return false
        }
    }

    private func resetActiveTrackingLocked() {
        guard case .active(var active) = state else {
            return
        }
        active.resetTracking()
        state = .active(active)
    }

    private func nextGenerationLocked() -> UInt64? {
        let (nextGeneration, overflow) =
            generation.addingReportingOverflow(1)
        guard !overflow else {
            return nil
        }
        generation = nextGeneration
        return nextGeneration
    }
}
