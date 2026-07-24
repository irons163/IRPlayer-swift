//
//  IRSmoothScrollSession.swift
//  IRPlayer-swift
//
//  Created by Codex on 2026/7/24.
//

import Foundation
import UIKit

enum IRSmoothScrollPhase: Equatable {
    case idle
    case active
}

struct IRSmoothScrollSnapshot: Equatable {
    let phase: IRSmoothScrollPhase
    let generation: UInt64
    let finalPoint: CGPoint
    let alreadyPoint: CGPoint
    let duration: CGFloat
    let startTimestamp: TimeInterval?
    let isPaned: Bool
    let didHorizontalBoundsBounce: Bool
    let didVerticalBoundsBounce: Bool
}

struct IRSmoothScrollTick: Equatable {
    let generation: UInt64
    let move: CGPoint
    let isPaned: Bool
    let isFinished: Bool
}

struct IRSmoothScrollBoundsRequest: Equatable {
    let amount: CGFloat
    let direction: IRScrollDirectionType
}

struct IRSmoothScrollBoundsRequests: Equatable {
    let horizontal: IRSmoothScrollBoundsRequest?
    let vertical: IRSmoothScrollBoundsRequest?
}

final class IRSmoothScrollSession: @unchecked Sendable {
    struct Step: Equatable {
        let move: CGPoint
        let alreadyPoint: CGPoint
        let isFinished: Bool
    }

    private struct ActiveState {
        let generation: UInt64
        let finalPoint: CGPoint
        var alreadyPoint = CGPoint.zero
        let duration: CGFloat
        var startTimestamp: TimeInterval?
        let isPaned: Bool
        var didHorizontalBoundsBounce = false
        var didVerticalBoundsBounce = false
    }

    private enum State {
        case idle
        case active(ActiveState)
    }

    private let lock = NSLock()
    private var generation: UInt64 = 0
    private var state: State = .idle
    private var isPaned = false

    var snapshot: IRSmoothScrollSnapshot {
        lock.lock()
        defer { lock.unlock() }
        switch state {
        case .idle:
            return IRSmoothScrollSnapshot(
                phase: .idle,
                generation: generation,
                finalPoint: .zero,
                alreadyPoint: .zero,
                duration: 0,
                startTimestamp: nil,
                isPaned: isPaned,
                didHorizontalBoundsBounce: false,
                didVerticalBoundsBounce: false
            )
        case .active(let active):
            return IRSmoothScrollSnapshot(
                phase: .active,
                generation: active.generation,
                finalPoint: active.finalPoint,
                alreadyPoint: active.alreadyPoint,
                duration: active.duration,
                startTimestamp: active.startTimestamp,
                isPaned: active.isPaned,
                didHorizontalBoundsBounce:
                    active.didHorizontalBoundsBounce,
                didVerticalBoundsBounce:
                    active.didVerticalBoundsBounce
            )
        }
    }

    func setPaned(_ isPaned: Bool) {
        lock.lock()
        self.isPaned = isPaned
        lock.unlock()
    }

    @discardableResult
    func start(velocity: CGPoint) -> Bool {
        let target = Self.smoothScrollTarget(for: velocity)
        return start(
            finalPoint: target.point,
            duration: target.duration
        )
    }

    @discardableResult
    func startDegreeShift(
        degreeX: Float,
        degreeY: Float
    ) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard let nextGeneration =
                nextGenerationLocked() else {
            state = .idle
            return false
        }

        let remaining: CGPoint
        switch state {
        case .idle:
            remaining = .zero
        case .active(let active):
            remaining = CGPoint(
                x: active.finalPoint.x
                    - active.alreadyPoint.x,
                y: active.finalPoint.y
                    - active.alreadyPoint.y
            )
        }
        isPaned = false

