import Foundation

enum IRGLTransform2DPolicy {
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
        let status: IRGLTransformController.ScrollStatus
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
    ) -> IRGLScaleRange {
        let old = range ?? IRGLScaleRange(minScaleX: 1.0, minScaleY: 1.0, maxScaleX: 1.0, maxScaleY: 1.0, defaultScaleX: 1.0, defaultScaleY: 1.0)
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
    ) -> DegreeScrollUnits {
        let maxContentOffsetX = Float(width) * scaleX
        let maxContentOffsetY = Float(height) * scaleY
        let wideDegreeX = range?.wideDegreeX ?? 0
        let wideDegreeY = range?.wideDegreeY ?? 0
        let unitX = wideDegreeX == 0 ? 0 : maxContentOffsetX / wideDegreeX
        let unitY = wideDegreeY == 0 ? 0 : maxContentOffsetY / wideDegreeY
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
        guard scope.width > 0, scope.height > 0 else { return nil }
        guard fx.isFinite, fy.isFinite else { return nil }
        guard sx.isFinite, sy.isFinite, sx > 0, sy > 0 else { return nil }
        guard scope.scaleX.isFinite, scope.scaleY.isFinite, scope.scaleX > 0, scope.scaleY > 0 else { return nil }
        guard scope.offsetX.isFinite, scope.offsetY.isFinite else { return nil }

        var scaleX = sx
        var scaleY = sy

        if scaleX < 1.0 && scaleY < 1.0 {
            if scaleX < scaleY {
                scaleY = 1.0
                scaleX = scope.scaleX / (scope.scaleY / scaleY)
            } else {
                scaleX = 1.0
                scaleY = scope.scaleY / (scope.scaleX / scaleX)
            }
        } else if scaleX > (scaleRange?.maxScaleX ?? 1.0) || scaleY > (scaleRange?.maxScaleY ?? 1.0) {
            if scaleX < scaleY {
                scaleY = scaleRange?.maxScaleY ?? 1.0
                scaleX = scope.scaleX / (scope.scaleY / scaleY)
            } else {
                scaleX = scaleRange?.maxScaleX ?? 1.0
                scaleY = scope.scaleY / (scope.scaleX / scaleX)
            }
        }

        guard scaleX.isFinite, scaleY.isFinite, scaleX > 0, scaleY > 0 else { return nil }

        var newX0 = scope.offsetX + fx * (scaleX - scope.scaleX) / (scaleX * scope.scaleX)
        var newY0 = scope.offsetY + fy * (scaleY - scope.scaleY) / (scaleY * scope.scaleY)

        let rW = scaleX / Float(scope.width)
        let rH = scaleY / Float(scope.height)
        guard rW.isFinite, rH.isFinite, rW > 0, rH > 0 else { return nil }

        let maxX0 = scaleX >= 1.0 ? Float(scope.width) - 1 / rW : 0
        let maxY0 = scaleY >= 1.0 ? Float(scope.height) - 1 / rH : 0

        newX0 = max(0, min(newX0, maxX0))
        newY0 = max(0, min(newY0, maxY0))

        return UpdateDecision(scaleX: scaleX, scaleY: scaleY, offsetX: newX0, offsetY: newY0, rW: rW, rH: rH, maxX0: maxX0, maxY0: maxY0)
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
        guard offsetX.isFinite, offsetY.isFinite,
              scaleX.isFinite, scaleY.isFinite, scaleX > 0, scaleY > 0,
              maxX0.isFinite, maxY0.isFinite,
              dx.isFinite, dy.isFinite else {
            return nil
        }

        var status: IRGLTransformController.ScrollStatus = []
        var newX0 = offsetX + dx / scaleX
        var newY0 = offsetY + dy / scaleY

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

        return ScrollDecision(offsetX: newX0, offsetY: newY0, status: status)
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
        guard width > 0, height > 0 else { return nil }
        guard scaleX.isFinite, scaleY.isFinite, scaleX > 0, scaleY > 0,
              offsetX.isFinite, offsetY.isFinite,
              oldRW.isFinite, oldRH.isFinite else {
            return nil
        }

        let rW = scaleX / Float(width)
        let rH = scaleY / Float(height)
        guard rW.isFinite, rH.isFinite, rW > 0, rH > 0 else { return nil }

        let maxX0 = scaleX >= 1.0 ? Float(width) - 1 / rW : 0
        let maxY0 = scaleY >= 1.0 ? Float(height) - 1 / rH : 0
        let newOffsetX = offsetX * (oldRW / rW)
        let newOffsetY = offsetY * (oldRH / rH)

        return ResizeDecision(offsetX: newOffsetX, offsetY: newOffsetY, rW: rW, rH: rH, maxX0: maxX0, maxY0: maxY0)
    }
}
