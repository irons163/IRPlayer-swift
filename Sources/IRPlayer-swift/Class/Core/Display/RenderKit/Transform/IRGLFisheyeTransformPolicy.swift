import Foundation

enum IRGLFisheyeTransformPolicy {
    struct NormalizedScope: Equatable {
        let lat: Float
        let lng: Float
    }

    struct ScrollDecision: Equatable {
        let lat: Float
        let lng: Float
        let status: IRGLTransformController.ScrollStatus
    }

    struct ScaleDecision: Equatable {
        let scale: Float
        let fovDegrees: Float
    }

    static func scopeRange(for type: IRGLScope3D.TiltType) -> IRGLScopeRange {
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

    static func aspectRatio(width: Int, height: Int) -> Float {
        guard width > 0, height > 0 else { return 1.0 }
        return Float(width) / Float(height)
    }

    static func scaleDecision(requestedScale: Float, maxScale: Float, tanbase: Float) -> ScaleDecision? {
        guard requestedScale.isFinite, maxScale.isFinite, tanbase.isFinite, requestedScale > 0 else {
            return nil
        }

        let scale: Float
        if requestedScale <= 1.0 {
            scale = 1
        } else {
            scale = requestedScale > maxScale ? maxScale : requestedScale
        }

        let newFov = atan(Double(tanbase) / Double(scale)) * 2
        return ScaleDecision(scale: scale, fovDegrees: Float(newFov * (180 / .pi)))
    }

    static func scrollDecision(
        currentLat: Float,
        currentLng: Float,
        dx: Float,
        dy: Float,
        friction: Float,
        range: IRGLScopeRange?
    ) -> ScrollDecision? {
        guard dx.isFinite, dy.isFinite, friction.isFinite else { return nil }

        let nextLng = -dx * friction + currentLng
        let nextLat = -dy * friction + currentLat
        var status: IRGLTransformController.ScrollStatus = []

        if min(range?.maxLng ?? 0, nextLng) == range?.maxLng {
            status.insert(.toMaxX)
        } else if max(range?.minLng ?? 0, nextLng) == range?.minLng {
            status.insert(.toMinX)
        }

        if min(range?.maxLat ?? 0, nextLat) == range?.maxLat {
            status.insert(.toMaxY)
        } else if max(range?.minLat ?? 0, nextLat) == range?.minLat {
            status.insert(.toMinY)
        }

        return ScrollDecision(lat: nextLat, lng: nextLng, status: status)
    }

    static func normalizedScope(lat: Float, lng: Float, fov: Float, range: IRGLScopeRange?) -> NormalizedScope {
        var normalizedLat = lat
        var normalizedLng = lng

        while normalizedLat > 90 {
            normalizedLat -= 180
        }
        while normalizedLat <= -90 {
            normalizedLat = 180 + normalizedLat
        }
        normalizedLat = max(range?.minLat ?? 0, min((range?.maxLat ?? 0) - fov / 2, normalizedLat))

        while normalizedLng > 180 {
            normalizedLng -= 360
        }
        while normalizedLng <= -180 {
            normalizedLng = 360 + normalizedLng
        }
        normalizedLng = max(range?.minLng ?? 0, min(range?.maxLng ?? 0, normalizedLng))

        return NormalizedScope(lat: normalizedLat, lng: normalizedLng)
    }
}
