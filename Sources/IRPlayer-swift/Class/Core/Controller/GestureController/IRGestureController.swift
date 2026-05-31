//
//  IRGestureController.swift
//  IRPlayer-swift
//
//  Created by irons on 2024/8/4.
//

import UIKit

enum IRGestureType: UInt {
    case unknown
    case singleTap
    case doubleTap
    case pan
    case pinch
}

enum IRPanDirection: UInt {
    case unknown
    case vertical
    case horizontal
}

enum IRPanLocation: UInt {
    case unknown
    case left
    case right
}

enum IRPanMovingDirection: UInt {
    case unknown
    case top
    case left
    case bottom
    case right
}

struct IRDisableGestureTypes: OptionSet {
    let rawValue: UInt

    static let none         = IRDisableGestureTypes([])
    static let singleTap    = IRDisableGestureTypes(rawValue: 1 << 0)
    static let doubleTap    = IRDisableGestureTypes(rawValue: 1 << 1)
    static let pan          = IRDisableGestureTypes(rawValue: 1 << 2)
    static let pinch        = IRDisableGestureTypes(rawValue: 1 << 3)
    static let all          = IRDisableGestureTypes([.singleTap, .doubleTap, .pan, .pinch])
}

struct IRDisablePanMovingDirection: OptionSet {
    let rawValue: UInt

    static let none         = IRDisablePanMovingDirection([])
    static let vertical     = IRDisablePanMovingDirection(rawValue: 1 << 0)
    static let horizontal   = IRDisablePanMovingDirection(rawValue: 1 << 1)
    static let all          = IRDisablePanMovingDirection([.vertical, .horizontal])
}

enum IRGesturePolicy {
    enum PanAction: Equatable {
        case begin
        case change
        case end
    }

    enum PinchAction: Equatable {
        case end
    }

    static func panDirection(forVelocity velocity: CGPoint) -> IRPanDirection {
        guard velocity.x.isFinite, velocity.y.isFinite else {
            return .unknown
        }

        let x = abs(velocity.x)
        let y = abs(velocity.y)
        if x > y {
            return .horizontal
        } else if x < y {
            return .vertical
        } else {
            return .unknown
        }
    }

    static func panMovingDirection(forTranslation translation: CGPoint,
                                   panDirection: IRPanDirection) -> IRPanMovingDirection {
        guard translation.x.isFinite, translation.y.isFinite else {
            return .unknown
        }

        switch panDirection {
        case .horizontal:
            return translation.x > 0 ? .right : .left
        case .vertical:
            return translation.y > 0 ? .bottom : .top
        case .unknown:
            return .unknown
        }
    }

    static func panLocation(forTouchX touchX: CGFloat, targetWidth: CGFloat) -> IRPanLocation {
        guard touchX.isFinite, targetWidth.isFinite, targetWidth > 0 else {
            return .unknown
        }

        return touchX > targetWidth / 2 ? .right : .left
    }

    static func panMovingAxis(forTranslation translation: CGPoint) -> IRPanDirection {
        guard translation.x.isFinite, translation.y.isFinite else {
            return .unknown
        }

        let x = abs(translation.x)
        let y = abs(translation.y)
        if x > y {
            return .horizontal
        } else if x < y {
            return .vertical
        } else {
            return .unknown
        }
    }

    static func isPanMovingAxisDisabled(_ axis: IRPanDirection,
                                        disabledAxes: IRDisablePanMovingDirection) -> Bool {
        switch axis {
        case .horizontal:
            return disabledAxes.contains(.horizontal)
        case .vertical:
            return disabledAxes.contains(.vertical)
        case .unknown:
            return false
        }
    }

    static func panAction(for state: UIGestureRecognizer.State) -> PanAction? {
        switch state {
        case .began:
            return .begin
        case .changed:
            return .change
        case .failed, .cancelled, .ended:
            return .end
        default:
            return nil
        }
    }

    static func pinchAction(for state: UIGestureRecognizer.State) -> PinchAction? {
        state == .ended ? .end : nil
    }
}

class IRGestureController: NSObject, UIGestureRecognizerDelegate {
    weak private(set) var targetView: UIView?

    var triggerCondition: ((IRGestureController, IRGestureType, UIGestureRecognizer, UITouch) -> Bool)?
    var singleTapped: ((IRGestureController) -> Void)?
    var doubleTapped: ((IRGestureController) -> Void)?
    var beganPan: ((IRGestureController, IRPanDirection, IRPanLocation) -> Void)?
    var changedPan: ((IRGestureController, IRPanDirection, IRPanLocation, CGPoint) -> Void)?
    var endedPan: ((IRGestureController, IRPanDirection, IRPanLocation) -> Void)?
    var pinched: ((IRGestureController, CGFloat) -> Void)?

