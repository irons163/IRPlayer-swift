//
//  IRGLTransformController3DFisheye.swift
//  IRPlayer-swift
//
//  Metal-only implementation (OpenGL-free)
//

import Foundation
import simd

class IRGLTransformController3DFisheye: IRGLTransformController {
    struct NormalizedScope: Equatable {
        let lat: Float
        let lng: Float
    }

    struct ScrollDecision: Equatable {
        let lat: Float
        let lng: Float
        let status: ScrollStatus
    }

    struct ScaleDecision: Equatable {
        let scale: Float
        let fovDegrees: Float
    }

    static func scopeRange(
        for type: IRGLScope3D.TiltType
    ) -> IRGLScopeRange {
        switch type {
        case .up:
            return IRGLScopeRange(
                minLat: -80,
                maxLat: 80,
                minLng: -75,
                maxLng: 75,
                defaultLat: 0,
                defaultLng: 0
            )
        case .toward:
            return IRGLScopeRange(
                minLat: 0,
                maxLat: 80,
                minLng: -180,
                maxLng: 180,
                defaultLat: 80,
                defaultLng: -90
            )
        case .backward:
            return IRGLScopeRange(
                minLat: -85,
                maxLat: -20,
                minLng: -180,
                maxLng: 180,
                defaultLat: -80,
                defaultLng: 90
            )
        default:
            return IRGLScopeRange(
                minLat: 0,
                maxLat: 0,
                minLng: 0,
                maxLng: 0,
                defaultLat: 0,
                defaultLng: 0
            )
        }
    }

    static func aspectRatio(width: Int, height: Int) -> Float {
        guard width > 0, height > 0 else { return 1 }
        let ratio = Float(width) / Float(height)
        return ratio.isFinite && ratio > 0 ? ratio : 1
    }

    static func scaleDecision(
        requestedScale: Float,
        maxScale: Float,
        tanbase: Float
    ) -> ScaleDecision? {
        guard requestedScale.isFinite,
              maxScale.isFinite,
              tanbase.isFinite,
              requestedScale > 0,
              maxScale >= 1,
              tanbase > 0 else {
            return nil
        }

        let scale = min(max(requestedScale, 1), maxScale)
        let newFov = atan(Double(tanbase) / Double(scale)) * 2
        let fovDegrees = Float(newFov * (180 / .pi))
        guard fovDegrees.isFinite, fovDegrees > 0 else { return nil }
        return ScaleDecision(scale: scale, fovDegrees: fovDegrees)
    }

    static func scrollDecision(
        currentLat: Float,
        currentLng: Float,
        dx: Float,
        dy: Float,
        friction: Float,
        range: IRGLScopeRange?
    ) -> ScrollDecision? {
        guard currentLat.isFinite,
              currentLng.isFinite,
              dx.isFinite,
              dy.isFinite,
              friction.isFinite,
              friction >= 0 else {
            return nil
        }

        let lngDelta = dx * friction
        let latDelta = dy * friction
        let nextLng = currentLng - lngDelta
        let nextLat = currentLat - latDelta
        guard lngDelta.isFinite,
              latDelta.isFinite,
              nextLng.isFinite,
              nextLat.isFinite else {
            return nil
        }

        var status: ScrollStatus = []
        if let range {
            guard range.minLat.isFinite,
                  range.maxLat.isFinite,
                  range.minLng.isFinite,
                  range.maxLng.isFinite,
                  range.minLat <= range.maxLat,
                  range.minLng <= range.maxLng else {
                return nil
            }
            if nextLng >= range.maxLng {
                status.insert(.toMaxX)
            } else if nextLng <= range.minLng {
                status.insert(.toMinX)
            }
            if nextLat >= range.maxLat {
                status.insert(.toMaxY)
            } else if nextLat <= range.minLat {
                status.insert(.toMinY)
            }
        }

        return ScrollDecision(
            lat: nextLat,
            lng: nextLng,
            status: status
        )
    }

