//
//  IRGLProgramFactoryPolicy.swift
//  IRPlayer-swift
//
//  Created by Codex on 2026/6/2.
//

import Foundation

enum IRGLProgramFactoryPolicy {
    static func expandedScaleRange(from range: IRGLScaleRange, multiplier: Float) -> IRGLScaleRange {
        IRGLScaleRange(minScaleX: range.minScaleX,
                       minScaleY: range.minScaleY,
                       maxScaleX: range.maxScaleX * multiplier,
                       maxScaleY: range.maxScaleY * multiplier,
                       defaultScaleX: range.defaultScaleX,
                       defaultScaleY: range.defaultScaleY)
    }

    static func fisheyeScopeRange(from range: IRGLScopeRange, latmax: Float) -> IRGLScopeRange {
        let maxLat = range.maxLat > 0 ? latmax : latmax - 90.0
        var defaultLat = range.defaultLat
        if defaultLat > maxLat || defaultLat < range.minLat {
            defaultLat = (maxLat + range.minLat) / 2
        }
        return IRGLScopeRange(minLat: range.minLat,
                              maxLat: maxLat,
                              minLng: range.minLng,
                              maxLng: range.maxLng,
                              defaultLat: defaultLat,
                              defaultLng: range.defaultLng)
    }

    static func defaultFisheyeScope(from range: IRGLScopeRange, panelIndex: Int?) -> IRGLScopeRange {
        let defaultLng: Float
        switch panelIndex {
        case 1:
            defaultLng = 180
        case 2:
            defaultLng = 270
        case 3:
            defaultLng = 0
        default:
            defaultLng = 90
        }

        return IRGLScopeRange(minLat: range.minLat,
                              maxLat: range.maxLat,
                              minLng: range.minLng,
                              maxLng: range.maxLng,
                              defaultLat: -40,
                              defaultLng: defaultLng)
    }

    static func fisheyeParameter(from parameter: IRMediaParameter?) -> IRFisheyeParameter? {
        guard let parameter = parameter else {
            return IRFisheyeParameter(width: 0, height: 0, up: false, rx: 0, ry: 0, cx: 0, cy: 0, latmax: 0)
        }
        return parameter as? IRFisheyeParameter
    }
}