        guard degreeX.isFinite, degreeY.isFinite else {
            state = .idle
            return false
        }
        let finalPoint = CGPoint(
            x: CGFloat(degreeX) + remaining.x,
            y: -CGFloat(degreeY) + remaining.y
        )
        guard Self.isValidWork(
            finalPoint: finalPoint,
            duration: 0.5
        ) else {
            state = .idle
            return false
        }
        state = .active(
            ActiveState(
                generation: nextGeneration,
                finalPoint: finalPoint,
                duration: 0.5,
                isPaned: false
            )
        )
        return true
    }

    @discardableResult
    func reset() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard case .active = state else {
            return false
        }
        _ = nextGenerationLocked()
        state = .idle
        return true
    }

    func advance(timestamp: TimeInterval)
        -> IRSmoothScrollTick?
    {
        lock.lock()
        defer { lock.unlock() }
        guard case .active(var active) = state else {
            return nil
        }
        guard timestamp.isFinite else {
            _ = nextGenerationLocked()
            state = .idle
            return nil
        }
        if active.startTimestamp == nil {
            active.startTimestamp = timestamp
        }
        guard let startTimestamp =
                active.startTimestamp else {
            state = .idle
            return nil
        }
        let elapsed = CGFloat(timestamp - startTimestamp)
        guard let step = Self.step(
            finalPoint: active.finalPoint,
            alreadyPoint: active.alreadyPoint,
            elapsed: elapsed,
            duration: active.duration
        ) else {
            _ = nextGenerationLocked()
            state = .idle
            return nil
        }

        active.alreadyPoint = step.alreadyPoint
        let tick = IRSmoothScrollTick(
            generation: active.generation,
            move: step.move,
            isPaned: active.isPaned,
            isFinished: step.isFinished
        )
        state = step.isFinished
            ? .idle
            : .active(active)
        return tick
    }

    func admitBounds(
        _ bounds: IRGLTransformController.ScrollToBounds
    ) -> IRSmoothScrollBoundsRequests {
        lock.lock()
        defer { lock.unlock() }
        guard case .active(var active) = state else {
            return IRSmoothScrollBoundsRequests(
                horizontal: nil,
                vertical: nil
            )
        }

        var moveX =
            active.finalPoint.x - active.alreadyPoint.x
        var moveY =
            active.finalPoint.y - active.alreadyPoint.y
        guard moveX.isFinite, moveY.isFinite else {
            _ = nextGenerationLocked()
            state = .idle
            return IRSmoothScrollBoundsRequests(
                horizontal: nil,
                vertical: nil
            )
        }

        switch bounds {
        case .horizontal:
            moveY = 0
        case .vertical:
            moveX = 0
        case .both:
            break
        default:
            moveX = 0
            moveY = 0
        }

        let horizontal =
            active.didHorizontalBoundsBounce
                ? nil
                : Self.boundsRequest(
                    amount: moveX,
                    positiveDirection: .right,
                    negativeDirection: .left
                )
        let vertical =
            active.didVerticalBoundsBounce
                ? nil
                : Self.boundsRequest(
                    amount: moveY,
                    positiveDirection: .down,
                    negativeDirection: .up
                )
        active.didHorizontalBoundsBounce =
            active.didHorizontalBoundsBounce
            || horizontal != nil
        active.didVerticalBoundsBounce =
            active.didVerticalBoundsBounce
            || vertical != nil
        state = .active(active)
        return IRSmoothScrollBoundsRequests(
            horizontal: horizontal,
            vertical: vertical
        )
    }

    static func smoothScrollTarget(
        for velocity: CGPoint
    ) -> (point: CGPoint, duration: CGFloat) {
        guard velocity.x.isFinite,
              velocity.y.isFinite else {
            return (.zero, 0)
        }
        let magnitude = hypot(velocity.x, velocity.y)
        guard magnitude.isFinite else {
            return (.zero, 0)
        }
        let slideFactor =
            0.05 * (magnitude / 200)
        let point = CGPoint(
            x: velocity.x * slideFactor,
            y: velocity.y * slideFactor
        )
        let duration = slideFactor * 2
        guard isValidWork(
            finalPoint: point,
            duration: duration
        ) else {
            return (.zero, 0)
        }
        return (point, duration)
    }

    static func step(
        finalPoint: CGPoint,
        alreadyPoint: CGPoint,
        elapsed: CGFloat,
        duration: CGFloat
    ) -> Step? {
        guard finalPoint.x.isFinite,
              finalPoint.y.isFinite,
              alreadyPoint.x.isFinite,
              alreadyPoint.y.isFinite,
              elapsed.isFinite,
              duration.isFinite,
              duration > 0 else {
            return nil
        }

        let clampedElapsed =
            min(max(elapsed, 0), duration)
        var percentage = clampedElapsed / duration
        percentage =
            -percentage * (percentage - 2)
        let move = CGPoint(
            x: finalPoint.x * percentage
                - alreadyPoint.x,
            y: finalPoint.y * percentage
                - alreadyPoint.y
        )
        let nextPoint = CGPoint(
            x: alreadyPoint.x + move.x,
            y: alreadyPoint.y + move.y
        )
        guard move.x.isFinite,
              move.y.isFinite,
              nextPoint.x.isFinite,
              nextPoint.y.isFinite else {
            return nil
        }
        return Step(
            move: move,
            alreadyPoint: nextPoint,
            isFinished: clampedElapsed >= duration
        )
    }

    private func start(
        finalPoint: CGPoint,
        duration: CGFloat
    ) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard let nextGeneration =
                nextGenerationLocked() else {
            state = .idle
            return false
        }
        guard Self.isValidWork(
            finalPoint: finalPoint,
            duration: duration
        ) else {
            state = .idle
            return false
        }
        state = .active(
            ActiveState(
                generation: nextGeneration,
                finalPoint: finalPoint,
                duration: duration,
                isPaned: isPaned
            )
        )
        return true
    }

    private static func isValidWork(
        finalPoint: CGPoint,
        duration: CGFloat
    ) -> Bool {
        finalPoint.x.isFinite
            && finalPoint.y.isFinite
            && Float(finalPoint.x).isFinite
            && Float(finalPoint.y).isFinite
            && finalPoint != .zero
            && duration.isFinite
            && duration > 0
    }

    private static func boundsRequest(
        amount: CGFloat,
        positiveDirection: IRScrollDirectionType,
        negativeDirection: IRScrollDirectionType
    ) -> IRSmoothScrollBoundsRequest? {
        if amount > 0 {
            return IRSmoothScrollBoundsRequest(
                amount: amount,
                direction: positiveDirection
            )
        } else if amount < 0 {
            return IRSmoothScrollBoundsRequest(
                amount: amount,
                direction: negativeDirection
            )
        }
        return nil
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
