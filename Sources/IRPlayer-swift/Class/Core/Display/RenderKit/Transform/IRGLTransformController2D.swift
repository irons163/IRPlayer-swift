//
//  IRGLTransformController2D.swift
//  IRPlayer-swift
//
//  Metal-only implementation (OpenGL-free)
//

import Foundation
import simd

@objcMembers public class IRGLTransformController2D: IRGLTransformController {
    struct Scope: Equatable {
        let width: Int
        let height: Int
        let scaleX: Float
        let scaleY: Float
        let offsetX: Float
        let offsetY: Float
    }

    struct DegreeScrollUnits: Equatable {
        let unitX: Float
        let unitY: Float
    }

    struct UpdateDecision: Equatable {
        let scaleX: Float
        let scaleY: Float
        let offsetX: Float
        let offsetY: Float
        let rW: Float
        let rH: Float
        let maxX0: Float
        let maxY0: Float
    }

    struct ScrollDecision: Equatable {
        let offsetX: Float
        let offsetY: Float
        let status: ScrollStatus
    }

    struct ResizeDecision: Equatable {
        let offsetX: Float
        let offsetY: Float
        let rW: Float
        let rH: Float
        let maxX0: Float
        let maxY0: Float
    }

    static func expandedScaleRange(
        _ range: IRGLScaleRange?,
        defaultScaleX: Float,
        defaultScaleY: Float
    ) -> IRGLScaleRange? {
        guard defaultScaleX.isFinite,
              defaultScaleY.isFinite,
              defaultScaleX > 0,
              defaultScaleY > 0 else {
            return nil
        }

        let old = range ?? IRGLScaleRange(
            minScaleX: 1,
            minScaleY: 1,
            maxScaleX: 1,
            maxScaleY: 1,
            defaultScaleX: 1,
            defaultScaleY: 1
        )
        guard old.minScaleX.isFinite,
              old.minScaleY.isFinite,
              old.maxScaleX.isFinite,
              old.maxScaleY.isFinite,
              old.defaultScaleX.isFinite,
              old.defaultScaleY.isFinite,
              old.minScaleX > 0,
              old.minScaleY > 0,
              old.maxScaleX >= old.minScaleX,
              old.maxScaleY >= old.minScaleY,
              old.defaultScaleX > 0,
              old.defaultScaleY > 0 else {
            return nil
        }

        return IRGLScaleRange(
            minScaleX: old.minScaleX,
            minScaleY: old.minScaleY,
            maxScaleX: max(old.maxScaleX, defaultScaleX),
            maxScaleY: max(old.maxScaleY, defaultScaleY),
            defaultScaleX: old.defaultScaleX,
            defaultScaleY: old.defaultScaleY
        )
    }

    static func degreeScrollUnits(
        width: Int,
        height: Int,
        scaleX: Float,
        scaleY: Float,
        range: IRGLScopeRange?
    ) -> DegreeScrollUnits? {
        guard width > 0,
              height > 0,
              scaleX.isFinite,
              scaleY.isFinite,
              scaleX > 0,
              scaleY > 0 else {
            return nil
        }
        guard let range else {
            return DegreeScrollUnits(unitX: 0, unitY: 0)
        }
        guard range.minLat.isFinite,
              range.maxLat.isFinite,
              range.minLng.isFinite,
              range.maxLng.isFinite,
              range.minLat <= range.maxLat,
              range.minLng <= range.maxLng else {
            return nil
        }

        let contentWidth = Float(width) * scaleX
        let contentHeight = Float(height) * scaleY
        let wideDegreeX = range.maxLng - range.minLng
        let wideDegreeY = range.maxLat - range.minLat
        guard contentWidth.isFinite,
              contentHeight.isFinite,
              wideDegreeX.isFinite,
              wideDegreeY.isFinite else {
            return nil
        }

        let unitX = wideDegreeX == 0 ? 0 : contentWidth / wideDegreeX
        let unitY = wideDegreeY == 0 ? 0 : contentHeight / wideDegreeY
        guard unitX.isFinite, unitY.isFinite else { return nil }
        return DegreeScrollUnits(unitX: unitX, unitY: unitY)
    }

