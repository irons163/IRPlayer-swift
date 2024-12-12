//
//  IRBounceController.swift
//  IRPlayer-swift
//
//  Created by irons on 2024/8/7.
//

import UIKit

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

    public func addBounceToView(_ view: UIView) {
        self.targetView = view
        createLine()
    }

    private func createLine() {
        horizontalLineLayer = CAShapeLayer()
        horizontalLineLayer?.strokeColor = UIColor(white: 0.333, alpha: 0.5).cgColor
        horizontalLineLayer?.lineWidth = 0.0
        horizontalLineLayer?.fillColor = UIColor(white: 0.333, alpha: 0.5).cgColor
        targetView?.layer.addSublayer(horizontalLineLayer!)

        verticalLineLayer = CAShapeLayer()
        verticalLineLayer?.strokeColor = UIColor(white: 0.333, alpha: 0.5).cgColor
        verticalLineLayer?.lineWidth = 0.0
        verticalLineLayer?.fillColor = UIColor(white: 0.333, alpha: 0.5).cgColor
        targetView?.layer.addSublayer(verticalLineLayer!)
    }

    public func removeAndAddAnimate(with scrollValue: CGFloat, byScrollDirection type: IRScrollDirectionType) {
        var key: String?
        var lineLayer: CAShapeLayer?
        let startPath = getLinePath(withAmount: scrollValue, byScrollDirection: type)
        let endPath = getLinePath(withAmount: 0.0, byScrollDirection: type)

        switch type {
        case .left:
            key = "bounce_right"
            lineLayer = horizontalLineLayer
        case .right:
            key = "bounce_left"
            lineLayer = horizontalLineLayer
        case .up:
            key = "bounce_bottom"
            lineLayer = verticalLineLayer
        case .down:
            key = "bounce_top"
            lineLayer = verticalLineLayer
        default:
            return
        }

        lineLayer?.removeAnimation(forKey: key ?? "")
        lineLayer?.path = startPath.cgPath

        let morph = CABasicAnimation(keyPath: "path")
        morph.timingFunction = CAMediaTimingFunction(name: .easeIn)
        morph.fromValue = lineLayer?.path
        morph.toValue = endPath.cgPath
        morph.duration = 0.2
        morph.isRemovedOnCompletion = false
        morph.fillMode = .forwards
        lineLayer?.add(morph, forKey: key)
    }

    private func getLinePath(withAmount amount: CGFloat, byScrollDirection type: IRScrollDirectionType) -> UIBezierPath {
        let bounceWidth = min(targetViewWidth / 10, targetViewHeight / 10)
        var startPoint = CGPoint.zero
        var midControlPoint = CGPoint.zero
        var endPoint = CGPoint.zero

        switch type {
        case .left:
            startPoint = CGPoint(x: targetViewWidth, y: 0)
            midControlPoint = CGPoint(x: max(targetViewWidth + amount, targetViewWidth - bounceWidth), y: targetViewHeight / 2)
            endPoint = CGPoint(x: targetViewWidth, y: targetViewHeight)
        case .right:
            startPoint = .zero
            midControlPoint = CGPoint(x: min(amount, bounceWidth), y: targetViewHeight / 2)
            endPoint = CGPoint(x: 0, y: targetViewHeight)
        case .up:
            startPoint = CGPoint(x: 0, y: targetViewHeight)
            midControlPoint = CGPoint(x: targetViewWidth / 2, y: max(targetViewHeight + amount, targetViewHeight - bounceWidth))
            endPoint = CGPoint(x: targetViewWidth, y: targetViewHeight)
        case .down:
            startPoint = .zero
            midControlPoint = CGPoint(x: targetViewWidth / 2, y: min(amount, bounceWidth))
            endPoint = CGPoint(x: targetViewWidth, y: 0)
        default:
            return UIBezierPath()
        }

        let path = UIBezierPath()
        path.move(to: startPoint)
        path.addQuadCurve(to: endPoint, controlPoint: midControlPoint)
        path.close()

        return path
    }
}

