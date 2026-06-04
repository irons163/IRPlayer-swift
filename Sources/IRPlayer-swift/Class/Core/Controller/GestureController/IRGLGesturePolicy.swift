//
//  IRGLGesturePolicy.swift
//  IRPlayer-swift
//
//  Created by Codex on 2026/6/2.
//

import UIKit

enum IRGLGesturePolicy {
    enum PanAction: Equatable {
        case begin
        case update
        case endWithDeceleration
        case cancel
    }

    enum ContinuousAction: Equatable {
        case begin
        case update
        case end
    }

    static func renderPoint(from point: CGPoint, viewHeight: CGFloat, screenScale: CGFloat) -> CGPoint {
        guard point.x.isFinite,
              point.y.isFinite,
              viewHeight.isFinite,
              screenScale.isFinite,
              screenScale > 0 else {
            return .zero
        }
        return CGPoint(x: point.x * screenScale,
                       y: (viewHeight - point.y) * screenScale)
    }

    static func panAction(for state: UIGestureRecognizer.State) -> PanAction {
        switch state {
        case .cancelled, .failed:
            return .cancel
        case .ended:
            return .endWithDeceleration
        case .began:
            return .begin
        default:
            return .update
        }
    }

    static func continuousAction(for state: UIGestureRecognizer.State) -> ContinuousAction {
        switch state {
        case .cancelled, .ended, .failed:
            return .end
        case .began:
            return .begin
        default:
            return .update
        }
    }

    static func shouldBeginGesture(superAllowsGesture: Bool,
                                   isDoubleTapGesture: Bool,
                                   doubleTapEnabled: Bool,
                                   isSwipeGesture: Bool,
                                   isProgramZooming: Bool) -> Bool {
        guard superAllowsGesture else { return false }

        if isDoubleTapGesture, !doubleTapEnabled {
            return false
        }

        if isSwipeGesture, isProgramZooming {
            return false
        }

        return true
    }
}