    static func normalizedScope(
        lat: Float,
        lng: Float,
        fov: Float,
        range: IRGLScopeRange?
    ) -> NormalizedScope? {
        guard lat.isFinite,
              lng.isFinite,
              fov.isFinite,
              fov >= 0 else {
            return nil
        }

        guard let effectiveRange = range else {
            return NormalizedScope(lat: 0, lng: 0)
        }
        guard effectiveRange.minLat.isFinite,
              effectiveRange.maxLat.isFinite,
              effectiveRange.minLng.isFinite,
              effectiveRange.maxLng.isFinite,
              effectiveRange.minLat <= effectiveRange.maxLat,
              effectiveRange.minLng <= effectiveRange.maxLng else {
            return nil
        }

        var normalizedLat =
            lat.truncatingRemainder(dividingBy: 180)
        if normalizedLat > 90 {
            normalizedLat -= 180
        } else if normalizedLat <= -90 {
            normalizedLat += 180
        }

        let halfFov = fov / 2
        let upperLat = effectiveRange.maxLat - halfFov
        guard normalizedLat.isFinite,
              halfFov.isFinite,
              upperLat.isFinite,
              upperLat >= effectiveRange.minLat else {
            return nil
        }
        normalizedLat = max(
            effectiveRange.minLat,
            min(upperLat, normalizedLat)
        )

        var normalizedLng =
            lng.truncatingRemainder(dividingBy: 360)
        if normalizedLng > 180 {
            normalizedLng -= 360
        } else if normalizedLng <= -180 {
            normalizedLng += 360
        }
        guard normalizedLng.isFinite else { return nil }
        normalizedLng = max(
            effectiveRange.minLng,
            min(effectiveRange.maxLng, normalizedLng)
        )
        return NormalizedScope(lat: normalizedLat, lng: normalizedLng)
    }

    var camera: [Float] = [0, 0, 0]
    var rc: Float = 0
    var fov: Float = 0
    var tanbase: Float = 0
    var projectMatrix = IRMatrix4.identity()
    var modelMatrix = IRMatrix4.identity()
    var viewMatrix = IRMatrix4.identity()

    private var scope: IRGLScope3D
    private var defaultType: IRGLScope3D.TiltType = .unknown
    override var scopeRange: IRGLScopeRange? {
        didSet {
            scope.lat = scopeRange?.defaultLat ?? 0
            scope.lng = scopeRange?.defaultLng ?? 0
            setupScope(getScope().tiltType, degree: getScope().panDegree, lat: getScope().lat, lng: getScope().lng, sx: getScope().scaleX, sy: getScope().scaleY)
            updateVertices()
        }
    }
    override var scaleRange: IRGLScaleRange? {
        didSet {
            updateToDefault()
        }
    }

    let CAMERA_RADIUS: Float = 120.0
    let DEFAULT_FOV: Float = 60.0
    let DRAG_FRICTION: Float = 0.15
    let INITIAL_PITCH_DEGREES: Float = 0

    init(viewportWidth width: Int, viewportHeight height: Int, tileType type: IRGLScope3D.TiltType) {
        defaultType = type
        scope = IRGLScope3D()
        scope.tiltType = defaultType
        let scopeRange = IRGLTransformController3DFisheye.getScopeRange(of: scope.tiltType )
        super.init(scopeRange: scopeRange)

        scope.w = width
        scope.h = height

        let aspectRatio = Self.aspectRatio(width: width, height: height)
        let fovyRadians = fov * .pi / 180.0
        projectMatrix = IRMatrix4.makePerspective(fovyRadians, aspectRatio, 1.0, 1000.0)
        viewMatrix = IRMatrix4.identity()

        setupTilt(scope.tiltType )

        rc = CAMERA_RADIUS
        fov = DEFAULT_FOV
        tanbase = tan(fov / 2 * .pi / 180.0)

        resetViewport(width: width, height: height, resetTransform: true)
    }

