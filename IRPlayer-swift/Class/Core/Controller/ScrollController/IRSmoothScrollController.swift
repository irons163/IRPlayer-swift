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
        self.bounce?.addBounceToView(self.targetView!)

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

        let duration = min(slideDuration, CGFloat(sender.timestamp - startTimestamp))
        var percentage = duration / slideDuration
        percentage = -1 * percentage * (percentage - 2) // quadratic easing out

        let moveX = finalPoint.x * percentage - alreadyPoint.x
        let moveY = finalPoint.y * percentage - alreadyPoint.y

        alreadyPoint.x += moveX
        alreadyPoint.y += moveY

        if self.isPaned {
            self.targetView?.scroll(byDx: Float(moveX * UIScreen.main.scale), dy: Float(-moveY * UIScreen.main.scale))
        } else {
            self.currentMode?.shiftController.shiftDegreeX(Float(moveX), degreeY: -Float(moveY))
            self.targetView?.render(nil)
        }

        if finalPoint == alreadyPoint {
            self.resetSmoothScroll()
            delegate?.glViewDidEndDecelerating(self.targetView!)
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
        let magnitude = sqrt((velocity.x * velocity.x) + (velocity.y * velocity.y))
        let slideMult = magnitude / 200
        print("magnitude: \(magnitude), slideMult: \(slideMult)")

        self.resetSmoothScroll()
        let slideFactor = 0.05 * slideMult // Increase for more of a slide
        finalPoint = CGPoint(x: velocity.x * slideFactor, y: velocity.y * slideFactor)
        slideDuration = slideFactor * 2
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
}

extension IRSmoothScrollController: IRGLProgramDelegate {

    func didScrollToBounds(_ bounds: IRGLTransformController.ScrollToBounds, withProgram program: IRGLProgram2D) {
        var moveX = finalPoint.x - alreadyPoint.x
        var moveY = finalPoint.y - alreadyPoint.y
        var scrollDirectionType = IRScrollDirectionType.none

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

        if moveX > 0 {
            scrollDirectionType = .right
        } else if moveX < 0 {
            scrollDirectionType = .left
        }

        if !didHorizontalBoundsBounce && (scrollDirectionType == .left || scrollDirectionType == .right) {
            bounce?.removeAndAddAnimate(with: moveX, byScrollDirection: scrollDirectionType)
            didHorizontalBoundsBounce = true
        }

        if moveY > 0 {
            scrollDirectionType = .down
        } else if moveY < 0 {
            scrollDirectionType = .up
        }

        if !didVerticalBoundsBounce && (scrollDirectionType == .up || scrollDirectionType == .down) {
            bounce?.removeAndAddAnimate(with: moveY, byScrollDirection: scrollDirectionType)
            didVerticalBoundsBounce = true
        }

        delegate?.glViewDidScroll(toBounds: self.targetView)
    }
}
