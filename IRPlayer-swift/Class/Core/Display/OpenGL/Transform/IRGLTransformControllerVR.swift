//
//  IRGLTransformControllerVR.swift
//  IRPlayer-swift
//
//  Created by irons on 2024/9/7.
//

import Foundation
import GLKit

class IRGLTransformControllerVR: IRGLTransformController3DFisheye {

    override init(viewportWidth width: Int, viewportHeight height: Int, tileType type: TiltType) {
        super.init(viewportWidth: width, viewportHeight: height, tileType: type)
    }

    override class func getScopeRange(of type: TiltType) -> IRGLScopeRange {
        switch type {
        case .TILT_UP:
            return IRGLScopeRange(minLat: -190, maxLat: 190, minLng: -180, maxLng: 180, defaultLat: 0, defaultLng: 0)
        case .TILT_TOWARD:
            return IRGLScopeRange(minLat: -90, maxLat: 90, minLng: -180, maxLng: 180, defaultLat: 0, defaultLng: 0)
        case .TILT_BACKWARD:
            return IRGLScopeRange(minLat: -90, maxLat: 90, minLng: -180, maxLng: 180, defaultLat: 0, defaultLng: 0)
        default:
            return IRGLScopeRange(minLat: 0, maxLat: 0, minLng: 0, maxLng: 0, defaultLat: 0, defaultLng: 0)
        }
    }

    override func scroll(dx: Float, dy: Float) {
        super.scroll(dx: dx, dy: -dy)
    }
}