    override func getScope() -> IRGLScope3D {
        return scope
    }

    class func getScopeRange(of type: IRGLScope3D.TiltType) -> IRGLScopeRange {
        return scopeRange(for: type)
    }

    override func getModelViewProjectionMatrix() -> simd_float4x4 {
        let mv = IRMatrix4.multiply(viewMatrix, modelMatrix)
        let mvp = IRMatrix4.multiply(projectMatrix, mv)
        return mvp
    }

    override func getDefaultTransformScale() -> CGPoint {
        return CGPoint(x: CGFloat(defaultTransformScaleX), y: CGFloat(defaultTransformScaleY))
    }

    override func updateToDefault() {
        updateBy(fx: 0, fy: 0, sx: defaultTransformScaleX * (scaleRange?.defaultScaleX ?? 1), sy: defaultTransformScaleY * (scaleRange?.defaultScaleY ?? 1), renew: false)
    }

    override func scroll(degreeX: Float, degreeY: Float) {
        scroll(dx: degreeX / DRAG_FRICTION, dy: degreeY / DRAG_FRICTION)
    }

    override func update(fx: Float, fy: Float, sx: Float, sy: Float) {
        updateBy(fx: fx, fy: fy, sx: sx, sy: sy, renew: false)
    }

    func updateBy(fx: Float, fy: Float, sx: Float, sy: Float, renew: Bool) {
        guard sy.isFinite, sy > 0,
              let decision = Self.scaleDecision(
                requestedScale: sx,
                maxScale: scaleRange?.maxScaleX ?? 1,
                tanbase: tanbase
              ) else {
            return
        }

        let oldScale = scope.scaleX 
        scope.scaleX = decision.scale
        scope.scaleY = decision.scale

        if oldScale != scope.scaleX {
            fov = decision.fovDegrees
            let aspectRatio = Self.aspectRatio(width: scope.w, height: scope.h)
            let fovyRadians = fov * .pi / 180.0
            projectMatrix = IRMatrix4.makePerspective(fovyRadians, aspectRatio, 1.0, 1000.0)
            updateVertices()
        } else if renew {
            updateVertices()
        }
    }

    override func scroll(dx: Float, dy: Float) {
        guard let decision = Self.scrollDecision(
            currentLat: scope.lat,
            currentLng: scope.lng,
            dx: dx,
            dy: dy,
            friction: DRAG_FRICTION,
            range: scopeRange
        ) else {
            return
        }

        let oldLng = scope.lng
        let oldLat = scope.lat

        scope.lng = decision.lng
        scope.lat = decision.lat
        var status = decision.status

        var doScrollHorizontal = true
        var doScrollVertical = true

        if let delegate = delegate {
            doScrollHorizontal = delegate.doScrollHorizontal(status: status, transformController: self)
            doScrollVertical = delegate.doScrollVertical(status: status, transformController: self)

            if !doScrollHorizontal {
                status.remove([.toMinX, .toMaxX])
                scope.lng = oldLng
            }
            if !doScrollVertical {
                status.remove([.toMinY, .toMaxY])
                scope.lat = oldLat
            }
        }

        if doScrollHorizontal || doScrollVertical {
            updateVertices()
        }

        delegate?.didScroll(status: status, transformController: self)
    }

    override func rotate(degree: Float) {
        guard scope.tiltType == .up, degree.isFinite else { return }
        let totalDegree = (scope.panDegree ) + degree
        guard totalDegree.isFinite else { return }
        setupScope(scope.tiltType, degree: totalDegree, lat: scope.lat , lng: scope.lng , sx: scope.scaleX , sy: scope.scaleY )
    }

