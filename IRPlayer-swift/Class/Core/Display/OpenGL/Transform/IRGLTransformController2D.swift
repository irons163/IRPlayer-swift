//
//  IRGLTransformController2D.swift
//  IRPlayer-swift
//
//  Created by irons on 2024/9/7.
//

import Foundation
import GLKit

@objcMembers public class IRGLTransformController2D: IRGLTransformController {
    private var maxX0: Float = 0.0
    private var maxY0: Float = 0.0
    private var rW: Float = 1.0
    private var rH: Float = 1.0

    private var scope: IRGLScope2D
    private var modelviewProj: GLKMatrix4 = GLKMatrix4MakeOrtho(-1.0, 1.0, -1.0, 1.0, -1.0, 1.0)
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
        scope.w = Int32(viewportWidth)
        scope.h = Int32(viewportHeight)
    }

    override func getScope() -> IRGLScope2D {
        return scope
    }

    override func setupDefaultTransform(scaleX defaultTransformScaleX: Float, scaleY defaultTransformScaleY: Float) {
        self.defaultTransformScaleX = defaultTransformScaleX
        self.defaultTransformScaleY = defaultTransformScaleY

        if defaultTransformScaleX > scaleRange?.maxScaleX ?? 1.0 {
            scaleRange = IRGLScaleRange(minScaleX: scaleRange?.minScaleX ?? 1.0, minScaleY: scaleRange?.minScaleY ?? 1.0, maxScaleX: defaultTransformScaleX, maxScaleY: scaleRange?.maxScaleY ?? 1.0, defaultScaleX: scaleRange?.defaultScaleX ?? 1.0, defaultScaleY: scaleRange?.defaultScaleY ?? 1.0)
        }

        if defaultTransformScaleY > scaleRange?.maxScaleY ?? 1.0 {
            scaleRange = IRGLScaleRange(minScaleX: scaleRange?.minScaleX ?? 1.0, minScaleY: scaleRange?.minScaleY ?? 1.0, maxScaleX: scaleRange?.maxScaleX ?? 1.0, maxScaleY: defaultTransformScaleY, defaultScaleX: scaleRange?.defaultScaleX ?? 1.0, defaultScaleY: scaleRange?.defaultScaleY ?? 1.0)
        }
    }

    override func getDefaultTransformScale() -> CGPoint {
        return CGPoint(x: CGFloat(defaultTransformScaleX), y: CGFloat(defaultTransformScaleY))
    }

    override func getModelViewProjectionMatrix() -> GLKMatrix4 {
        return modelviewProj
    }

    override func updateToDefault() {
        update(fx: Float(scope.w) / 2.0, fy: Float(scope.h) / 2.0, sx: defaultTransformScaleX * (scaleRange?.defaultScaleX ?? 1.0), sy: defaultTransformScaleY * (scaleRange?.defaultScaleY ?? 1.0))
    }

    override func scroll(degreeX: Float, degreeY: Float) {
        let maxContentOffsetX = Float(scope.w) * (scope.scaleX)
        let maxContentOffsetY = Float(scope.h) * (scope.scaleY)

        let wideDegreeX = scopeRange?.maxLng ?? 0 - (scopeRange?.minLng ?? 0)
        let wideDegreeY = scopeRange?.maxLat ?? 0 - (scopeRange?.minLat ?? 0)

        unitX = wideDegreeX == 0 ? 0 : (maxContentOffsetX) / wideDegreeX
        unitY = wideDegreeY == 0 ? 0 : (maxContentOffsetY) / wideDegreeY

        scroll(dx: degreeX * unitX, dy: degreeY * unitY)
    }

    override func update(fx: Float, fy: Float, sx: Float, sy: Float) {
        let scope2d = scope

        var scaleX = sx
        var scaleY = sy

        if scaleX < 1.0 && scaleY < 1.0 {
            if scaleX < scaleY {
                scaleY = 1.0
                scaleX = (scope2d.scaleX ) / ((scope2d.scaleY ) / scaleY)
            } else {
                scaleX = 1.0
                scaleY = (scope2d.scaleY ) / ((scope2d.scaleX ) / scaleX)
            }
        } else if scaleX > (scaleRange?.maxScaleX ?? 1.0) || scaleY > (scaleRange?.maxScaleY ?? 1.0) {
            if scaleX < scaleY {
                scaleY = scaleRange?.maxScaleY ?? 1.0
                scaleX = (scope2d.scaleX ) / ((scope2d.scaleY ) / scaleY)
            } else {
                scaleX = scaleRange?.maxScaleX ?? 1.0
                scaleY = (scope2d.scaleY ) / ((scope2d.scaleX ) / scaleX)
            }
        }

        var newX0 = (scope2d.offsetX ) + fx * (scaleX - (scope2d.scaleX )) / (scaleX * (scope2d.scaleX ))
        var newY0 = (scope2d.offsetY ) + fy * (scaleY - (scope2d.scaleY )) / (scaleY * (scope2d.scaleY ))

        rW = scaleX / Float(scope2d.w)
        rH = scaleY / Float(scope2d.h)

        maxX0 = scaleX >= 1.0 ? Float(scope2d.w) - 1 / rW : 0
        maxY0 = scaleY >= 1.0 ? Float(scope2d.h) - 1 / rH : 0

        newX0 = max(0, min(newX0, maxX0))
        newY0 = max(0, min(newY0, maxY0))

        scope2d.offsetX = newX0
        scope2d.offsetY = newY0
        scope2d.scaleX = scaleX
        scope2d.scaleY = scaleY

        updateVertices()
        print("\(scope2d.offsetX ) \(scope2d.offsetY ) \(scope2d.scaleX ) \(scope2d.scaleY )")
    }

    override func scroll(dx: Float, dy: Float) {
        guard let delegate = delegate else { return }

        let scope2d = scope
        var status: IRGLTransformController.ScrollStatus = []

        var newX0 = (scope2d.offsetX ) + dx / (scope2d.scaleX )
        var newY0 = (scope2d.offsetY ) + dy / (scope2d.scaleY )

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

        let doScrollHorizontal = delegate.doScrollHorizontal(status: status, transformController: self)
        let doScrollVertical = delegate.doScrollVertical(status: status, transformController: self)

        if doScrollHorizontal {
            scope2d.offsetX = newX0
        }
        if doScrollVertical {
            scope2d.offsetY = newY0
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
            scope.w = Int32(w)
            scope.h = Int32(h)
            updateToDefault()
        } else {
            scope.w = Int32(w)
            scope.h = Int32(h)

            let oldRW = rW
            let oldRH = rH
            rW = (scope.scaleX ) / Float(scope.w )
            rH = (scope.scaleY ) / Float(scope.h )

            maxX0 = (scope.scaleX ) >= 1.0 ? Float(scope.w ) - 1 / rW : 0
            maxY0 = (scope.scaleY ) >= 1.0 ? Float(scope.h ) - 1 / rH : 0

            scope.offsetX = (scope.offsetX ) * (oldRW / rW)
            scope.offsetY = (scope.offsetY ) * (oldRH / rH)

            updateVertices()
        }
    }

    override func updateVertices() {
        let scope2d = scope

        modelviewProj = GLKMatrix4MakeTranslation((scope2d.offsetX ) * rW * 2 + 1.0 - (scope2d.scaleX ), (scope2d.offsetY ) * rH * 2 + 1.0 - (scope2d.scaleY ), 0)
        modelviewProj = GLKMatrix4Scale(modelviewProj, scope2d.scaleX , scope2d.scaleY , 1.0)
    }
}

