//
//  IRBouncePolicy.swift
//  IRPlayer-swift
//
//  Created by Codex on 2026/6/2.
//

import UIKit

struct IRBouncePathGeometry {
    let start: CGPoint
    let control: CGPoint
    let end: CGPoint
}

struct IRBounceAnimationPlan: Equatable {
    enum Axis {
        case horizontal
        case vertical
    }

    let key: String
    let axis: Axis
}

enum IRBouncePolicy {
    static func bouncePathGeometry(amount: CGFloat, direction type: IRScrollDirectionType, targetSize: CGSize) -> IRBouncePathGeometry {
        let targetViewWidth = targetSize.width
        let targetViewHeight = targetSize.height
        let bounceWidth = min(targetViewWidth / 10, targetViewHeight / 10)

        switch type {
        case .left:
            return IRBouncePathGeometry(start: CGPoint(x: targetViewWidth, y: 0),
                                        control: CGPoint(x: max(targetViewWidth + amount, targetViewWidth - bounceWidth), y: targetViewHeight / 2),
                                        end: CGPoint(x: targetViewWidth, y: targetViewHeight))
        case .right:
            return IRBouncePathGeometry(start: .zero,
                                        control: CGPoint(x: min(amount, bounceWidth), y: targetViewHeight / 2),
                                        end: CGPoint(x: 0, y: targetViewHeight))
        case .up:
            return IRBouncePathGeometry(start: CGPoint(x: 0, y: targetViewHeight),
                                        control: CGPoint(x: targetViewWidth / 2, y: max(targetViewHeight + amount, targetViewHeight - bounceWidth)),
                                        end: CGPoint(x: targetViewWidth, y: targetViewHeight))
        case .down:
            return IRBouncePathGeometry(start: .zero,
                                        control: CGPoint(x: targetViewWidth / 2, y: min(amount, bounceWidth)),
                                        end: CGPoint(x: targetViewWidth, y: 0))
        default:
            return IRBouncePathGeometry(start: .zero, control: .zero, end: .zero)
        }
    }

    static func animationPlan(for type: IRScrollDirectionType) -> IRBounceAnimationPlan? {
        switch type {
        case .left:
            return IRBounceAnimationPlan(key: "bounce_right", axis: .horizontal)
        case .right:
            return IRBounceAnimationPlan(key: "bounce_left", axis: .horizontal)
        case .up:
            return IRBounceAnimationPlan(key: "bounce_bottom", axis: .vertical)
        case .down:
            return IRBounceAnimationPlan(key: "bounce_top", axis: .vertical)
        default:
            return nil
        }
    }
}