    static func updateDecision(
        scope: Scope,
        fx: Float,
        fy: Float,
        sx: Float,
        sy: Float,
        scaleRange: IRGLScaleRange?
    ) -> UpdateDecision? {
        guard scope.width > 0, scope.height > 0,
              fx.isFinite, fy.isFinite,
              sx.isFinite, sy.isFinite, sx > 0, sy > 0,
              scope.scaleX.isFinite,
              scope.scaleY.isFinite,
              scope.scaleX > 0,
              scope.scaleY > 0,
              scope.offsetX.isFinite,
              scope.offsetY.isFinite else {
            return nil
        }

        let maxScaleX: Float
        let maxScaleY: Float
        if let scaleRange {
            guard scaleRange.minScaleX.isFinite,
                  scaleRange.minScaleY.isFinite,
                  scaleRange.maxScaleX.isFinite,
                  scaleRange.maxScaleY.isFinite,
                  scaleRange.maxScaleX >= scaleRange.minScaleX,
                  scaleRange.maxScaleY >= scaleRange.minScaleY,
                  scaleRange.minScaleX > 0,
                  scaleRange.minScaleY > 0 else {
                return nil
            }
            maxScaleX = scaleRange.maxScaleX
            maxScaleY = scaleRange.maxScaleY
        } else {
            maxScaleX = 1
            maxScaleY = 1
        }

        var scaleX = sx
        var scaleY = sy
        if scaleX < 1, scaleY < 1 {
            if scaleX < scaleY {
                scaleY = 1
                scaleX = scope.scaleX / scope.scaleY
            } else {
                scaleX = 1
                scaleY = scope.scaleY / scope.scaleX
            }
        } else if scaleX > maxScaleX || scaleY > maxScaleY {
            if scaleX < scaleY {
                scaleY = maxScaleY
                scaleX = scope.scaleX / scope.scaleY * scaleY
            } else {
                scaleX = maxScaleX
                scaleY = scope.scaleY / scope.scaleX * scaleX
            }
        }
        guard scaleX.isFinite,
              scaleY.isFinite,
              scaleX > 0,
              scaleY > 0 else {
            return nil
        }

        let denominatorX = scaleX * scope.scaleX
        let denominatorY = scaleY * scope.scaleY
        let scaleDeltaX = scaleX - scope.scaleX
        let scaleDeltaY = scaleY - scope.scaleY
        guard denominatorX.isFinite,
              denominatorY.isFinite,
              denominatorX > 0,
              denominatorY > 0,
              scaleDeltaX.isFinite,
              scaleDeltaY.isFinite else {
            return nil
        }

        var newX0 =
            scope.offsetX + fx * scaleDeltaX / denominatorX
        var newY0 =
            scope.offsetY + fy * scaleDeltaY / denominatorY
        let rW = scaleX / Float(scope.width)
        let rH = scaleY / Float(scope.height)
        guard newX0.isFinite,
              newY0.isFinite,
              rW.isFinite,
              rH.isFinite,
              rW > 0,
              rH > 0 else {
            return nil
        }

        let inverseRW = 1 / rW
        let inverseRH = 1 / rH
        let maxX0 =
            scaleX >= 1 ? Float(scope.width) - inverseRW : 0
        let maxY0 =
            scaleY >= 1 ? Float(scope.height) - inverseRH : 0
        guard inverseRW.isFinite,
              inverseRH.isFinite,
              maxX0.isFinite,
              maxY0.isFinite,
              maxX0 >= 0,
              maxY0 >= 0 else {
            return nil
        }

        newX0 = max(0, min(newX0, maxX0))
        newY0 = max(0, min(newY0, maxY0))
        return UpdateDecision(
            scaleX: scaleX,
            scaleY: scaleY,
            offsetX: newX0,
            offsetY: newY0,
            rW: rW,
            rH: rH,
            maxX0: maxX0,
            maxY0: maxY0
        )
    }

