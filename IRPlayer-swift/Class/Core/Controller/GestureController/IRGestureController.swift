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
            let translation = (gestureRecognizer as! UIPanGestureRecognizer).translation(in: targetView)
            let x = abs(translation.x)
            let y = abs(translation.y)
            if x < y && disablePanMovingDirection.contains(.vertical) { // up and down moving direction.
                return false
            } else if x > y && disablePanMovingDirection.contains(.horizontal) { // left and right moving direction.
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
        panLocation = locationPoint.x > targetView!.bounds.size.width / 2 ? .right : .left

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
            let translation = (gestureRecognizer as! UIPanGestureRecognizer).translation(in: targetView)
            let x = abs(translation.x)
            let y = abs(translation.y)
            if x < y && disablePanMovingDirection.contains(.vertical) {
                return true
            } else if x > y && disablePanMovingDirection.contains(.horizontal) {
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
        switch pan.state {
        case .began:
            panMovingDirection = .unknown
            let x = abs(velocity.x)
            let y = abs(velocity.y)
            if x > y {
                panDirection = .horizontal
            } else if x < y {
                panDirection = .vertical
            } else {
                panDirection = .unknown
            }
            beganPan?(self, panDirection, panLocation)
        case .changed:
            switch panDirection {
            case .horizontal:
                panMovingDirection = translate.x > 0 ? .right : .left
            case .vertical:
                panMovingDirection = translate.y > 0 ? .bottom : .top
            case .unknown:
                break
            }
            changedPan?(self, panDirection, panLocation, velocity)
        case .failed, .cancelled, .ended:
            endedPan?(self, panDirection, panLocation)
        default:
            break
        }
    }

    @objc func handlePinch(_ pinch: UIPinchGestureRecognizer) {
        if pinch.state == .ended {
            pinched?(self, pinch.scale)
        }
    }
}
