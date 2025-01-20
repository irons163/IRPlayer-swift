//
//  IRGLGestureController.swift
//  IRPlayer-swift
//
//  Created by irons on 2024/8/4.
//

import Foundation
import UIKit

@objc public protocol IRGLViewDelegate: AnyObject {
    func glViewDidEndDragging(_ view: IRGLView?, willDecelerate: Bool)
    func glViewWillBeginDragging(_ view: IRGLView?)
    func glViewWillBeginZooming(_ view: IRGLView?)
    func glViewDidEndDecelerating(_ view: IRGLView?)
    func glViewDidEndZooming(_ view: IRGLView?, atScale scale: CGFloat)
    func glViewDidScroll(toBounds view: IRGLView?)
}

class IRGLGestureController: IRGestureController {

    var doubleTapEnable: Bool = true
    var swipeEnable: Bool = true
    var currentMode: IRGLRenderMode? {
        didSet {
            if let program = currentMode?.program {
                program.delegate = smoothScroll
            }
            currentMode?.delegate = self
            smoothScroll?.currentMode = currentMode!
        }
    }
    weak var delegate: IRGLViewDelegate?
    weak var smoothScroll: IRSmoothScrollController?
    private var targetGLView: IRGLView? {
        return targetView as? IRGLView
    }

    private var rotateGR: UIRotationGestureRecognizer!
    private var isTouchedInProgram: Bool = false

    func addGesture(to view: IRGLView) {
        super.addGestureToView(view)
        initDefaultValue()
    }

    override func removeGesture(to view: UIView) {
        super.removeGesture(to: view)
    }

