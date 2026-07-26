//
//  IRSmoothScrollController.swift
//  IRPlayer-swift
//
//  Created by irons on 2024/8/7.
//

import UIKit

protocol IRSmoothScrollBounceDriving: AnyObject {
    func install(on view: UIView)
    func animate(
        amount: CGFloat,
        direction: IRScrollDirectionType
    )
}

extension IRBounceController: IRSmoothScrollBounceDriving {
    func install(on view: UIView) {
        addBounceToView(view)
    }

    func animate(
        amount: CGFloat,
        direction: IRScrollDirectionType
    ) {
        removeAndAddAnimate(
            with: amount,
            byScrollDirection: direction
        )
    }
}

struct IRSmoothScrollDependencies {
    let displayLink:
        any IRDisplayLinkDriving
    let bounce: any IRSmoothScrollBounceDriving
    let screenScale: () -> CGFloat

    static func system() -> IRSmoothScrollDependencies {
        IRSmoothScrollDependencies(
            displayLink:
                IRSystemDisplayLinkDriver(),
            bounce: IRBounceController(),
            screenScale: { UIScreen.main.scale }
        )
    }
}

struct IRSmoothScrollDiagnostics: Equatable {
    let isClosed: Bool
    let isDisplayLinkInstalled: Bool
    let displayLink:
        IRDisplayLinkSnapshot
    let animation: IRSmoothScrollSnapshot
    let hasTargetView: Bool
    let hasCurrentMode: Bool
    let hasDelegate: Bool
}

@objcMembers public class IRSmoothScrollController: NSObject {
    weak var delegate: IRGLViewDelegate?
    var currentMode: IRGLRenderMode?
    private(set) weak var targetView: IRGLView?

    var isPaned: Bool {
        get { session.snapshot.isPaned }
        set { session.setPaned(newValue) }
    }

    private let dependencies: IRSmoothScrollDependencies
    private let session = IRSmoothScrollSession()
    private var isDisplayLinkInstalled = false
    private var isClosed = false

    var diagnostics: IRSmoothScrollDiagnostics {
        IRSmoothScrollDiagnostics(
            isClosed: isClosed,
            isDisplayLinkInstalled:
                isDisplayLinkInstalled,
            displayLink:
                dependencies.displayLink.snapshot,
            animation: session.snapshot,
            hasTargetView: targetView != nil,
            hasCurrentMode: currentMode != nil,
            hasDelegate: delegate != nil
        )
    }

    convenience init(targetView: IRGLView) {
        self.init(
            targetView: targetView,
            dependencies: .system()
        )
    }

    init(
        targetView: IRGLView,
        dependencies: IRSmoothScrollDependencies
    ) {
        self.targetView = targetView
        self.dependencies = dependencies
        super.init()

        dependencies.bounce.install(on: targetView)
        isDisplayLinkInstalled =
            dependencies.displayLink.install {
                [weak self] timestamp in
                self?.tick(timestamp: timestamp)
            }
    }

    deinit {
        _ = close()
    }

    @discardableResult
    func close() -> Bool {
        guard !isClosed else {
            return false
        }
        isClosed = true
        _ = session.reset()
        _ = dependencies.displayLink.close()
        isDisplayLinkInstalled = false
        delegate = nil
        currentMode = nil
        targetView = nil
        return true
    }

    func resetSmoothScroll() {
        _ = session.reset()
        _ = dependencies.displayLink.setActive(false)
    }

    @discardableResult
    func calculateSmoothScroll(
        velocity: CGPoint
    ) -> Bool {
        guard !isClosed,
              session.start(velocity: velocity) else {
            _ = dependencies.displayLink.setActive(false)
            return false
        }
        return activateDisplayLinkOrReset()
    }

    func scrollBy(dx: Float, dy: Float) {
        guard !isClosed,
              dx.isFinite,
              dy.isFinite else {
            return
        }
        targetView?.scroll(byDx: dx, dy: dy)
    }

    public func shiftDegreeX(
        _ degreeX: Float,
        degreeY: Float
    ) {
        guard !isClosed,
              session.startDegreeShift(
                  degreeX: degreeX,
                  degreeY: degreeY
              ) else {
            _ = dependencies.displayLink.setActive(false)
            return
        }
        _ = activateDisplayLinkOrReset()
    }

    static func smoothScrollTarget(
        for velocity: CGPoint
    ) -> (point: CGPoint, duration: CGFloat) {
        IRSmoothScrollSession.smoothScrollTarget(
            for: velocity
        )
    }

    private func tick(timestamp: TimeInterval) {
        guard !isClosed,
              let tick = session.advance(
                  timestamp: timestamp
              ) else {
            _ = dependencies.displayLink.setActive(false)
            return
        }
        if tick.isPaned {
            let configuredScale = dependencies.screenScale()
            let scale =
                configuredScale.isFinite
                    && configuredScale > 0
                ? configuredScale
                : 1
            targetView?.scroll(
                byDx: Float(tick.move.x * scale),
                dy: Float(-tick.move.y * scale)
            )
        } else {
            currentMode?.shiftController.shiftDegreeX(
                Float(tick.move.x),
                degreeY: -Float(tick.move.y)
            )
            targetView?.render(nil)
        }

        if tick.isFinished, tick.isPaned {
            delegate?.glViewDidEndDecelerating(
                targetView
            )
        }
        if tick.isFinished {
            _ = dependencies.displayLink.setActive(false)
        }
    }

    private func activateDisplayLinkOrReset() -> Bool {
        guard isDisplayLinkInstalled,
              dependencies.displayLink
                .setActive(true) else {
            _ = session.reset()
            return false
        }
        return true
    }
}

extension IRSmoothScrollController: IRGLProgramDelegate {
    func didScrollToBounds(
        _ bounds:
            IRGLTransformController.ScrollToBounds,
        withProgram program: IRGLProgram2D
    ) {
        let requests = session.admitBounds(bounds)
        if let horizontal = requests.horizontal {
            dependencies.bounce.animate(
                amount: horizontal.amount,
                direction: horizontal.direction
            )
        }
        if let vertical = requests.vertical {
            dependencies.bounce.animate(
                amount: vertical.amount,
                direction: vertical.direction
            )
        }
        delegate?.glViewDidScroll(toBounds: targetView)
    }
}
