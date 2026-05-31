//
//  IRSmoothScrollController.swift
//  IRPlayer-swift
//
//  Created by irons on 2024/8/7.
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

@objcMembers public class IRSmoothScrollController: NSObject {
    weak var delegate: IRGLViewDelegate?
    var currentMode: IRGLRenderMode?
    private(set) weak var targetView: IRGLView?
    var isPaned: Bool = false

    private var finalPoint = CGPoint.zero
    private var alreadyPoint = CGPoint.zero
    private var slideDuration: CGFloat = 0.0
    private var timer: CADisplayLink?
    private var startTimestamp: TimeInterval = 0
    private var lastTimestamp: TimeInterval = 0
    private var didHorizontalBoundsBounce: Bool = false
    private var didVerticalBoundsBounce: Bool = false
    private var bounce: IRBounceController?

    init(targetView: IRGLView) {
        super.init()
        self.targetView = targetView
        self.bounce = IRBounceController()
        self.bounce?.addBounceToView(targetView)

        self.timer = CADisplayLink(target: self, selector: #selector(tick(_:)))
        self.timer?.add(to: .main, forMode: .default)
    }

    @objc private func tick(_ sender: CADisplayLink) {
        guard finalPoint != .zero else {
            return
        }

        if startTimestamp == 0 {
            startTimestamp = sender.timestamp
        }

        let elapsed = CGFloat(sender.timestamp - startTimestamp)
        guard let step = IRSmoothScrollPolicy.step(finalPoint: finalPoint,
                                                   alreadyPoint: alreadyPoint,
                                                   elapsed: elapsed,
                                                   duration: slideDuration) else {
            resetSmoothScroll()
            return
        }

        let moveX = step.move.x
        let moveY = step.move.y
        alreadyPoint = step.alreadyPoint

        if self.isPaned {
            self.targetView?.scroll(byDx: Float(moveX * UIScreen.main.scale), dy: Float(-moveY * UIScreen.main.scale))
        } else {
            self.currentMode?.shiftController.shiftDegreeX(Float(moveX), degreeY: -Float(moveY))
            self.targetView?.render(nil)
        }

        if step.isFinished {
            self.resetSmoothScroll()
            delegate?.glViewDidEndDecelerating(self.targetView)
        }
    }

    func resetSmoothScroll() {
        finalPoint = .zero
        alreadyPoint = .zero
        startTimestamp = 0
        didHorizontalBoundsBounce = false
        didVerticalBoundsBounce = false
    }

    func calculateSmoothScroll(velocity: CGPoint) {
        self.resetSmoothScroll()
        let target = Self.smoothScrollTarget(for: velocity)
        finalPoint = target.point
        slideDuration = target.duration
    }

    func scrollBy(dx: Float, dy: Float) {
        self.targetView?.scroll(byDx: dx, dy: dy)
    }

    public func shiftDegreeX(_ degreeX: Float, degreeY: Float) {
        var degreeX = degreeX
        var degreeY = degreeY
        let unmoveYetX = finalPoint.x - alreadyPoint.x
        let unmoveYetY = finalPoint.y - alreadyPoint.y
        degreeX += Float(unmoveYetX)
        degreeY += Float(-unmoveYetY)

        self.resetSmoothScroll()
        self.isPaned = false

        finalPoint = CGPoint(x: CGFloat(degreeX), y: CGFloat(-degreeY))
        slideDuration = 0.5
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
}

extension IRSmoothScrollController: IRGLProgramDelegate {

    func didScrollToBounds(_ bounds: IRGLTransformController.ScrollToBounds, withProgram program: IRGLProgram2D) {
        let boundsBounce = IRSmoothScrollPolicy.boundsBounce(bounds: bounds,
                                                             finalPoint: finalPoint,
                                                             alreadyPoint: alreadyPoint,
                                                             didHorizontalBounce: didHorizontalBoundsBounce,
                                                             didVerticalBounce: didVerticalBoundsBounce)

        if let horizontal = boundsBounce.horizontal {
            bounce?.removeAndAddAnimate(with: horizontal.amount, byScrollDirection: horizontal.direction)
            didHorizontalBoundsBounce = true
        }

        if let vertical = boundsBounce.vertical {
            bounce?.removeAndAddAnimate(with: vertical.amount, byScrollDirection: vertical.direction)
            didVerticalBoundsBounce = true
        }

        delegate?.glViewDidScroll(toBounds: self.targetView)
    }
}
