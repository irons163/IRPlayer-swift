//
//  IRGLTransformController3DFisheye.swift
//  IRPlayer-swift
//
//  Metal-only implementation (OpenGL-free)
//

import Foundation
import simd

class IRGLTransformController3DFisheye: IRGLTransformController {
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
        return IRGLFisheyeTransformPolicy.scopeRange(for: type)
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
              let decision = IRGLFisheyeTransformPolicy.scaleDecision(
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
        guard let decision = IRGLFisheyeTransformPolicy.scrollDecision(
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
        if scope.tiltType != .up { return }
        let totalDegree = (scope.panDegree ) + degree
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
        let normalizedScope = IRGLFisheyeTransformPolicy.normalizedScope(
            lat: scope.lat,
            lng: scope.lng,
            fov: fov,
            range: scopeRange
        )
        scope.lat = normalizedScope.lat
        scope.lng = normalizedScope.lng

        let lng = scope.lng + 180
        let phi = (90 - scope.lat) * .pi / 180.0
        let theta = lng * .pi / 180.0

        camera[0] = rc * sinf(phi) * cosf(theta)
        camera[1] = rc * cosf(phi)
        camera[2] = rc * sinf(phi) * sinf(theta)

        viewMatrix = IRMatrix4.makeLookAt(SIMD3<Float>(camera[0], camera[1], camera[2]),
                                          SIMD3<Float>(0, 0, 0),
                                          SIMD3<Float>(0, 1, 0))
    }

    static func aspectRatio(width: Int, height: Int) -> Float {
        return IRGLFisheyeTransformPolicy.aspectRatio(width: width, height: height)
    }
}
