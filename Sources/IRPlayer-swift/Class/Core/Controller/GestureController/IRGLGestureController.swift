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
            smoothScroll?.currentMode = currentMode
        }
    }
    weak var delegate: IRGLViewDelegate?
    weak var smoothScroll: IRSmoothScrollController?
    private var targetGLView: IRGLView? {
        return targetView as? IRGLView
    }

    private var rotateGR: UIRotationGestureRecognizer?
    private var isTouchedInProgram: Bool = false

    func addGesture(to view: IRGLView) {
        super.addGestureToView(view)
        initDefaultValue()
    }

    override func removeGesture(to view: UIView) {
        super.removeGesture(to: view)
        if let rotateGR = rotateGR {
            view.removeGestureRecognizer(rotateGR)
            self.rotateGR = nil
        }
    }

    private func initDefaultValue() {
        self.swipeEnable = true

        if let rotateGR = rotateGR {
            rotateGR.view?.removeGestureRecognizer(rotateGR)
        }

        let rotationGestureRecognizer = UIRotationGestureRecognizer(target: self, action: #selector(handleRotate(_:)))
        rotateGR = rotationGestureRecognizer
        targetView?.addGestureRecognizer(rotationGestureRecognizer)

        isTouchedInProgram = false
        self.doubleTapEnable = true
    }

    // MARK: - Gesture Callback
    @objc override func handlePan(_ gr: UIPanGestureRecognizer) {
        super.handlePan(gr)

        smoothScroll?.isPaned = true
        smoothScroll?.resetSmoothScroll()

        switch IRGLGesturePolicy.panAction(for: gr.state) {
        case .cancel:
            isTouchedInProgram = false
            delegate?.glViewDidEndDragging(targetGLView, willDecelerate: false)

        case .endWithDeceleration:
            isTouchedInProgram = false
            let velocity = gr.velocity(in: targetView)
            smoothScroll?.calculateSmoothScroll(velocity: velocity)
            delegate?.glViewDidEndDragging(targetGLView, willDecelerate: velocity == .zero)

        case .begin:
            let touchedPoint = gr.location(in: targetView)
            let scaledPoint = IRGLGesturePolicy.renderPoint(from: touchedPoint,
                                                            viewHeight: targetView?.frame.size.height ?? 0,
                                                            screenScale: UIScreen.main.scale)
            isTouchedInProgram = currentMode?.program?.touchedInProgram(scaledPoint) ?? false

        case .update:
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

        switch IRGLGesturePolicy.continuousAction(for: sender.state) {
        case .end:
            isTouchedInProgram = false

        case .begin:
            let touchedPoint = sender.location(in: targetView)
            let scaledPoint = IRGLGesturePolicy.renderPoint(from: touchedPoint,
                                                            viewHeight: targetView?.frame.size.height ?? 0,
                                                            screenScale: UIScreen.main.scale)
            isTouchedInProgram = currentMode?.program?.touchedInProgram(scaledPoint) ?? false

        case .update:
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
        switch IRGLGesturePolicy.continuousAction(for: gr.state) {
        case .end:
            isTouchedInProgram = false

        case .begin:
            let touchedPoint = gr.location(in: targetView)
            let scaledPoint = IRGLGesturePolicy.renderPoint(from: touchedPoint,
                                                            viewHeight: targetView?.frame.size.height ?? 0,
                                                            screenScale: UIScreen.main.scale)
            isTouchedInProgram = currentMode?.program?.touchedInProgram(scaledPoint) ?? false

        case .update:
            guard isTouchedInProgram else { return }

            delegate?.glViewWillBeginDragging(targetGLView)
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

        isTouchedInProgram = false
        let touchedPoint = gr.location(in: targetView)
        let scaledPoint = IRGLGesturePolicy.renderPoint(from: touchedPoint,
                                                        viewHeight: targetView?.frame.size.height ?? 0,
                                                        screenScale: UIScreen.main.scale)
        isTouchedInProgram = currentMode?.program?.touchedInProgram(scaledPoint) ?? false

        guard isTouchedInProgram else { return }

        if let program = currentMode?.program,
           program.tramsformController is IRGLTransformController2D {
            program.doResetToDefaultScaleBlock = { program in
                guard !program.getCurrentScale().equalTo(CGPoint(x: 1.0, y: 1.0)) else { return false }
                program.setDefaultScale(1.0)
                return true
            }
        } else {
            currentMode?.program?.doResetToDefaultScaleBlock = nil
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
        let scaledPoint = IRGLGesturePolicy.renderPoint(from: touchedPoint,
                                                        viewHeight: targetView?.frame.size.height ?? 0,
                                                        screenScale: UIScreen.main.scale)
        isTouchedInProgram = currentMode?.program?.touchedInProgram(scaledPoint) ?? false

        return IRGLGesturePolicy.shouldBeginGesture(superAllowsGesture: shouldBegin,
                                                   isDoubleTapGesture: gestureRecognizer == doubleTapGR,
                                                   doubleTapEnabled: doubleTapEnable,
                                                   isSwipeGesture: gestureRecognizer is UISwipeGestureRecognizer,
                                                   isProgramZooming: isProgramZooming())
    }

    override func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        let shouldRecognizeSimultaneously = super.gestureRecognizer(gestureRecognizer, shouldRecognizeSimultaneouslyWith: otherGestureRecognizer)

        if gestureRecognizer is UIPanGestureRecognizer,
           otherGestureRecognizer is UISwipeGestureRecognizer,
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
