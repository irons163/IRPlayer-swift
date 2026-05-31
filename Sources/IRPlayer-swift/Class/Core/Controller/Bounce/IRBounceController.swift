//
//  IRBounceController.swift
//  IRPlayer-swift
//
//  Created by irons on 2024/8/7.
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

@objc public enum IRScrollDirectionType: Int {
    case none
    case left
    case right
    case up
    case down
}

@objcMembers public class IRBounceController: NSObject {
    private weak var targetView: UIView?
    private var horizontalLineLayer: CAShapeLayer?
    private var verticalLineLayer: CAShapeLayer?
    private var targetViewWidth: CGFloat {
        return targetView?.bounds.size.width ?? 0
    }
    private var targetViewHeight: CGFloat {
        return targetView?.bounds.size.height ?? 0
    }

    @nonobjc static func bouncePathGeometry(amount: CGFloat, direction type: IRScrollDirectionType, targetSize: CGSize) -> IRBouncePathGeometry {
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

    @nonobjc static func animationPlan(for type: IRScrollDirectionType) -> IRBounceAnimationPlan? {
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

    public func addBounceToView(_ view: UIView) {
        self.targetView = view
        createLine()
    }

    private func createLine() {
        let horizontalLineLayer = CAShapeLayer()
        horizontalLineLayer.strokeColor = UIColor(white: 0.333, alpha: 0.5).cgColor
        horizontalLineLayer.lineWidth = 0.0
        horizontalLineLayer.fillColor = UIColor(white: 0.333, alpha: 0.5).cgColor
        targetView?.layer.addSublayer(horizontalLineLayer)
        self.horizontalLineLayer = horizontalLineLayer

        let verticalLineLayer = CAShapeLayer()
        verticalLineLayer.strokeColor = UIColor(white: 0.333, alpha: 0.5).cgColor
        verticalLineLayer.lineWidth = 0.0
        verticalLineLayer.fillColor = UIColor(white: 0.333, alpha: 0.5).cgColor
        targetView?.layer.addSublayer(verticalLineLayer)
        self.verticalLineLayer = verticalLineLayer
    }

    public func removeAndAddAnimate(with scrollValue: CGFloat, byScrollDirection type: IRScrollDirectionType) {
        guard let plan = Self.animationPlan(for: type) else { return }
        let lineLayer: CAShapeLayer?
        let startPath = getLinePath(withAmount: scrollValue, byScrollDirection: type)
        let endPath = getLinePath(withAmount: 0.0, byScrollDirection: type)

        switch plan.axis {
        case .horizontal:
            lineLayer = horizontalLineLayer
        case .vertical:
            lineLayer = verticalLineLayer
        }

        lineLayer?.removeAnimation(forKey: plan.key)
        lineLayer?.path = startPath.cgPath

        let morph = CABasicAnimation(keyPath: "path")
        morph.timingFunction = CAMediaTimingFunction(name: .easeIn)
        morph.fromValue = lineLayer?.path
        morph.toValue = endPath.cgPath
        morph.duration = 0.2
        morph.isRemovedOnCompletion = false
        morph.fillMode = .forwards
        lineLayer?.add(morph, forKey: plan.key)
    }

    private func getLinePath(withAmount amount: CGFloat, byScrollDirection type: IRScrollDirectionType) -> UIBezierPath {
        guard type != .none else {
            return UIBezierPath()
        }
        let geometry = Self.bouncePathGeometry(amount: amount,
                                               direction: type,
                                               targetSize: CGSize(width: targetViewWidth, height: targetViewHeight))

        let path = UIBezierPath()
        path.move(to: geometry.start)
        path.addQuadCurve(to: geometry.end, controlPoint: geometry.control)
        path.close()

        return path
    }
}