    static func scrollDecision(
        offsetX: Float,
        offsetY: Float,
        scaleX: Float,
        scaleY: Float,
        maxX0: Float,
        maxY0: Float,
        dx: Float,
        dy: Float
    ) -> ScrollDecision? {
        guard offsetX.isFinite,
              offsetY.isFinite,
              scaleX.isFinite,
              scaleY.isFinite,
              scaleX > 0,
              scaleY > 0,
              maxX0.isFinite,
              maxY0.isFinite,
              maxX0 >= 0,
              maxY0 >= 0,
              dx.isFinite,
              dy.isFinite else {
            return nil
        }

        var newX0 = offsetX + dx / scaleX
        var newY0 = offsetY + dy / scaleY
        guard newX0.isFinite, newY0.isFinite else { return nil }

        var status: ScrollStatus = []
        if newX0 < 0 {
            newX0 = 0
            status.insert(.toMinX)
        } else if newX0 > maxX0 {
            newX0 = maxX0
            status.insert(.toMaxX)
        }
        if newY0 < 0 {
            newY0 = 0
            status.insert(.toMinY)
        } else if newY0 > maxY0 {
            newY0 = maxY0
            status.insert(.toMaxY)
        }
        return ScrollDecision(
            offsetX: newX0,
            offsetY: newY0,
            status: status
        )
    }

    static func resizeDecision(
        width: Int,
        height: Int,
        scaleX: Float,
        scaleY: Float,
        offsetX: Float,
        offsetY: Float,
        oldRW: Float,
        oldRH: Float
    ) -> ResizeDecision? {
        guard width > 0,
              height > 0,
              scaleX.isFinite,
              scaleY.isFinite,
              scaleX > 0,
              scaleY > 0,
              offsetX.isFinite,
              offsetY.isFinite,
              oldRW.isFinite,
              oldRH.isFinite,
              oldRW > 0,
              oldRH > 0 else {
            return nil
        }

        let rW = scaleX / Float(width)
        let rH = scaleY / Float(height)
        guard rW.isFinite,
              rH.isFinite,
              rW > 0,
              rH > 0 else {
            return nil
        }

        let inverseRW = 1 / rW
        let inverseRH = 1 / rH
        let maxX0 =
            scaleX >= 1 ? Float(width) - inverseRW : 0
        let maxY0 =
            scaleY >= 1 ? Float(height) - inverseRH : 0
        let scaledOffsetX = offsetX * (oldRW / rW)
        let scaledOffsetY = offsetY * (oldRH / rH)
        guard inverseRW.isFinite,
              inverseRH.isFinite,
              maxX0.isFinite,
              maxY0.isFinite,
              maxX0 >= 0,
              maxY0 >= 0,
              scaledOffsetX.isFinite,
              scaledOffsetY.isFinite else {
            return nil
        }

        return ResizeDecision(
            offsetX: max(0, min(scaledOffsetX, maxX0)),
            offsetY: max(0, min(scaledOffsetY, maxY0)),
            rW: rW,
            rH: rH,
            maxX0: maxX0,
            maxY0: maxY0
        )
    }

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

        guard let expandedScaleRange = Self.expandedScaleRange(
            scaleRange,
            defaultScaleX: defaultTransformScaleX,
            defaultScaleY: defaultTransformScaleY
        ) else {
            return
        }
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
        guard let units = Self.degreeScrollUnits(
            width: scope.w,
            height: scope.h,
            scaleX: scope.scaleX,
            scaleY: scope.scaleY,
            range: scopeRange
        ) else {
            return
        }
        unitX = units.unitX
        unitY = units.unitY

        scroll(dx: degreeX * unitX, dy: degreeY * unitY)
    }

    override func update(fx: Float, fy: Float, sx: Float, sy: Float) {
        let scope2d = scope
        guard let decision = Self.updateDecision(
            scope: Scope(
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
    }

    override func scroll(dx: Float, dy: Float) {
        guard let delegate = delegate else { return }
        delegate.willScroll(dx: dx, dy: dy, transformController: self)

        let scope2d = scope
        guard let decision = Self.scrollDecision(
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
            if let decision = Self.resizeDecision(
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
        guard tx.isFinite,
              ty.isFinite,
              scope2d.scaleX.isFinite,
              scope2d.scaleY.isFinite else {
            return
        }
        modelviewProj = IRMatrix4.makeTranslation(tx, ty, 0)
        modelviewProj = IRMatrix4.multiply(modelviewProj, IRMatrix4.makeScale(scope2d.scaleX, scope2d.scaleY, 1.0))
    }
}
