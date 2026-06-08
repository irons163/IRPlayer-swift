//
//  IRSmoothScrollController.swift
//  IRPlayer-swift
//
//  Created by irons on 2024/8/7.
//

import UIKit

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
        return IRSmoothScrollPolicy.smoothScrollTarget(for: velocity)
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
