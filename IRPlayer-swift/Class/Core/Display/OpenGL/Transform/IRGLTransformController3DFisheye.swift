//
//  IRGLTransformController3DFisheye.swift
//  IRPlayer-swift
//
//  Created by irons on 2024/9/7.
//

import Foundation
import GLKit

class IRGLTransformController3DFisheye: IRGLTransformController {
    var camera: [Float] = [0, 0, 0]
    var rc: Float = 0
    var fov: Float = 0
    var tanbase: Float = 0
    var projectMatrix = GLKMatrix4Identity
    var modelMatrix = GLKMatrix4Identity
    var viewMatrix = GLKMatrix4Identity

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

        let aspectRatio = Float(width) / Float(height)
        let fovyRadians = fov * .pi / 180.0
        projectMatrix = GLKMatrix4MakePerspective(fovyRadians, aspectRatio, 1.0, 1000.0)
        viewMatrix = GLKMatrix4Identity

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
        switch type {
        case .up:
            return IRGLScopeRange(minLat: -80, maxLat: 80, minLng: -75, maxLng: 75, defaultLat: 0, defaultLng: 0)
        case .toward:
            return IRGLScopeRange(minLat: 0, maxLat: 80, minLng: -180, maxLng: 180, defaultLat: 80, defaultLng: -90)
        case .backward:
            return IRGLScopeRange(minLat: -85, maxLat: -20, minLng: -180, maxLng: 180, defaultLat: -80, defaultLng: 90)
        default:
            return IRGLScopeRange(minLat: 0, maxLat: 0, minLng: 0, maxLng: 0, defaultLat: 0, defaultLng: 0)
        }
    }

    override func getModelViewProjectionMatrix() -> GLKMatrix4 {
        let mv = GLKMatrix4Multiply(viewMatrix, modelMatrix)
        let mvp = GLKMatrix4Multiply(projectMatrix, mv)
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
        let oldScale = scope.scaleX 
        if sx <= 1.0 {
            scope.scaleX = 1
            scope.scaleY = 1
        } else {
            let s2 = sx > (scaleRange?.maxScaleX ?? 1) ? scaleRange?.maxScaleX ?? 1 : sx
            scope.scaleX = s2
            scope.scaleY = s2
        }

        if oldScale != scope.scaleX {
            let newFov = atan(Double(tanbase) / Double(scope.scaleX )) * 2
            fov = Float(newFov * (180 / .pi))
            let aspectRatio = Float(scope.w ) / Float(scope.h )
            let fovyRadians = fov * .pi / 180.0
            projectMatrix = GLKMatrix4MakePerspective(fovyRadians, aspectRatio, 1.0, 1000.0)
            updateVertices()
        } else if renew {
            updateVertices()
        }
    }

    override func scroll(dx: Float, dy: Float) {
        let oldLng = scope.lng
        let oldLat = scope.lat

        scope.lng = -dx * DRAG_FRICTION + scope.lng
        scope.lat = -dy * DRAG_FRICTION + scope.lat

        var status: IRGLTransformController.ScrollStatus = []

        if min(scopeRange?.maxLng ?? 0, scope.lng) == scopeRange?.maxLng {
            status.insert(.toMaxX)
        } else if max(scopeRange?.minLng ?? 0, scope.lng) == scopeRange?.minLng {
            status.insert(.toMinX)
        }

        if min(scopeRange?.maxLat ?? 0, scope.lat) == scopeRange?.maxLat {
            status.insert(.toMaxY)
        } else if max(scopeRange?.minLat ?? 0, scope.lat) == scopeRange?.minLat {
            status.insert(.toMinY)
        }

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
            modelMatrix = GLKMatrix4MakeRotation(INITIAL_PITCH_DEGREES * .pi / 180.0, 1, 0, 0)
        case .toward:
            modelMatrix = GLKMatrix4MakeRotation(-90 * .pi / 180.0, 0, 0, 1)
        case .backward:
            modelMatrix = GLKMatrix4MakeRotation(90 * .pi / 180.0, 0, 0, 1)
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
                modelMatrix = GLKMatrix4Rotate(modelMatrix, degreeDelta * .pi / 180.0, 1, 0, 0)
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
        let aspectRatio = Float(w) / Float(h)
        let fovyRadians = fov * .pi / 180.0
        projectMatrix = GLKMatrix4MakePerspective(fovyRadians, aspectRatio, 1.0, 1000.0)
        viewMatrix = GLKMatrix4Identity
        if oldTiltType != scope.tiltType {
            setupTilt(scope.tiltType )
        }
        setupScope(scope.tiltType, degree: scope.panDegree , lat: scope.lat , lng: scope.lng , sx: scope.scaleX , sy: scope.scaleY )
        updateVertices()
    }

    override func updateVertices() {
        while scope.lat > 90 {
            scope.lat = scope.lat - 180
        }
        while scope.lat <= -90 {
            scope.lat = 180 + scope.lat
        }
        scope.lat = max(scopeRange?.minLat ?? 0, min((scopeRange?.maxLat ?? 0) - fov / 2, scope.lat))
        while scope.lng > 180 {
            scope.lng = scope.lng - 360
        }
        while scope.lng <= -180 {
            scope.lng = 360 + scope.lng
        }
        scope.lng = max(scopeRange?.minLng ?? 0, min(scopeRange?.maxLng ?? 0, scope.lng))

        let lng = scope.lng + 180
        let phi = (90 - scope.lat) * .pi / 180.0
        let theta = lng * .pi / 180.0

        camera[0] = rc * sinf(phi) * cosf(theta)
        camera[1] = rc * cosf(phi)
        camera[2] = rc * sinf(phi) * sinf(theta)

        viewMatrix = GLKMatrix4MakeLookAt(camera[0], camera[1], camera[2], 0, 0, 0, 0, 1, 0)
    }
}
