//
//  IRGLTransformController2D.swift
//  IRPlayer-swift
//
//  Metal-only implementation (OpenGL-free)
//

import Foundation
import simd

@objcMembers public class IRGLTransformController2D: IRGLTransformController {
    private var maxX0: Float = 0.0
    private var maxY0: Float = 0.0
    private var rW: Float = 1.0
    private var rH: Float = 1.0

    private var scope: IRGLScope2D
    private var modelviewProj: simd_float4x4 = IRMatrix4.makeOrtho(-1.0, 1.0, -1.0, 1.0, -1.0, 1.0)
    private var unitX: Float = 0
    private var unitY: Float = 0

    override var scopeRange: IRGLScopeRange? {
        didSet {
            scroll(degreeX: scopeRange?.defaultLng ?? 0, degreeY: scopeRange?.defaultLat ?? 0)
        }
    }
    override var scaleRange: IRGLScaleRange? {
        didSet {
            updateToDefault()
        }
    }

    init() {
        scope = IRGLScope2D()
        scope.w = 0
        scope.h = 0
        super.init()
    }

    public convenience init(viewportWidth: Int, viewportHeight: Int) {
        self.init()
        scope.w = viewportWidth
        scope.h = viewportHeight
    }

    override func getScope() -> IRGLScope2D {
        return scope
    }

    override func setupDefaultTransform(scaleX defaultTransformScaleX: Float, scaleY defaultTransformScaleY: Float) {
        self.defaultTransformScaleX = defaultTransformScaleX
        self.defaultTransformScaleY = defaultTransformScaleY

        let expandedScaleRange = IRGLTransform2DPolicy.expandedScaleRange(
            scaleRange,
            defaultScaleX: defaultTransformScaleX,
            defaultScaleY: defaultTransformScaleY
        )
        if expandedScaleRange.maxScaleX != scaleRange?.maxScaleX || expandedScaleRange.maxScaleY != scaleRange?.maxScaleY {
            scaleRange = expandedScaleRange
        }
    }

    override func getDefaultTransformScale() -> CGPoint {
        return CGPoint(x: CGFloat(defaultTransformScaleX), y: CGFloat(defaultTransformScaleY))
    }

    override func getModelViewProjectionMatrix() -> simd_float4x4 {
        return modelviewProj
    }

    override func updateToDefault() {
        update(fx: Float(scope.w) / 2.0, fy: Float(scope.h) / 2.0, sx: defaultTransformScaleX * (scaleRange?.defaultScaleX ?? 1.0), sy: defaultTransformScaleY * (scaleRange?.defaultScaleY ?? 1.0))
    }

    override func scroll(degreeX: Float, degreeY: Float) {
        let units = IRGLTransform2DPolicy.degreeScrollUnits(
            width: scope.w,
            height: scope.h,
            scaleX: scope.scaleX,
            scaleY: scope.scaleY,
            range: scopeRange
        )
        unitX = units.unitX
        unitY = units.unitY

        scroll(dx: degreeX * unitX, dy: degreeY * unitY)
    }

    override func update(fx: Float, fy: Float, sx: Float, sy: Float) {
        let scope2d = scope
        guard let decision = IRGLTransform2DPolicy.updateDecision(
            scope: IRGLTransform2DPolicy.Scope(
                width: scope2d.w,
                height: scope2d.h,
                scaleX: scope2d.scaleX,
                scaleY: scope2d.scaleY,
                offsetX: scope2d.offsetX,
                offsetY: scope2d.offsetY
            ),
            fx: fx,
            fy: fy,
            sx: sx,
            sy: sy,
            scaleRange: scaleRange
        ) else {
            return
        }

        rW = decision.rW
        rH = decision.rH
        maxX0 = decision.maxX0
        maxY0 = decision.maxY0
        scope2d.offsetX = decision.offsetX
        scope2d.offsetY = decision.offsetY
        scope2d.scaleX = decision.scaleX
        scope2d.scaleY = decision.scaleY

        updateVertices()
        print("\(scope2d.offsetX ) \(scope2d.offsetY ) \(scope2d.scaleX ) \(scope2d.scaleY )")
    }

    override func scroll(dx: Float, dy: Float) {
        guard let delegate = delegate else { return }

        let scope2d = scope
        guard let decision = IRGLTransform2DPolicy.scrollDecision(
            offsetX: scope2d.offsetX,
            offsetY: scope2d.offsetY,
            scaleX: scope2d.scaleX,
            scaleY: scope2d.scaleY,
            maxX0: maxX0,
            maxY0: maxY0,
            dx: dx,
            dy: dy
        ) else {
            return
        }
        let status = decision.status

        let doScrollHorizontal = delegate.doScrollHorizontal(status: status, transformController: self)
        let doScrollVertical = delegate.doScrollVertical(status: status, transformController: self)

        if doScrollHorizontal {
            scope2d.offsetX = decision.offsetX
        }
        if doScrollVertical {
            scope2d.offsetY = decision.offsetY
        }
        if doScrollHorizontal || doScrollVertical {
            updateVertices()
        }

        delegate.didScroll(status: status, transformController: self)
    }

    override func rotate(degree: Float) {
        // Not supported
    }

    override func reset() {
        scope.w = 0
        scope.h = 0
        rW = 1.0
        rH = 1.0
        scope.scaleX = 1.0
        scope.scaleY = 1.0
        scope.offsetX = 0.0
        scope.offsetY = 0.0
        maxX0 = 0.0
        maxY0 = 0.0
        defaultTransformScaleX = scope.scaleX
        defaultTransformScaleY = scope.scaleY
    }

    override func resetViewport(width w: Int, height h: Int, resetTransform: Bool) {
        let oldDefaultScaleX = defaultTransformScaleX
        let oldDefaultScaleY = defaultTransformScaleY

        if resetTransform {
            reset()
            scope.w = w
            scope.h = h
            updateToDefault()
        } else {
            guard w > 0, h > 0 else {
                reset()
                scope.w = w
                scope.h = h
                updateVertices()
                defaultTransformScaleX = oldDefaultScaleX
                defaultTransformScaleY = oldDefaultScaleY
                return
            }

            scope.w = w
            scope.h = h

            let oldRW = rW
            let oldRH = rH
            if let decision = IRGLTransform2DPolicy.resizeDecision(
                width: scope.w,
                height: scope.h,
                scaleX: scope.scaleX,
                scaleY: scope.scaleY,
                offsetX: scope.offsetX,
                offsetY: scope.offsetY,
                oldRW: oldRW,
                oldRH: oldRH
            ) {
                rW = decision.rW
                rH = decision.rH
                maxX0 = decision.maxX0
                maxY0 = decision.maxY0
                scope.offsetX = decision.offsetX
                scope.offsetY = decision.offsetY
            }

            updateVertices()
        }

        defaultTransformScaleX = oldDefaultScaleX
        defaultTransformScaleY = oldDefaultScaleY
    }

    override func updateVertices() {
        let scope2d = scope

        let tx = (scope2d.offsetX ) * rW * 2 + 1.0 - (scope2d.scaleX )
        let ty = (scope2d.offsetY ) * rH * 2 + 1.0 - (scope2d.scaleY )
        modelviewProj = IRMatrix4.makeTranslation(tx, ty, 0)
        modelviewProj = IRMatrix4.multiply(modelviewProj, IRMatrix4.makeScale(scope2d.scaleX, scope2d.scaleY, 1.0))
    }
}