    private(set) lazy var singleTapGR: UITapGestureRecognizer = {
        let gesture = UITapGestureRecognizer(target: self, action: #selector(handleSingleTap(_:)))
        gesture.delegate = self
        gesture.delaysTouchesBegan = true
        gesture.delaysTouchesEnded = true
        gesture.numberOfTouchesRequired = 1
        gesture.numberOfTapsRequired = 1
        return gesture
    }()

    private(set) lazy var doubleTapGR: UITapGestureRecognizer = {
        let gesture = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
        gesture.delegate = self
        gesture.delaysTouchesBegan = true
        gesture.delaysTouchesEnded = true
        gesture.numberOfTouchesRequired = 1
        gesture.numberOfTapsRequired = 2
        return gesture
    }()

    private(set) lazy var panGR: UIPanGestureRecognizer = {
        let gesture = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        gesture.delegate = self
        gesture.delaysTouchesBegan = true
        gesture.delaysTouchesEnded = true
        gesture.maximumNumberOfTouches = 1
        gesture.cancelsTouchesInView = true
        return gesture
    }()

    private(set) lazy var pinchGR: UIPinchGestureRecognizer = {
        let gesture = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
        gesture.delegate = self
        gesture.delaysTouchesBegan = true
        return gesture
    }()

    private(set) var panDirection: IRPanDirection = .unknown
    private(set) var panLocation: IRPanLocation = .unknown
    private(set) var panMovingDirection: IRPanMovingDirection = .unknown

    var disableTypes: IRDisableGestureTypes = []
    var disablePanMovingDirection: IRDisablePanMovingDirection = []

    func addGestureToView(_ view: UIView) {
        targetView = view
        targetView?.isMultipleTouchEnabled = true
        singleTapGR.require(toFail: doubleTapGR)
        singleTapGR.require(toFail: panGR)
        targetView?.addGestureRecognizer(singleTapGR)
        targetView?.addGestureRecognizer(doubleTapGR)
        targetView?.addGestureRecognizer(panGR)
        targetView?.addGestureRecognizer(pinchGR)
    }

    func removeGesture(to view: UIView) {
        view.removeGestureRecognizer(singleTapGR)
        view.removeGestureRecognizer(doubleTapGR)
        view.removeGestureRecognizer(panGR)
        view.removeGestureRecognizer(pinchGR)
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        if gestureRecognizer == panGR {
            guard let panGestureRecognizer = gestureRecognizer as? UIPanGestureRecognizer else { return true }
            let translation = panGestureRecognizer.translation(in: targetView)
            let axis = IRGesturePolicy.panMovingAxis(forTranslation: translation)
            if IRGesturePolicy.isPanMovingAxisDisabled(axis, disabledAxes: disablePanMovingDirection) {
                return false
            }
        }
        return true
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        var type: IRGestureType = .unknown
        if gestureRecognizer == singleTapGR {
            type = .singleTap
        } else if gestureRecognizer == doubleTapGR {
            type = .doubleTap
        } else if gestureRecognizer == panGR {
            type = .pan
        } else if gestureRecognizer == pinchGR {
            type = .pinch
        }

        let locationPoint = touch.location(in: touch.view)
        if let targetView = targetView {
            panLocation = IRGesturePolicy.panLocation(forTouchX: locationPoint.x,
                                                       targetWidth: targetView.bounds.size.width)
        } else {
            panLocation = .unknown
        }

        switch type {
        case .unknown: break
        case .pan:
            if disableTypes.contains(.pan) {
                return false
            }
        case .pinch:
            if disableTypes.contains(.pinch) {
                return false
            }
        case .doubleTap:
            if disableTypes.contains(.doubleTap) {
                return false
            }
        case .singleTap:
            if disableTypes.contains(.singleTap) {
                return false
            }
        }

        if let triggerCondition = triggerCondition {
            return triggerCondition(self, type, gestureRecognizer, touch)
        }
        return true
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        if otherGestureRecognizer != singleTapGR &&
            otherGestureRecognizer != doubleTapGR &&
            otherGestureRecognizer != panGR &&
            otherGestureRecognizer != pinchGR {
            return false
        }

        if gestureRecognizer == panGR {
            guard let panGestureRecognizer = gestureRecognizer as? UIPanGestureRecognizer else { return true }
            let translation = panGestureRecognizer.translation(in: targetView)
            let axis = IRGesturePolicy.panMovingAxis(forTranslation: translation)
            if IRGesturePolicy.isPanMovingAxisDisabled(axis, disabledAxes: disablePanMovingDirection) {
                return true
            }
        }
        if gestureRecognizer.numberOfTouches >= 2 {
            return false
        }
        return true
    }

    @objc func handleSingleTap(_ tap: UITapGestureRecognizer) {
        singleTapped?(self)
    }

    @objc func handleDoubleTap(_ tap: UITapGestureRecognizer) {
        doubleTapped?(self)
    }

    @objc func handlePan(_ pan: UIPanGestureRecognizer) {
        let translate = pan.translation(in: pan.view)
        let velocity = pan.velocity(in: pan.view)
        switch IRGesturePolicy.panAction(for: pan.state) {
        case .begin:
            panMovingDirection = .unknown
            panDirection = IRGesturePolicy.panDirection(forVelocity: velocity)
            beganPan?(self, panDirection, panLocation)
        case .change:
            panMovingDirection = IRGesturePolicy.panMovingDirection(forTranslation: translate,
                                                                    panDirection: panDirection)
            changedPan?(self, panDirection, panLocation, velocity)
        case .end:
            endedPan?(self, panDirection, panLocation)
        case nil:
            break
        }
    }

    @objc func handlePinch(_ pinch: UIPinchGestureRecognizer) {
        if IRGesturePolicy.pinchAction(for: pinch.state) == .end {
            pinched?(self, pinch.scale)
        }
    }
}
