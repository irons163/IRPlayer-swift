//
//  IRSmoothScrollPolicy.swift
//  IRPlayer-swift
//
//  Created by Codex on 2026/6/2.
//

import UIKit

enum IRSmoothScrollPolicy {
    struct Step {
        let move: CGPoint
        let alreadyPoint: CGPoint
        let isFinished: Bool
    }

    struct BoundsBounce {
        struct Request {
            let amount: CGFloat
            let direction: IRScrollDirectionType
        }

        let horizontal: Request?
        let vertical: Request?
    }

    static func smoothScrollTarget(for velocity: CGPoint) -> (point: CGPoint, duration: CGFloat) {
        guard velocity.x.isFinite, velocity.y.isFinite else {
            return (point: .zero, duration: 0)
        }
        let magnitude = sqrt((velocity.x * velocity.x) + (velocity.y * velocity.y))
        let slideFactor = 0.05 * (magnitude / 200)
        return (
            point: CGPoint(x: velocity.x * slideFactor, y: velocity.y * slideFactor),
            duration: slideFactor * 2
        )
    }

    static func step(finalPoint: CGPoint, alreadyPoint: CGPoint, elapsed: CGFloat, duration: CGFloat) -> Step? {
        guard finalPoint.x.isFinite,
              finalPoint.y.isFinite,
              alreadyPoint.x.isFinite,
              alreadyPoint.y.isFinite,
              elapsed.isFinite,
              duration.isFinite,
              duration > 0 else {
            return nil
        }

        let clampedElapsed = min(max(elapsed, 0), duration)
        var percentage = clampedElapsed / duration
        percentage = -1 * percentage * (percentage - 2)

        let move = CGPoint(x: finalPoint.x * percentage - alreadyPoint.x,
                           y: finalPoint.y * percentage - alreadyPoint.y)
        let nextPoint = CGPoint(x: alreadyPoint.x + move.x,
                                y: alreadyPoint.y + move.y)

        return Step(move: move,
                    alreadyPoint: nextPoint,
                    isFinished: nextPoint == finalPoint)
    }

    static func boundsBounce(bounds: IRGLTransformController.ScrollToBounds,
                             finalPoint: CGPoint,
                             alreadyPoint: CGPoint,
                             didHorizontalBounce: Bool,
                             didVerticalBounce: Bool) -> BoundsBounce {
        guard finalPoint.x.isFinite,
              finalPoint.y.isFinite,
              alreadyPoint.x.isFinite,
              alreadyPoint.y.isFinite else {
            return BoundsBounce(horizontal: nil, vertical: nil)
        }

        var moveX = finalPoint.x - alreadyPoint.x
        var moveY = finalPoint.y - alreadyPoint.y

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

        let horizontal = didHorizontalBounce ? nil : bounceRequest(amount: moveX,
                                                                   positiveDirection: .right,
                                                                   negativeDirection: .left)
        let vertical = didVerticalBounce ? nil : bounceRequest(amount: moveY,
                                                               positiveDirection: .down,
                                                               negativeDirection: .up)
        return BoundsBounce(horizontal: horizontal, vertical: vertical)
    }

    private static func bounceRequest(amount: CGFloat,
                                      positiveDirection: IRScrollDirectionType,
                                      negativeDirection: IRScrollDirectionType) -> BoundsBounce.Request? {
        if amount > 0 {
            return BoundsBounce.Request(amount: amount, direction: positiveDirection)
        } else if amount < 0 {
            return BoundsBounce.Request(amount: amount, direction: negativeDirection)
        } else {
            return nil
        }
    }
}
