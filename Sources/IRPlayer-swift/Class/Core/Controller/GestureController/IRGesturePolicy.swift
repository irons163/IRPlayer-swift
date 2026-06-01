//
//  IRGesturePolicy.swift
//  IRPlayer-swift
//
//  Created by Codex on 2026/6/2.
//

import UIKit

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

    static func shouldRecognizeSimultaneously(otherRecognizerIsManaged: Bool,
                                              gestureIsPan: Bool,
                                              panTranslation: CGPoint?,
                                              disabledPanMovingAxes: IRDisablePanMovingDirection,
                                              numberOfTouches: Int) -> Bool {
        guard otherRecognizerIsManaged else { return false }

        if gestureIsPan {
            guard let panTranslation = panTranslation else { return true }
            let axis = panMovingAxis(forTranslation: panTranslation)
            if isPanMovingAxisDisabled(axis, disabledAxes: disabledPanMovingAxes) {
                return true
            }
        }

        return numberOfTouches < 2
    }
}