    func setupTilt(_ type: IRGLScope3D.TiltType) {
        switch type {
        case .up:
            modelMatrix = IRMatrix4.makeRotation(INITIAL_PITCH_DEGREES * .pi / 180.0, 1, 0, 0)
        case .toward:
            modelMatrix = IRMatrix4.makeRotation(-90 * .pi / 180.0, 0, 0, 1)
        case .backward:
            modelMatrix = IRMatrix4.makeRotation(90 * .pi / 180.0, 0, 0, 1)
        default:
            break
        }
        scope.tiltType = type
    }

    func setupScope(_ type: IRGLScope3D.TiltType, degree: Float, lat: Float, lng: Float, sx: Float, sy: Float) {
        guard degree.isFinite,
              lat.isFinite,
              lng.isFinite,
              sx.isFinite,
              sy.isFinite,
              sx > 0,
              sy > 0 else {
            return
        }
        if type == .up {
            let newDegree = max(-180, min(180, degree))
            if newDegree != scope.panDegree {
                let degreeDelta = newDegree - (scope.panDegree )
                modelMatrix = IRMatrix4.multiply(modelMatrix, IRMatrix4.makeRotation(degreeDelta * .pi / 180.0, 1, 0, 0))
                scope.panDegree = newDegree
            }
        }
        scope.lat = lat
        scope.lng = lng
        updateBy(fx: 0, fy: 0, sx: sx, sy: sy, renew: true)
    }

    override func reset() {
        scope.w = 0
        scope.h = 0
        scope.scaleX = 1
        scope.scaleY = 1
        scope.panDegree = 0
        scope.lat = 0
        scope.lng = 0
        scope.tiltType = defaultType
        defaultTransformScaleX = scope.scaleX 
        defaultTransformScaleY = scope.scaleY 
    }

    override func resetViewport(width w: Int, height h: Int, resetTransform: Bool) {
        let oldDefaultScaleX = defaultTransformScaleX
        let oldDefaultScaleY = defaultTransformScaleY
        let oldTiltType = scope.tiltType

        if resetTransform {
            reset()
            scopeRange = scopeRange
            scope.lat = scopeRange?.defaultLat ?? 0
            scope.lng = scopeRange?.defaultLng ?? 0
        }

        scope.w = w
        scope.h = h
        defaultTransformScaleX = oldDefaultScaleX
        defaultTransformScaleY = oldDefaultScaleY
        let aspectRatio = Self.aspectRatio(width: w, height: h)
        let fovyRadians = fov * .pi / 180.0
        projectMatrix = IRMatrix4.makePerspective(fovyRadians, aspectRatio, 1.0, 1000.0)
        viewMatrix = IRMatrix4.identity()
        if oldTiltType != scope.tiltType {
            setupTilt(scope.tiltType )
        }
        setupScope(scope.tiltType, degree: scope.panDegree , lat: scope.lat , lng: scope.lng , sx: scope.scaleX , sy: scope.scaleY )
        updateVertices()
    }

    override func updateVertices() {
        guard let normalizedScope = Self.normalizedScope(
            lat: scope.lat,
            lng: scope.lng,
            fov: fov,
            range: scopeRange
        ) else {
            return
        }

        let lng = normalizedScope.lng + 180
        let phi = (90 - normalizedScope.lat) * .pi / 180.0
        let theta = lng * .pi / 180.0
        let cameraX = rc * sinf(phi) * cosf(theta)
        let cameraY = rc * cosf(phi)
        let cameraZ = rc * sinf(phi) * sinf(theta)
        guard lng.isFinite,
              phi.isFinite,
              theta.isFinite,
              rc.isFinite,
              cameraX.isFinite,
              cameraY.isFinite,
              cameraZ.isFinite else {
            return
        }
        scope.lat = normalizedScope.lat
        scope.lng = normalizedScope.lng
        camera[0] = cameraX
        camera[1] = cameraY
        camera[2] = cameraZ

        viewMatrix = IRMatrix4.makeLookAt(SIMD3<Float>(camera[0], camera[1], camera[2]),
                                          SIMD3<Float>(0, 0, 0),
                                          SIMD3<Float>(0, 1, 0))
    }
}