    private func initDefaultValue() {
        self.swipeEnable = true

        rotateGR = UIRotationGestureRecognizer(target: self, action: #selector(handleRotate(_:)))
        targetView?.addGestureRecognizer(rotateGR)

        isTouchedInProgram = false
        self.doubleTapEnable = true
    }

    // MARK: - Gesture Callback
    @objc override func handlePan(_ gr: UIPanGestureRecognizer) {
        super.handlePan(gr)

        print("didPan, state \(gr.state.rawValue)")

        smoothScroll?.isPaned = true
        smoothScroll?.resetSmoothScroll()

        switch gr.state {
        case .cancelled, .failed:
            isTouchedInProgram = false
            delegate?.glViewDidEndDragging(targetGLView, willDecelerate: false)

        case .ended:
            isTouchedInProgram = false
            let velocity = gr.velocity(in: targetView)
            smoothScroll?.calculateSmoothScroll(velocity: velocity)
            delegate?.glViewDidEndDragging(targetGLView, willDecelerate: velocity == .zero)

        case .began:
            let touchedPoint = gr.location(in: targetView)
            let scaledPoint = CGPoint(x: touchedPoint.x * UIScreen.main.scale,
                                      y: ((targetView?.frame.size.height ?? 0) - touchedPoint.y) * UIScreen.main.scale)
            isTouchedInProgram = currentMode?.program?.touchedInProgram(scaledPoint) ?? false

        default:
            guard isTouchedInProgram else { return }
            delegate?.glViewWillBeginDragging(targetGLView)
            let screenOffset = gr.translation(in: targetView)
            smoothScroll?.scrollBy(dx: Float(screenOffset.x * UIScreen.main.scale),
                                   dy: Float(-1 * screenOffset.y * UIScreen.main.scale))
            gr.setTranslation(.zero, in: targetView)
        }
    }

    @objc override func handlePinch(_ sender: UIPinchGestureRecognizer) {
        super.handlePinch(sender)

        print("didPinch \(sender.scale) state \(sender.state.rawValue)")

        switch sender.state {
        case .cancelled, .ended, .failed:
            isTouchedInProgram = false

        case .began:
            let touchedPoint = sender.location(in: targetView)
            let scaledPoint = CGPoint(x: touchedPoint.x * UIScreen.main.scale,
                                      y: ((targetView?.frame.size.height ?? 0) - touchedPoint.y) * UIScreen.main.scale)
            isTouchedInProgram = currentMode?.program?.touchedInProgram(scaledPoint) ?? false

        default:
            guard isTouchedInProgram, sender.numberOfTouches >= 2 else { return }

            let p1 = sender.location(ofTouch: 0, in: targetView)
            let p2 = sender.location(ofTouch: 1, in: targetView)

            delegate?.glViewWillBeginZooming(targetGLView)
            targetGLView?.updateScope(byFx: Float((p1.x + p2.x) / 2),
                                      fy: Float((p1.y + p2.y) / 2),
                                      dsx: Float(sender.scale),
                                      dsy: Float(sender.scale))
            delegate?.glViewDidEndZooming(targetGLView, atScale: 0)
            sender.scale = 1
        }
    }

    @objc func handleRotate(_ gr: UIRotationGestureRecognizer) {
        print("didRotate, state \(gr.state.rawValue)")
        switch gr.state {
        case .cancelled, .ended, .failed:
            isTouchedInProgram = false

        case .began:
            let touchedPoint = gr.location(in: targetView)
            let scaledPoint = CGPoint(x: touchedPoint.x * UIScreen.main.scale,
                                      y: ((targetView?.frame.size.height ?? 0) - touchedPoint.y) * UIScreen.main.scale)
            isTouchedInProgram = currentMode?.program?.touchedInProgram(scaledPoint) ?? false

        default:
            guard isTouchedInProgram else { return }

            delegate?.glViewWillBeginDragging(targetGLView)
            print("rotate: \(gr.rotation)")
            updateRotation(Float(gr.rotation))
            gr.rotation = 0
            delegate?.glViewDidEndDragging(nil, willDecelerate: false)
        }
    }

    func updateRotation(_ rotateRadians: Float) {
        currentMode?.program?.didRotate(-rotateRadians)
        targetGLView?.render(nil)
    }

    @objc override func handleDoubleTap(_ gr: UITapGestureRecognizer) {
        super.handleDoubleTap(gr)

        print("didDoubleTap, state \(gr.state.rawValue)")

        isTouchedInProgram = false
        let touchedPoint = gr.location(in: targetView)
        let scaledPoint = CGPoint(x: touchedPoint.x * UIScreen.main.scale,
                                  y: ((targetView?.frame.size.height ?? 0) - touchedPoint.y) * UIScreen.main.scale)
        isTouchedInProgram = currentMode?.program?.touchedInProgram(scaledPoint) ?? false

        guard isTouchedInProgram else { return }

        currentMode?.program?.doResetToDefaultScaleBlock = { program in
            guard !program.getCurrentScale().equalTo(CGPoint(x: 1.0, y: 1.0)) else { return false }
            program.setDefaultScale(1.0)
            return true
        }

        currentMode?.program?.didDoubleTap()
        currentMode?.update()
        targetGLView?.render(nil)
    }

    func isProgramZooming() -> Bool {
        guard let scale = currentMode?.program?.getCurrentScale() else { return false }
        return scale != CGPoint(x: 1.0, y: 1.0)
    }

    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        let shouldBegin = super.gestureRecognizerShouldBegin(gestureRecognizer)

        let touchedPoint = gestureRecognizer.location(in: targetView)
        let scaledPoint = CGPoint(x: touchedPoint.x * UIScreen.main.scale,
                                  y: ((targetView?.frame.size.height ?? 0) - touchedPoint.y) * UIScreen.main.scale)
        isTouchedInProgram = currentMode?.program?.touchedInProgram(scaledPoint) ?? false

        if (!doubleTapEnable), gestureRecognizer == doubleTapGR {
            return false
        } else if let swipeGR = gestureRecognizer as? UISwipeGestureRecognizer, isProgramZooming() {
            return false
        }
        return shouldBegin
    }

    override func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        let shouldRecognizeSimultaneously = super.gestureRecognizer(gestureRecognizer, shouldRecognizeSimultaneouslyWith: otherGestureRecognizer)

        if let panGR = gestureRecognizer as? UIPanGestureRecognizer,
           let swipeGR = otherGestureRecognizer as? UISwipeGestureRecognizer,
           swipeEnable, !isProgramZooming() {
            return true
        }
        return shouldRecognizeSimultaneously
    }
}

extension IRGLGestureController: IRGLRenderModeDelegate {

    func programDidCreate(_ program: IRGLProgram2D) {
        program.delegate = smoothScroll
    }
}
